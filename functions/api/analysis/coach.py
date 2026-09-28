"""api/analysis/coach.py — context + prompt for the dashboard's Coach tab.

The browser used to build the entire system prompt itself and POST it to
/coach/chat, which made the endpoint an open Gemini proxy: anyone who
could reach the API could send arbitrary prompts on the server's API key.
It also meant the coach's view of the data was whatever the dashboard had
already fetched, and the prompt duplicated (and drifted from)
analysis/gemini.py's build_context.

Now the client sends only which sections to include, and the assembly
happens here on top of build_context().

Since ADR-021 it can also *pin* individual workouts. Those are still only
ids — the session and its heart rate trace are read here, by
services/session_context.py — so the rule above is unchanged: the client
chooses which data, never what the data says. The pinned sessions are the
one part of this prompt that is not a summary, and the section heading
below is written accordingly.
"""

from __future__ import annotations

import json
import logging
from dataclasses import dataclass

from api.analysis.gemini import CONTEXT_EXERCISE_DAYS_BACK, build_context, chat_completion
from api.config import settings
from api.services.session_context import attached_sessions
from api.services.training import get_training_status
from api.store.firestore import FirestoreStore

logger = logging.getLogger("api.analysis.coach")

SYSTEM_PREAMBLE = (
    "You are a supportive, knowledgeable fitness and football coach helping an "
    "amateur player prepare for matches, spot trends in their health data, and "
    "decide when to add extra training or rest. Be concise and specific, "
    "referencing the data given below when relevant. If data needed to answer "
    "isn't included, say so and suggest the user include it via the toggles. "
    "Reply in plain markdown (headings, bullets, **bold**/*italic*). The chat "
    "renders real LaTeX, so use '$...$' (inline) or '$$...$$' (its own line) "
    "only for an actual formula, e.g. '$FTP = 0.95 \\times MMP$' — never for "
    "a plain trend, which reads better as '13.9 -> 38.3' than as "
    "'$13.9 \\rightarrow 38.3$'. For a numbered "
    "list, put each item on its own line starting with '1.', '2.', etc. — "
    "never run them together in one paragraph, which reads as '...zero. 2. "
    "The next point...' instead of a list. For anything tabular — a week of "
    "Fitness/Fatigue/Form, several matches side by side — use a markdown "
    "table (a header row, then a |---|---| separator row, then the data "
    "rows) rather than describing it in prose. You can also draw a chart "
    "in a fenced ```chart code block holding one JSON object: "
    '{"type": "line" | "bar" | "pie", "title": "...", "unit": "...", '
    '"x": [labels], "series": [{"name": "...", "values": [numbers or null]}]}. '
    "Use line for a trend over time, bar to compare a few values (a week of "
    "Active Zone Minutes, several matches) and pie for the parts of a whole, "
    "with exactly one series. Every series has one value per label in `x`, "
    "null where a day has no data; the series of one chart share one axis, "
    "so only put numbers in the same unit together. Keep it to at most 60 "
    "labels and 4 series. Use either the data given to you or numbers you "
    "work out yourself (e.g. a weekly average from the daily series). "
    "Double-check any number you compute before putting it in a chart; a "
    "wrong number in a chart is a wrong number, not a style issue. For a "
    "decision (whether to train or rest), write a short list, not a chart."
)

NO_DATA = "No data selected — the user hasn't included any of their data in this chat."

# The heading over the pinned workouts (ADR-021). It has to do three things
# the summary sections do not:
#
# 1. Say that these are the sessions the user *chose*, so a question with no
#    demonstrative in it ("was that too hard?") lands on them rather than on
#    whatever the fortnight summary happens to end with.
# 2. Explain the trace, because it is the only raw series in the whole
#    prompt: what a pair is, that the offsets are seconds, and that the
#    stated `zones` are the answer to "how long in each" rather than
#    something to recount off the samples.
# 3. Tell the model to check `heart_rate.status` before saying a session has
#    no heart rate. "Not synced yet" and "the watch recorded none" are
#    different sentences and only one of them is about the workout.
ATTACHED_HEADING = (
    "Workouts the user has attached to this chat, in full (this is what they "
    'want analysed — treat an unqualified question about "this session" or '
    '"the workout" as being about these, and prefer them over the summary '
    "list above where the two overlap).\n"
    "`metrics` holds whatever else the watch recorded, under field names "
    "that carry their own units. `heart_rate.samples` is the beat-by-beat "
    "trace as [seconds since the session started, bpm] pairs — use it for "
    "pacing, drift, how long the warm-up took, how quickly they came back "
    "down, and whether the effort was steady or spiky. `heart_rate.zones` "
    "already gives the seconds spent in each zone; quote those rather than "
    "recounting them from the samples, and note that the bpm boundaries are "
    "derived from a resting and a maximum heart rate, not published by the "
    "watch. Before saying a session has no heart rate data, read "
    '`heart_rate.status`: "not_synced" means it has not been fetched yet, '
    "which is a statement about the sync and not about the session. "
    "`match`, when present, is the official ÖFB match report for the game "
    "this session was — opponent, result from the home side's view, minutes "
    "played and goals — so a question about how the match went has both "
    "sides of it.\n"
)

# What the prompt says when an attached id no longer names a session. Worth
# a sentence rather than a silent shorter list: the user can see the chip in
# the composer, so a coach that simply never mentions that workout looks
# like it ignored the question.
MISSING_ATTACHED = (
    "The user also attached {count} workout(s) that could not be loaded "
    "({ids}) — the underlying data is no longer there. Say so if they ask "
    "about them; do not answer from the summary rows instead."
)


@dataclass(frozen=True)
class CoachInclude:
    """Mirrors the dashboard's "Include in this chat" toggles."""

    health: bool = True
    exercises: bool = True
    matches: bool = True
    events: bool = True
    report: bool = True
    alcohol: bool = True


def _training_section(store: FirestoreStore) -> str | None:
    status = get_training_status(store)
    if status.status == "insufficient_data":
        return None
    return (
        "Training status (trailing averages of daily Active Zone Minutes — "
        "Fitbit/Google's heart-rate-zone-weighted cardio metric, so ~21/day is "
        "roughly the WHO moderate-activity guideline):\n"
        f"Status: {status.status} — {status.headline}\n"
        f"Fitness (42-day avg): {status.fitness}, moving {status.ramp_pct}% per week\n"
        f"Fatigue (7-day avg): {status.fatigue}\n"
        f"Form (Fitness - Fatigue): {status.form} — read on the standard TSB bands: "
        "below -30 overreaching, -10 to -30 a productive block, -10 to +10 "
        "maintaining, +10 to +25 rested and primed\n"
        f"Recovery: {status.recovery if status.recovery is not None else 'unknown'}/100 "
        "from HRV, resting HR and sleep vs a 28-day baseline, averaged over the "
        "last three days\n"
        f"Readiness: {status.readiness if status.readiness is not None else 'unknown'}/100 "
        "— the same index scored on last night alone, so it answers 'how am I "
        "today' where Recovery answers 'how has this week gone'"
    )


def _attached_section(store: FirestoreStore, session_ids: list[str] | None) -> str | None:
    """The pinned workouts, in full (ADR-021), or None when none are pinned.

    Deliberately *not* gated on `include.exercises`. That toggle is about the
    rolling summary of "what have I been doing" — attaching a workout is the
    user pointing at one thing and asking about it, and a pointed question
    answered with "you haven't included your workouts" would be absurd. The
    same reasoning ADR-019 used for keeping the beer log off the health
    toggle.
    """
    if not session_ids:
        return None

    attached = attached_sessions(store, session_ids)
    parts: list[str] = []
    if attached.sessions:
        parts.append(ATTACHED_HEADING + json.dumps(attached.sessions, indent=2))
    if attached.missing:
        parts.append(MISSING_ATTACHED.format(count=len(attached.missing), ids=", ".join(attached.missing)))
    return "\n\n".join(parts) if parts else None


def build_system_prompt(
    store: FirestoreStore,
    include: CoachInclude,
    lookback_days: int | None = None,
    session_ids: list[str] | None = None,
) -> str:
    """The full system instruction: preamble + whichever data the user opted
    in to. `lookback_days` is the Coach tab's History selector — how far back
    the health / workout / match data reaches; `session_ids` are the workouts
    pinned to this chat, which arrive in full rather than as summary rows."""
    context = build_context(store, lookback_days=lookback_days)
    exercise_days = lookback_days or CONTEXT_EXERCISE_DAYS_BACK
    parts: list[str] = []

    if include.health:
        if context["recent_daily_health"]:
            parts.append(
                "Daily health (most recent first):\n" + json.dumps(context["recent_daily_health"], indent=2)
            )
        if context["latest_measurements"]:
            parts.append(
                "Latest weight / VO2 max — these are not measured every day, so "
                "the daily rows above are null in between and that is not missing "
                "data. Each is the current value, with the day it was measured "
                "and how many days ago that was; treat a recent one as today's "
                "number:\n" + json.dumps(context["latest_measurements"], indent=2)
            )
        training = _training_section(store)
        if training:
            parts.append(training)
        if context["training_series"]:
            parts.append(
                "Daily Fitness / Fatigue / Form history (oldest first; Form = "
                "Fitness − Fatigue, read on the bands above). Use the dates to "
                "line form up with match days and upcoming events — form on a "
                "match day is what matters most:\n" + json.dumps(context["training_series"], indent=2)
            )

    if include.exercises and context["recent_exercises"]:
        parts.append(
            f"Individual tracked workouts of the last {exercise_days} days "
            "(newest first; `metrics` holds whatever else the watch recorded, under "
            "field names that carry their own units):\n" + json.dumps(context["recent_exercises"], indent=2)
        )

    # Right after the workout summary it supersedes, and before the match /
    # calendar sections: the model reads in order, and the detail belongs
    # next to the list it is the zoomed-in version of.
    attached = _attached_section(store, session_ids)
    if attached:
        parts.append(attached)

    if include.matches and context["recent_matches"]:
        parts.append("Match performance:\n" + json.dumps(context["recent_matches"], indent=2))

    if include.events and context["upcoming_events"]:
        parts.append(
            "Upcoming calendar events (times already in the user's local timezone):\n"
            + json.dumps(context["upcoming_events"], indent=2)
        )

    if include.alcohol and context["alcohol"]:
        parts.append(
            "Alcohol, logged by hand on the dashboard (nothing measures this — "
            "it is what the user tapped in). `since_last_report` is the counter "
            "as it stands now: the drinks no daily report has covered yet, "
            "which is usually last night's. `daily_counts` is the recent "
            "history by day, days with none omitted. Answer about it plainly "
            "and use it to explain sleep, resting HR and HRV where it fits:\n"
            + json.dumps(context["alcohol"], indent=2)
        )

    if include.report and context["previous_report_summary"]:
        parts.append("Latest AI readiness report:\n" + context["previous_report_summary"])

    body = "\n\n".join(parts) if parts else NO_DATA
    return f"{SYSTEM_PREAMBLE}\n\nToday is {context['today']}.\n\n{body}"


def trim_history(messages: list[dict]) -> list[dict]:
    """The window of a stored conversation the model actually sees (ADR-017).

    Every turn is kept and displayed; only this much is replayed. Two bounds,
    because they fail differently — a message count keeps a long-running chat
    from growing the request without limit, and a character budget is the one
    that bites when a few turns quote large numbers back at each other. The
    day's Gemini budget counts requests, not tokens (ADR-013), so this
    changes what a turn costs, never how many are left.

    Always starts on a `user` turn. Cutting mid-exchange can leave a leading
    assistant turn, which reads to Gemini as a conversation that opens with
    the answer to a question it was never asked.
    """
    window = messages[-settings.coach_history_messages :]
    while window and window[0]["role"] != "user":
        window = window[1:]
    # Drop whole exchanges, so the window still opens on a user turn.
    while len(window) > 1 and sum(len(m["content"]) for m in window) > settings.coach_history_max_chars:
        window = window[2:]
    # A single message over the budget is still the question being asked:
    # sending it truncated-to-nothing would be worse than sending it.
    return window or messages[-1:]


def answer(
    store: FirestoreStore,
    include: CoachInclude,
    messages: list[dict],
    lookback_days: int | None = None,
    session_ids: list[str] | None = None,
) -> str:
    prompt = build_system_prompt(store, include, lookback_days, session_ids)
    # The attached count is logged because it is the one input that can move
    # the prompt by tens of thousands of characters between two turns of the
    # same chat — which is what to look at first when a request that used to
    # work stops.
    logger.info(
        "Coach chat: %d message(s), lookback=%s days, %d workout(s) attached, context %d chars, include=%s",
        len(messages),
        lookback_days or "default",
        len(session_ids or []),
        len(prompt),
        include,
    )
    return chat_completion(store, prompt, messages)
