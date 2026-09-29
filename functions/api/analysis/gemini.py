"""api/analysis/gemini.py — the Gemini report pipeline.

On trigger: assemble a compact context window (recent daily health,
upcoming calendar events, the latest matches, the league table and the
previous report for continuity), send it to Gemini with a versioned prompt, parse a structured
JSON response, and store the report.

Ported from fitness-dashboard with the prompt unchanged, so a report
generated here is comparable with one generated there (phase 5 of the
port). What changed is only where the rows come from: the Firestore store
instead of SQLAlchemy.
"""

from __future__ import annotations

import json
import logging
import time
from datetime import UTC, date, datetime, timedelta

import requests

from api.config import settings
from api.integrations import gemini_models
from api.integrations.gemini_models import api_key_header
from api.integrations.google_health import local_tz
from api.services import drinks, gemini_usage
from api.services.exercises import sessions_since
from api.services.health import Measurement, latest_measurements
from api.services.league import Standing, match_standings, our_row, points_per_game, upcoming_fixtures
from api.services.matches import newest_first
from api.services.push import notify_report_ready
from api.services.reports import report_exists_today
from api.services.sessions import ExerciseSession
from api.services.training import get_training_status
from api.store.firestore import FirestoreStore
from api.store.rows import AiReport, CalendarEvent, DailyHealth, LeagueTable, MatchPerformance

logger = logging.getLogger("api.analysis.gemini")

# The model is GEMINI_MODEL, normally the rolling gemini-flash-latest alias,
# with a fallback one release below it for a second requests-per-day budget
# (ADR-013, ADR-025 in fitness-dashboard; api/integrations/gemini_models.py).
GEMINI_API_URL = "https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"

# v2 (2026-08): training_status gained readiness_score, and the context
# gained recent_exercises.
# v3 (2026-08): the context gained training_series — the daily Fitness /
# Fatigue / Form track, not just today's snapshot.
# v4 (2026-08): the context gained latest_measurements — the last weight and
# VO2 max with their dates, so the gaps between weigh-ins stop reading to the
# model as missing data (ADR-018).
# v5 (2026-09): the context gained alcohol — the user's own beer log, and the
# only number here nothing measured for them (ADR-019).
# v6 (2026-09): the context gained league — the table, and each match and
# fixture with the opponent's standing next to ours.
PROMPT_VERSION = "v6"

CONTEXT_HEALTH_DAYS_BACK = 14
CONTEXT_CALENDAR_DAYS_AHEAD = 14
CONTEXT_MATCH_LIMIT = 5
# The next few fixtures, with the opponent's standing. Three reaches past the
# next weekend without turning the league section into the season schedule.
CONTEXT_FIXTURE_LIMIT = 3
# Shorter than the health window on purpose: sessions are the busiest
# part of the context (one entry per workout, each with an open bag of
# metrics), and a fortnight of them would crowd out the summary rows.
CONTEXT_EXERCISE_DAYS_BACK = 7

# How many days of the daily Fitness / Fatigue / Form series to include when
# no wider window is asked for (the daily report, and the coach at its
# default). ~2× the 42-day fitness time constant — long enough to show a
# block build and where form is heading, ~1.5k tokens. A coach lookback
# overrides it and the series is still daily, never downsampled: form on a
# match day is the number that matters, so every day is kept.
CONTEXT_TRAINING_SERIES_DAYS = 90


def _require_api_key() -> None:
    if not settings.gemini_api_key:
        raise RuntimeError("GEMINI_API_KEY is not set — add it to Secret Manager")


def _serialize_health(rows: list[DailyHealth]) -> list[dict]:
    return [
        {
            "date": row.date.isoformat(),
            "steps": row.steps,
            "resting_hr": row.resting_hr,
            "hrv_ms": row.hrv_ms,
            "sleep_minutes": row.sleep_minutes,
            "weight_kg": row.weight_kg,
            "vo2max": row.vo2max,
        }
        for row in rows
    ]


def _serialize_events(rows: list[CalendarEvent]) -> list[dict]:
    # start_ts is stored in UTC — convert to the user's local timezone before
    # handing it to Gemini, otherwise the model has no way to know the offset
    # and just echoes the UTC hour as if it were local (e.g. a 19:00 Vienna
    # event reported back as "17:00").
    return [
        {
            "title": row.title,
            "start": row.start_ts.astimezone(local_tz()).isoformat() if row.start_ts else None,
            "all_day": row.all_day,
        }
        for row in rows
    ]


def _match_outcome(result: str | None, home_away: str) -> tuple[int | None, int | None, str | None]:
    """`result` is always written home-goals-first (oefb/parser.py), so which
    half is ours depends on `home_away`. Resolving that here — instead of
    handing the model "result": "1:2" and trusting it to also apply
    home_away — is what fixed the coach reporting an away loss as a win: it
    was reading the raw home-first score as if it were always our score."""
    if not result:
        return None, None, None
    try:
        home_goals, away_goals = (int(g) for g in result.split(":"))
    except ValueError:
        return None, None, None
    our, their = (home_goals, away_goals) if home_away == "home" else (away_goals, home_goals)
    outcome = "W" if our > their else "L" if our < their else "D"
    return our, their, outcome


def _serialize_standing(standing: Standing | None) -> dict | None:
    """The opponent's row next to ours. `strength` is pre-computed from the
    points-per-game difference (api/services/league.py), so the model reads
    one word instead of re-deriving it from ranks."""
    if standing is None:
        return None
    return {
        "opponent_rank": standing.rank,
        "opponent_points": standing.points,
        "opponent_played": standing.played,
        "opponent_points_per_game": standing.points_per_game,
        "our_rank": standing.our_rank,
        "our_points": standing.our_points,
        "our_points_per_game": standing.our_points_per_game,
        "points_gap": standing.points_gap,
        "strength": standing.strength,
        "table_day": standing.table_day.isoformat(),
    }


def _serialize_league(table: LeagueTable | None, store: FirestoreStore) -> dict | None:
    """The league table and the next fixtures. None before the first scrape
    has stored a table."""
    if table is None:
        return None
    ours = our_row(table)
    fixtures = upcoming_fixtures(store, datetime.now(UTC), table)[:CONTEXT_FIXTURE_LIMIT]
    return {
        "league": table.league,
        "table_day": table.day.isoformat(),
        "our_standing": {
            "rank": ours.rank,
            "played": ours.played,
            "points": ours.points,
            "points_per_game": points_per_game(ours),
            "goal_difference": ours.goal_difference,
        }
        if ours
        else None,
        "table": [
            {
                "rank": row.rank,
                "team": row.team,
                "played": row.played,
                "points": row.points,
                "goal_difference": row.goal_difference,
                **({"is_us": True} if row.is_us else {}),
            }
            for row in table.rows
        ],
        "next_fixtures": [
            {
                "kickoff": f.kickoff.astimezone(local_tz()).isoformat() if f.kickoff else None,
                "opponent": f.opponent,
                "home_away": f.home_away,
                "competition": f.art,
                "opponent_standing": _serialize_standing(f.opponent_standing),
            }
            for f in fixtures
        ],
    }


def _serialize_matches(
    rows: list[MatchPerformance], standings: dict[str, Standing] | None = None
) -> list[dict]:
    """`standings` puts the opponent's place in the table before kick-off
    on each match that has one."""
    standings = standings or {}
    serialized = []
    for row in rows:
        our_score, opponent_score, outcome = _match_outcome(row.result, row.home_away)
        serialized.append(
            {
                "date": row.match_date.isoformat() if row.match_date else None,
                "opponent": row.opponent,
                "home_away": row.home_away,
                "our_score": our_score,
                "opponent_score": opponent_score,
                "outcome": outcome,
                "minutes_played": row.minutes_played,
                "goals": row.goals,
                "yellow_card": row.yellow_card,
                "red_card": row.red_card,
                "opponent_standing": _serialize_standing(standings.get(row.oefb_game_id)),
            }
        )
    return serialized


def _serialize_exercises(sessions: list[ExerciseSession]) -> list[dict]:
    # `metrics` is passed through under Google's own field names (ADR-012),
    # which carry their units — distanceMillimeters, averagePaceSecondsPerMeter
    # — so the model can read them without a legend. Renaming them here would
    # mean maintaining that legend for a set of keys that varies by activity.
    return [
        {
            "date": s.date.isoformat(),
            "start": s.start_ts.astimezone(local_tz()).isoformat() if s.start_ts else None,
            "type": s.exercise_type,
            "duration_minutes": s.duration_minutes,
            "active_zone_minutes": s.active_zone_minutes,
            "average_heart_rate": s.average_heart_rate,
            **({"metrics": s.metrics} if s.metrics else {}),
        }
        for s in sessions
    ]


def _serialize_latest_measurements(measurements: dict[str, Measurement], today: date) -> dict | None:
    """The last known weight / VO2 max, with the day each was measured and
    how long ago that was (ADR-018).

    Without this the model reads the nulls in `recent_daily_health` as "no
    weight data" and says so — which is exactly what it did — even when the
    user weighed themselves two days ago. `days_ago` is written out rather
    than left as a subtraction: it is what the answer turns on (a weight
    from two days ago is current, one from two months ago is a footnote),
    and it costs one field to spare the model the arithmetic."""
    if not measurements:
        return None
    return {
        name: {
            "value": m.value,
            "date": m.date.isoformat(),
            "days_ago": (today - m.date).days,
        }
        for name, m in measurements.items()
    }


def _serialize_alcohol(store: FirestoreStore, today: date, days_back: int) -> dict | None:
    """The user's own beer log (ADR-019) — the counter since the last
    report, plus the recent days it came from.

    `since_last_report` is the number the Today tab's stepper is showing
    right now, and it is deliberately *not* a calendar day: it is the drinks
    no report has spoken for yet, which on a normal day is last night's.

    None when there is nothing to say — no pending drinks and nothing logged
    in the window — so a user who never taps the button never has a report
    telling them they drank zero beers. `unit` spells out what a count is
    worth, so the model reasons about a dose rather than guessing a glass
    size.
    """
    counter = drinks.pending(store)
    history = drinks.daily_counts(store, today - timedelta(days=days_back))
    if not counter.count and not history:
        return None

    def local(at: datetime | None) -> str | None:
        return at.astimezone(local_tz()).isoformat() if at else None

    return {
        "unit": f"one {drinks.DRINK_VOLUME_L} L beer (~{drinks.DRINK_ALCOHOL_GRAMS} g of alcohol) per count",
        "since_last_report": {
            "count": counter.count,
            "first_logged_at": local(counter.first_logged_at),
            "last_logged_at": local(counter.last_logged_at),
        },
        "daily_counts": [{"date": d.date.isoformat(), "count": d.count} for d in history],
    }


def _serialize_training_status(status) -> dict | None:
    if status.status == "insufficient_data":
        return None
    return {
        "status": status.status,
        "headline": status.headline,
        "fitness_42d_avg": status.fitness,
        "fatigue_7d_avg": status.fatigue,
        "form_fitness_minus_fatigue": status.form,
        "form_bands": (
            "below -30 overreaching, -10 to -30 productive, -10 to +10 maintaining, +10 to +25 primed"
        ),
        "form_pct_of_fitness": status.form_pct,
        "fitness_ramp_pct_per_week": status.ramp_pct,
        "recovery_score": status.recovery,
        "readiness_score": status.readiness,
    }


def _serialize_training_series(status) -> list[dict] | None:
    """The daily Fitness / Fatigue / Form track, oldest first. `form` is
    written out (Fitness − Fatigue) rather than left for the model to
    subtract per row. Kept daily on purpose — never downsampled — so form
    on any given match day is in there exactly."""
    if status.status == "insufficient_data" or not status.series:
        return None
    return [
        {
            "date": point.date,
            "fitness": point.fitness,
            "fatigue": point.fatigue,
            "form": round(point.fitness - point.fatigue, 1),
            "load": point.load,
        }
        for point in status.series
    ]


def build_context(store: FirestoreStore, *, lookback_days: int | None = None) -> dict:
    """Assemble the JSON context. `lookback_days`, when given (the coach's
    History selector), widens the health / exercise / match windows to that
    many days back; the daily report leaves it None and gets the fixed
    CONTEXT_* windows. Calendar stays forward-looking either way."""
    today = datetime.now(local_tz()).date()

    health_days = lookback_days or CONTEXT_HEALTH_DAYS_BACK
    exercise_days = lookback_days or CONTEXT_EXERCISE_DAYS_BACK

    health_rows = sorted(
        store.health_days(first=today - timedelta(days=health_days)), key=lambda row: row.date, reverse=True
    )

    now = datetime.now(UTC)
    event_rows = store.calendar_events(now, now + timedelta(days=CONTEXT_CALENDAR_DAYS_AHEAD))

    matches = newest_first(store)
    if lookback_days is None:
        match_rows = matches[:CONTEXT_MATCH_LIMIT]
    else:
        since = today - timedelta(days=lookback_days)
        match_rows = [m for m in matches if m.match_date is not None and m.match_date >= since]

    exercise_sessions = sessions_since(store, today - timedelta(days=exercise_days))

    previous_report = store.latest_report()

    # One computation, two views: the maths always runs over the full history
    # (get_training_status only trims what it returns), so `days` costs
    # nothing but the length of the series handed on.
    series_days = lookback_days or CONTEXT_TRAINING_SERIES_DAYS
    training = get_training_status(store, days=series_days)

    return {
        "today": today.isoformat(),
        "recent_daily_health": _serialize_health(health_rows),
        "latest_measurements": _serialize_latest_measurements(latest_measurements(store), today),
        "training_status": _serialize_training_status(training),
        "training_series": _serialize_training_series(training),
        "recent_exercises": _serialize_exercises(exercise_sessions),
        "alcohol": _serialize_alcohol(store, today, health_days),
        "upcoming_events": _serialize_events(event_rows),
        "recent_matches": _serialize_matches(match_rows, match_standings(store, match_rows)),
        "league": _serialize_league(store.league_table(), store),
        "previous_report_summary": previous_report.summary_md if previous_report else None,
    }


PROMPT_TEMPLATE = """You are a personal fitness coach analysing data for one person. \
Today's date is {today}. All timestamps in the data below are already in the \
user's local timezone ({tz}) — use their hours as-is, no conversion needed. \
Use the JSON data below to write a short daily briefing. `training_status` \
(when present) is a pre-computed impulse-response model over daily Active \
Zone Minutes: fitness is a 42-day average, fatigue a 7-day average, form is \
fitness minus fatigue, and `recovery_score` and `readiness_score` (both \
0-100) come from HRV/resting HR/sleep against a 28-day baseline. The two \
scores differ only in how much of "now" they average: `recovery_score` uses \
the last three days, so it reads as a trend, while `readiness_score` uses \
last night alone and reacts to a single good or bad night — quote \
`readiness_score` when talking about today and `recovery_score` when talking \
about the week. Treat these as authoritative for readiness and training \
load — don't re-derive them from the raw health rows. `training_series` is \
that same model's daily history — one {{date, fitness, fatigue, form, load}} \
row per day, oldest first — so you can talk about the direction fitness and \
form have moved, not just today's value, and line form up against the dates \
of matches and upcoming events. `latest_measurements` carries the metrics \
that are not recorded every day — weight and VO2 max, which only land when \
the user steps on the scale or the watch re-estimates. A null for those in \
`recent_daily_health` means "not measured that day", not "unknown": the value \
in `latest_measurements` is the current one, and `days_ago` says how stale it \
is. Quote it as the current number rather than reporting the data as missing, \
and say how old it is only when it is old enough to have moved. \
`recent_exercises` \
lists the individual tracked workouts of the last {exercise_days} days, \
newest first — the sessions behind those daily Active Zone Minutes. Use \
them for what the summary rows cannot show: which activity the load came \
from, and how hard and how long each session was. `metrics` on a session \
is whatever else the watch recorded, under field names that carry their own \
units. `alcohol`, when present, is the only thing here the user logged by \
hand: `since_last_report.count` is the drinks they have tapped in since the \
last report claimed them — usually last night — and `daily_counts` is the \
recent history by day. Read it as evidence about sleep quality, resting HR \
and HRV rather than as a moral question, and only bring it up when there is \
something to say: a night that explains a metric, or a run of days worth \
naming. A count of 0 is not worth a sentence. `league`, when present, is \
the league table as of `table_day`, with `next_fixtures`; a fixture's and \
a recent match's `opponent_standing` puts the opponent next to us \
(`points_gap` is theirs minus ours, `strength` compares points per game: \
stronger, level or weaker). Use it for the physical side only: a stronger \
opponent usually means more defending and more high-intensity running, so \
say how to arrive fresh for that one; read a result in its light (a loss \
to a stronger side is not a fitness warning on its own). No tactics, no \
predictions of the score.

Data:
{context_json}

Respond with ONLY a JSON object (no markdown fences) matching this shape:
{{
  "summary_md": "<a few short paragraphs in Markdown: how they're trending, \
anything notable in sleep/HR/HRV/steps, how upcoming matches/events line up \
with recovery, and 1-3 concrete recommendations. Reference the previous \
report's summary if given, for continuity, without repeating it verbatim.>",
  "insights": {{
    "readiness": "<one of: high, moderate, low — your own call for today, \
informed by readiness_score and the training load, not a restatement of \
either>",
    "readiness_reason": "<one sentence>",
    "trends": ["<short bullet>", "..."],
    "recommendations": ["<short bullet>", "..."],
    "flags": ["<anything concerning, or empty list>"]
  }}
}}
"""


def build_prompt(context: dict) -> str:
    return PROMPT_TEMPLATE.format(
        today=context["today"],
        tz=settings.health_local_tz,
        exercise_days=CONTEXT_EXERCISE_DAYS_BACK,
        context_json=json.dumps(context, indent=2),
    )


# 503 is "the model is overloaded, come back in a moment" — a one- or
# two-second backoff genuinely clears it. 429 is a quota refusal, and the
# shortest window it can refer to is a minute, so retrying the same model
# 1-2s later cannot help; it only delays the error the caller already has.
# We move to the next model instead, which has its own daily budget.
# 404 is a retired model id (ADR-025) — nothing to retry, but the next
# candidate may still exist.
_OVERLOADED_STATUS = 503
_QUOTA_STATUS = 429
_NOT_FOUND_STATUS = 404

# usageMetadata's counts, in the order the log line prints them. Gemini
# omits a count that is zero (no cache hit, no thinking), hence the 0s.
# Thinking tokens are billed as output but are not in candidatesTokenCount.
_USAGE_FIELDS = (
    ("prompt", "promptTokenCount"),
    ("cached", "cachedContentTokenCount"),
    ("output", "candidatesTokenCount"),
    ("thinking", "thoughtsTokenCount"),
    ("total", "totalTokenCount"),
)


def _log_usage(purpose: str, model: str, data: dict) -> None:
    """One line per answered request, for comparing token costs over time:
    search Cloud Logging for "Gemini usage". The report also stores its
    total (AiReport.tokens_used); this is the only record of the chat's."""
    usage = data.get("usageMetadata") or {}
    counts = " ".join(f"{name}={usage.get(key, 0)}" for name, key in _USAGE_FIELDS)
    logger.info("Gemini usage: purpose=%s model=%s %s", purpose, model, counts)


def _post_gemini(
    store: FirestoreStore,
    body: dict,
    max_retries: int = 2,
    only: list[str] | None = None,
    purpose: str = "report",
) -> tuple[dict, str]:
    """POST to the Gemini generateContent endpoint; returns the parsed
    response and the model that actually answered.

    Retries 503 on the same model with a short backoff; on 429 it stops
    retrying that model and tries the next candidate, whose requests-per-day
    quota Google counts separately (ADR-013). Every attempt is recorded
    against the day's budget. The coach chat (chat_completion) sends
    through here too.

    `only` narrows the candidates, for the evening report's last try on the
    fallback model alone (run_daily_fallback). `purpose` only labels the
    token-usage log line."""
    _require_api_key()

    configured = gemini_models.candidates()
    if not configured:
        raise RuntimeError("GEMINI_MODEL is not set")
    models = only or configured

    unavailable: requests.Response | None = None

    for model in models:
        url = GEMINI_API_URL.format(model=model)
        for attempt in range(max_retries + 1):
            resp = requests.post(url, headers=api_key_header(), json=body, timeout=60)
            # Counted here because this is the only line in the process that
            # sends one, and because it went out whatever it came back as: a
            # 429 or a 500 is still a request against the day (ADR-013). A
            # connection error raises before this and is not counted — we
            # cannot know whether Google saw it.
            gemini_usage.record(store, model)
            if resp.status_code == _OVERLOADED_STATUS and attempt < max_retries:
                wait = 2**attempt
                logger.warning(
                    "Gemini 503 on %s, retrying in %ss (attempt %d/%d)", model, wait, attempt + 1, max_retries
                )
                time.sleep(wait)
                continue
            if resp.status_code == _QUOTA_STATUS:
                logger.warning("Gemini 429 on %s — out of quota, falling through", model)
                unavailable = resp
                break
            if resp.status_code == _NOT_FOUND_STATUS:
                logger.error(
                    "Gemini 404 on %s — model retired or misspelt, falling through; "
                    "fix GEMINI_MODEL / GEMINI_FALLBACK_MODEL",
                    model,
                )
                unavailable = resp
                break
            resp.raise_for_status()
            if model != configured[0]:
                logger.info("Gemini answered on fallback model %s", model)
            data = resp.json()
            # An alias like gemini-flash-latest names no model; modelVersion
            # is the one that actually answered (ADR-025), and what the
            # rolling fallback has to stay below.
            served = data.get("modelVersion")
            if model == configured[0]:
                gemini_models.note_primary_answered(served)
            _log_usage(purpose, served or model, data)
            return data, served or model

    # Only reachable when every candidate refused on quota or was gone:
    # re-raise the last one so the router turns it into its usual 502.
    unavailable.raise_for_status()
    raise RuntimeError("No configured Gemini model is available")


def call_gemini(
    store: FirestoreStore, prompt: str, max_retries: int = 2, only: list[str] | None = None
) -> tuple[dict, int | None, str]:
    data, model = _post_gemini(
        store,
        {
            "contents": [{"parts": [{"text": prompt}]}],
            "generationConfig": {"responseMimeType": "application/json"},
        },
        max_retries=max_retries,
        only=only,
    )

    text = data["candidates"][0]["content"]["parts"][0]["text"]
    # responseMimeType=json usually returns exactly one JSON value, but
    # occasionally trails extra text after it — parse just the first
    # value rather than requiring the whole string to be valid JSON.
    parsed, _end = json.JSONDecoder().raw_decode(text.strip())
    tokens_used = data.get("usageMetadata", {}).get("totalTokenCount")
    return parsed, tokens_used, model


def chat_completion(store: FirestoreStore, system: str, messages: list[dict]) -> str:
    """Plain-text chat reply for the coach. `messages` is
    [{"role": "user"|"assistant", "content": str}, ...]; our "assistant"
    maps to Gemini's "model" role."""
    data, _model = _post_gemini(
        store,
        {
            "systemInstruction": {"parts": [{"text": system}]},
            "contents": [
                {
                    "role": "model" if m["role"] == "assistant" else "user",
                    "parts": [{"text": m["content"]}],
                }
                for m in messages
            ],
        },
        purpose="coach",
    )
    return data["candidates"][0]["content"]["parts"][0]["text"]


def run_analysis(
    store: FirestoreStore, trigger: str, max_retries: int = 2, only: list[str] | None = None
) -> AiReport:
    started = time.perf_counter()
    # The report may spend the whole day's budget — it is what the reserve
    # is held for — but not more than exists. Past that Google refuses it
    # anyway, and failing here says so in a sentence.
    gemini_usage.require_report_budget(store)

    # Asked before the new report exists, because the report itself would
    # answer it: only the *first* report of a local day resets the beer
    # counter, so a second one generated the same evening reports the same
    # drinks again rather than zeroing a night still in progress (ADR-019).
    first_today = not report_exists_today(store)

    context = build_context(store)
    prompt = build_prompt(context)

    gemini_started = time.perf_counter()
    parsed, tokens_used, model = call_gemini(store, prompt, max_retries=max_retries, only=only)
    gemini_seconds = time.perf_counter() - gemini_started

    health_dates = [h["date"] for h in context["recent_daily_health"]]

    report = AiReport(
        id=store.next_ids("reports")[0],
        created_at=datetime.now(UTC),
        trigger=trigger,
        period_start=date.fromisoformat(min(health_dates)) if health_dates else None,
        period_end=date.fromisoformat(max(health_dates)) if health_dates else None,
        # The model that actually answered, which is not always the
        # configured primary — see _post_gemini's quota fallback.
        model=model,
        prompt_version=PROMPT_VERSION,
        summary_md=parsed.get("summary_md", ""),
        insights=parsed.get("insights", {}),
        tokens_used=tokens_used,
    )
    # The report and the drinks it counted go in one batch, so a report
    # that fails to save cannot leave the counter reset behind it.
    counted = drinks.close_out(store, report) if first_today else None
    if counted is None:
        store.put_report(report)

    # The "Analyzing…" half of New report (ADR-027): the whole run, and the
    # Gemini call inside it, which is nearly all of it.
    logger.info(
        "Saved report id=%s trigger=%s tokens=%s drinks_counted=%s — took %.1fs, Gemini %.1fs",
        report.id,
        trigger,
        tokens_used,
        "not first today" if counted is None else counted,
        time.perf_counter() - started,
        gemini_seconds,
    )
    return report


def run_daily_fallback(store: FirestoreStore, last_try: bool = False) -> str:
    """The end-of-day safety net (ADR-004): a report only if nothing else
    produced one today — a New report tap already covered the day, and
    re-running would just spend Gemini budget to say the same thing.
    Called from the hourly job; returns what it did, for the job's log line.

    The job calls it at WAKE_FALLBACK_HOUR and again an hour later with
    `last_try`, which only does anything if the first left the day without
    a report (ADR-034). On the last try a Gemini failure gets one more
    attempt, on the fallback model alone and without retries: a primary
    that is still overloaded an hour later is not about to recover, and
    one request of the fallback's budget is worth the day's report.

    Then it pushes the report to every registered device (ADR-030). A push
    that fails is logged and leaves the report standing: it is already
    saved, and the app shows it on the next open either way."""
    if report_exists_today(store):
        return "skipped (today already has a report)"
    note = ""
    try:
        report = run_analysis(store, "daily_fallback")
    except requests.RequestException:
        fallback = gemini_models.candidates()[1:]
        if not last_try or not fallback:
            raise
        logger.warning("Evening report failed again; one try on the fallback model %s", fallback[0])
        report = run_analysis(store, "daily_fallback", max_retries=0, only=fallback[:1])
        note = f" on the fallback model {fallback[0]}"
    try:
        pushed = notify_report_ready(store, report)
    except Exception as exc:  # noqa: BLE001 — logged; the report itself is saved
        logger.exception("Push after the daily report failed")
        pushed = f"failed: {exc}"
    return f"ok (report {report.id}{note}; push: {pushed})"
