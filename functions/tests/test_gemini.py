"""Tests for api/analysis/gemini.py — the report context handed to Gemini,
and what a run leaves behind.

The context is a hand-picked subset of TrainingStatus, so a field the
model needs is easy to leave behind: nothing downstream fails, the
briefing just quietly reasons without it. Ported from fitness-dashboard;
the tests that need rows run against the Firestore emulator.
"""

from __future__ import annotations

from dataclasses import replace
from datetime import UTC, date, datetime, timedelta
from zoneinfo import ZoneInfo

import pytest
import requests

from api.analysis import gemini
from api.analysis.training_load import TrainingStatus
from api.config import settings
from api.integrations.google_health import local_tz
from api.services import drinks, gemini_usage
from api.services.health import Measurement
from api.services.sessions import ExerciseSession
from api.store.rows import CalendarEvent, DailyHealth, Fixture, LeagueRow, LeagueTable, MatchPerformance

STATUS = TrainingStatus(
    status="maintaining",
    headline="Load and fitness are holding steady.",
    fitness=57.2,
    fatigue=92.8,
    form=-35.6,
    form_pct=-62.1,
    ramp_pct=15.0,
    recovery=95,
    readiness=68,
)


@pytest.fixture
def status(monkeypatch):
    def _set(value: TrainingStatus) -> None:
        monkeypatch.setattr(gemini, "get_training_status", lambda _store, days=None: value)

    return _set


def test_both_recovery_scores_reach_the_model():
    payload = gemini._serialize_training_status(STATUS)
    assert payload["recovery_score"] == 95
    assert payload["readiness_score"] == 68


def test_readiness_survives_having_no_score():
    payload = gemini._serialize_training_status(
        TrainingStatus(
            status="maintaining",
            headline="",
            fitness=1.0,
            fatigue=1.0,
            form=0.0,
            form_pct=0.0,
            ramp_pct=0.0,
            recovery=None,
        )
    )
    assert payload["readiness_score"] is None


def test_insufficient_history_drops_the_section_entirely():
    payload = gemini._serialize_training_status(
        TrainingStatus(
            status="insufficient_data",
            headline="",
            fitness=0.0,
            fatigue=0.0,
            form=0.0,
            form_pct=0.0,
            ramp_pct=0.0,
            recovery=None,
        )
    )
    assert payload is None


def test_training_series_writes_form_out_and_stays_daily():
    from api.analysis.training_load import DayPoint

    series = [
        DayPoint(date="2026-08-24", load=30.0, fitness=50.0, fatigue=62.0),
        DayPoint(date="2026-08-25", load=0.0, fitness=49.0, fatigue=55.0),
    ]
    payload = gemini._serialize_training_series(replace(STATUS, series=series))
    assert [p["date"] for p in payload] == ["2026-08-24", "2026-08-25"]
    assert payload[0]["form"] == -12.0  # 50 - 62, not left for the model to subtract
    assert payload[1]["form"] == -6.0


def test_training_series_is_none_without_history():
    assert gemini._serialize_training_series(replace(STATUS, series=[])) is None
    insufficient = TrainingStatus(
        status="insufficient_data",
        headline="",
        fitness=0.0,
        fatigue=0.0,
        form=0.0,
        form_pct=0.0,
        ramp_pct=0.0,
        recovery=None,
    )
    assert gemini._serialize_training_series(insufficient) is None


def test_the_prompt_explains_readiness_against_recovery():
    text = gemini.build_prompt({"today": "2026-08-25", "training_status": {"readiness_score": 68}})
    assert "readiness_score" in text
    assert "68" in text


# --- recent_exercises -------------------------------------------------------

SESSION = ExerciseSession(
    id="2026-08-25#0",
    date=date(2026, 8, 25),
    start_ts=datetime(2026, 8, 25, 17, 4, tzinfo=ZoneInfo("UTC")),
    end_ts=datetime(2026, 8, 25, 17, 45, tzinfo=ZoneInfo("UTC")),
    exercise_type="RUNNING",
    duration_minutes=41.0,
    active_zone_minutes=55.0,
    average_heart_rate=148.0,
    metrics={"distanceMillimeters": 7420000.0},
)


def test_a_session_carries_its_type_effort_and_metrics_bag():
    [payload] = gemini._serialize_exercises([SESSION])
    assert payload["type"] == "RUNNING"
    assert payload["duration_minutes"] == 41.0
    assert payload["active_zone_minutes"] == 55.0
    assert payload["average_heart_rate"] == 148.0
    assert payload["metrics"] == {"distanceMillimeters": 7420000.0}


def test_start_times_are_localized_like_calendar_events():
    """Same trap as _serialize_events: a UTC hour handed over unconverted
    comes back quoted as if it were the local one."""
    [payload] = gemini._serialize_exercises([SESSION])
    # 17:04 UTC is 19:04 in Vienna.
    assert payload["start"].startswith("2026-08-25T19:04")


def test_a_session_with_no_extra_metrics_omits_the_bag():
    [payload] = gemini._serialize_exercises([replace(SESSION, metrics={})])
    assert "metrics" not in payload


def test_the_swim_case_survives_having_neither_azm_nor_heart_rate():
    """Confirmed live 2026-08-23 — both fields absent on a real session."""
    [payload] = gemini._serialize_exercises(
        [replace(SESSION, active_zone_minutes=None, average_heart_rate=None)]
    )
    assert payload["active_zone_minutes"] is None
    assert payload["average_heart_rate"] is None


def test_the_context_asks_for_a_weeks_worth_of_sessions(store, monkeypatch, status):
    status(STATUS)
    seen = {}
    monkeypatch.setattr(gemini, "sessions_since", lambda _store, start: seen.update(start=start) or [])

    gemini.build_context(store)

    # Dated off the same clock build_context reads: the local day, which is
    # already tomorrow in Vienna while UTC still says today.
    today = datetime.now(local_tz()).date()
    assert seen["start"] == today - timedelta(days=gemini.CONTEXT_EXERCISE_DAYS_BACK)


def test_the_latest_measurements_carry_their_date_and_age():
    """A weight the user has not re-taken today is still their weight; the
    model needs the date to judge how much that matters (ADR-018)."""
    payload = gemini._serialize_latest_measurements(
        {
            "weight_kg": Measurement(value=79.2, date=date(2026, 8, 29)),
            "vo2max": Measurement(value=48.0, date=date(2026, 7, 15)),
        },
        date(2026, 8, 31),
    )
    assert payload["weight_kg"] == {"value": 79.2, "date": "2026-08-29", "days_ago": 2}
    assert payload["vo2max"]["days_ago"] == 47


def test_nothing_ever_measured_leaves_the_field_out_entirely():
    """None rather than an empty object: an absent key reads as "nothing to
    say", where {} invites the model to explain the emptiness."""
    assert gemini._serialize_latest_measurements({}, date(2026, 8, 31)) is None


def test_the_prompt_tells_the_model_a_gap_is_not_missing_data():
    text = gemini.build_prompt({"today": "2026-08-25", "latest_measurements": {}})
    assert "latest_measurements" in text
    assert "days_ago" in text


def test_the_prompt_names_the_exercise_window():
    text = gemini.build_prompt({"today": "2026-08-25", "recent_exercises": []})
    assert "recent_exercises" in text
    assert f"last {gemini.CONTEXT_EXERCISE_DAYS_BACK} days" in text


def test_the_prompt_explains_the_training_series():
    text = gemini.build_prompt({"today": "2026-08-25", "training_series": []})
    assert "training_series" in text
    assert "form" in text.lower()


def test_the_report_context_uses_the_default_series_window(store, monkeypatch):
    seen = {}
    monkeypatch.setattr(
        gemini, "get_training_status", lambda _store, days=None: seen.update(days=days) or STATUS
    )
    monkeypatch.setattr(gemini, "sessions_since", lambda _store, _start: [])
    gemini.build_context(store)
    assert seen["days"] == gemini.CONTEXT_TRAINING_SERIES_DAYS

    gemini.build_context(store, lookback_days=730)
    assert seen["days"] == 730


# --- the context, from stored rows ---------------------------------------------


def test_the_context_reads_its_windows_from_the_store(store, status):
    status(STATUS)
    today = datetime.now(local_tz()).date()
    store.put_health_days(
        [
            DailyHealth(date=today - timedelta(days=30), resting_hr=60),
            DailyHealth(date=today - timedelta(days=2), resting_hr=55),
            DailyHealth(date=today - timedelta(days=1), resting_hr=54),
        ]
    )
    store.put_match(
        MatchPerformance(
            id=1,
            oefb_game_id="g1",
            match_date=today - timedelta(days=5),
            opponent="Kirchberg",
            home_away="away",
            result="1:2",
        )
    )
    soon = datetime.now(UTC) + timedelta(days=2)
    store.put_calendar_events(
        [CalendarEvent(id="e1", calendar_id="primary", title="Training", start_ts=soon, end_ts=soon)]
    )

    context = gemini.build_context(store)

    # Newest first, 14 days back, so the reading from a month ago is left out.
    assert [row["resting_hr"] for row in context["recent_daily_health"]] == [54, 55]
    # An away 1:2 is a win for us, not a loss.
    [match] = context["recent_matches"]
    assert (match["our_score"], match["opponent_score"], match["outcome"]) == (2, 1, "W")
    assert [event["title"] for event in context["upcoming_events"]] == ["Training"]
    assert "previous_report_summary" not in context
    assert match["opponent_standing"] is None
    assert context["league"] is None


def test_the_context_carries_the_league_table_and_the_next_opponents(store, status):
    status(STATUS)
    today = datetime.now(local_tz()).date()
    store.put_league_table(
        LeagueTable(
            day=today,
            league="2. Nordwest",
            rows=[
                LeagueRow(rank=3, team="Sarleinsbach", played=7, points=15),
                LeagueRow(rank=8, team="Eidenberg/Geng", is_us=True, played=7, points=11, goal_difference=2),
                LeagueRow(rank=10, team="Kirchberg/D.", played=7, points=9),
            ],
        )
    )
    store.put_match(
        MatchPerformance(
            id=1,
            oefb_game_id="g1",
            match_date=today - timedelta(days=5),
            opponent="Kirchberg / D.",
            home_away="home",
        )
    )
    # 18:00 UTC is 20:00 in Vienna.
    kickoff = datetime.combine(today + timedelta(days=3), datetime.min.time(), tzinfo=UTC).replace(hour=18)
    store.put_fixtures(
        [Fixture(oefb_game_id="f1", kickoff=kickoff, opponent="Sarleinsbach", home_away="away")]
    )

    context = gemini.build_context(store)

    league = context["league"]
    assert league["league"] == "2. Nordwest"
    assert league["our_standing"] == {
        "rank": 8,
        "played": 7,
        "points": 11,
        "points_per_game": 1.57,
        "goal_difference": 2,
    }
    assert [row["team"] for row in league["table"]] == ["Sarleinsbach", "Eidenberg/Geng", "Kirchberg/D."]
    assert league["table"][1]["is_us"] is True
    assert "is_us" not in league["table"][0]
    [fixture] = league["next_fixtures"]
    assert fixture["kickoff"].startswith(f"{(today + timedelta(days=3)).isoformat()}T20:00")
    assert fixture["opponent_standing"]["points_gap"] == 4
    assert fixture["opponent_standing"]["strength"] == "stronger"
    # The table is only from today, after the match: the current rank stands in.
    [match] = context["recent_matches"]
    assert match["opponent_standing"]["opponent_rank"] == 10
    assert match["opponent_standing"]["strength"] == "level"



# --- a whole run -----------------------------------------------------------------


@pytest.fixture
def answered(monkeypatch, status):
    """Gemini answers, without the network: the tests below are about what
    a run stores and what it claims."""
    status(STATUS)
    monkeypatch.setattr(settings, "gemini_api_key", "test-key")
    # A named fallback, so nothing asks Google which models exist.
    monkeypatch.setattr(settings, "gemini_fallback_model", "fallback-model")
    monkeypatch.setattr(
        gemini,
        "call_gemini",
        lambda _store, _prompt, **_how: (
            {"summary_md": "## Rested", "insights": {"readiness": "high"}},
            1234,
            "gemini-3.8-flash",
        ),
    )


def test_a_run_stores_the_report_with_the_model_that_answered(store, answered):
    report = gemini.run_analysis(store, "manual")

    stored = store.latest_report()
    assert stored.id == report.id
    assert (stored.trigger, stored.model, stored.prompt_version) == ("manual", "gemini-3.8-flash", "v6")
    assert stored.summary_md == "## Rested"
    assert stored.insights == {"readiness": "high"}
    assert stored.tokens_used == 1234


def test_the_first_report_of_the_day_claims_the_counter_and_the_second_does_not(store, answered):
    """ADR-019: only the first report of a local day resets the stepper, so
    an evening report cannot swallow a night that is still going on."""
    store.add_drinks(2)
    first = gemini.run_analysis(store, "manual")
    assert drinks.pending(store).count == 0

    store.add_drinks(1)
    second = gemini.run_analysis(store, "manual")
    assert drinks.pending(store).count == 1
    assert second.id > first.id


def test_a_spent_budget_refuses_before_asking_gemini(store, answered, monkeypatch):
    monkeypatch.setattr(settings, "gemini_fallback_model", "")
    monkeypatch.setattr(settings, "gemini_requests_per_day", 1)
    store.count_gemini_request(gemini_usage.quota_day(), settings.gemini_model)

    with pytest.raises(gemini_usage.GeminiQuotaExceeded):
        gemini.run_analysis(store, "manual")
    assert store.latest_report() is None


# --- daily fallback --------------------------------------------------------


def test_daily_fallback_runs_when_the_day_has_no_report(store, answered):
    assert gemini.run_daily_fallback(store).startswith("ok")
    assert store.latest_report().trigger == "daily_fallback"


def test_daily_fallback_skips_when_the_day_already_has_a_report(store, answered):
    gemini.run_analysis(store, "manual")

    assert gemini.run_daily_fallback(store).startswith("skipped")
    assert store.latest_report().trigger == "manual"


def test_daily_fallback_pushes_the_report(store, answered, monkeypatch):
    from api.services import push

    push.register(store, "phone", "android")
    sent = []
    monkeypatch.setattr(push, "_send", lambda tokens, report: sent.append((tokens, report.id)) or [None])

    result = gemini.run_daily_fallback(store)

    report = store.latest_report()
    assert sent == [(["phone"], report.id)]
    assert result == f"ok (report {report.id}; push: sent 1, pruned 0, failed 0)"


def test_a_failed_push_leaves_the_daily_report_standing(store, answered, monkeypatch):
    from api.services import push

    push.register(store, "phone", "android")

    def fcm_down(tokens, report):
        raise RuntimeError("FCM unreachable")

    monkeypatch.setattr(push, "_send", fcm_down)

    assert gemini.run_daily_fallback(store).endswith("push: failed: FCM unreachable)")
    assert store.latest_report().trigger == "daily_fallback"


# --- the 19:30 last try (ADR-034) ---------------------------------------------


@pytest.fixture
def overloaded(monkeypatch, answered):
    """The primary answers 503 however often it is asked; the fallback
    answers. Records which models each call was allowed."""
    calls: list[tuple[list[str] | None, int]] = []

    def call(_store, _prompt, max_retries=2, only=None):
        calls.append((only, max_retries))
        if only is None:
            raise requests.HTTPError("503 Server Error: Service Unavailable")
        return {"summary_md": "## Late", "insights": {"readiness": "moderate"}}, 99, only[0]

    monkeypatch.setattr(gemini, "call_gemini", call)
    return calls


def test_the_1830_run_does_not_fall_back_on_its_own(store, overloaded):
    with pytest.raises(requests.HTTPError):
        gemini.run_daily_fallback(store)

    assert overloaded == [(None, 2)]
    assert store.latest_report() is None


def test_the_last_try_falls_back_once_to_the_second_model(store, overloaded):
    result = gemini.run_daily_fallback(store, last_try=True)

    # The normal call first, then one on the fallback alone, without retries.
    assert overloaded == [(None, 2), (["fallback-model"], 0)]
    report = store.latest_report()
    assert report.trigger == "daily_fallback"
    assert report.model == "fallback-model"
    assert result.startswith(f"ok (report {report.id} on the fallback model fallback-model; push: ")


def test_the_last_try_does_nothing_when_the_day_has_a_report(store, overloaded, monkeypatch):
    monkeypatch.setattr(gemini, "report_exists_today", lambda _store: True)

    assert gemini.run_daily_fallback(store, last_try=True).startswith("skipped")
    assert overloaded == []


def test_the_last_try_without_a_fallback_model_raises(store, overloaded, monkeypatch):
    monkeypatch.setattr(settings, "gemini_fallback_model", "")

    with pytest.raises(requests.HTTPError):
        gemini.run_daily_fallback(store, last_try=True)
    assert overloaded == [(None, 2)]


def test_a_spent_budget_is_not_retried_on_the_fallback(store, answered, monkeypatch):
    """Both models share the day's allowance (ADR-013): the fallback cannot
    help once it is gone."""
    monkeypatch.setattr(
        gemini.gemini_usage,
        "require_report_budget",
        lambda _store: (_ for _ in ()).throw(gemini_usage.GeminiQuotaExceeded("spent")),
    )

    with pytest.raises(gemini_usage.GeminiQuotaExceeded):
        gemini.run_daily_fallback(store, last_try=True)
