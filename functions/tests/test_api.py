"""End-to-end tests for the routers, against a real Postgres.

Marked `db` because the models use JSONB and the raw-payload round-trip is
part of what is being checked — SQLite cannot stand in for that. Set
TEST_DATABASE_URL to run them; see conftest.py.

The app is constructed without entering its lifespan, so the scheduler
never starts and no test reaches out to Google.
"""

from __future__ import annotations

from datetime import UTC, date, datetime, time, timedelta, timezone

import pytest
from fastapi.testclient import TestClient

from api.analysis.training_load import (
    DEFAULT_MATCH_FALLBACK_LOAD_PER_MINUTE,
    DEFAULT_TRAINING_FALLBACK_LOAD_PER_MINUTE,
)
from api.config import settings
from api.main import app
from api.services.exercises import sessions_since
from api.store.firestore import get_store
from tests.legacy_db import (
    AiReport,
    CalendarEvent,
    DailyHealth,
    ExerciseHeartRate,
    MatchPerformance,
)

NOW = datetime.now(UTC)


@pytest.fixture
def client(db):
    app.dependency_overrides[get_store] = lambda: db
    yield TestClient(app)
    app.dependency_overrides.clear()


@pytest.fixture
def seeded(db):
    db.add_all(
        [
            MatchPerformance(
                oefb_game_id="1", match_date=date(2026, 8, 8), opponent="Treffling",
                home_away="home", result="4:3", started=True, minutes_played=90, goals=1,
            ),
            MatchPerformance(
                oefb_game_id="2", match_date=date(2026, 8, 1), opponent="Admira",
                home_away="away", result="0:2", started=False, minutes_played=30, goals=0,
            ),
            CalendarEvent(
                id="past", calendar_id="primary", title="Yesterday",
                start_ts=NOW - timedelta(days=1), end_ts=NOW - timedelta(days=1), raw={},
            ),
            CalendarEvent(
                id="soon", calendar_id="primary", title="Training",
                start_ts=NOW + timedelta(days=1), end_ts=NOW + timedelta(days=1), raw={"x": 1},
            ),
            DailyHealth(
                date=date(2026, 8, 19), steps=2824, resting_hr=54, hrv_ms=87.0,
                sleep_minutes=418, active_zone_minutes=12, weight_kg=80.0, raw={"steps": {}},
            ),
            DailyHealth(date=date(2026, 8, 18), steps=9000, resting_hr=56, raw={}),
        ]
    )
    db.flush()
    return db


# --- meta -------------------------------------------------------------------


def test_healthz(client):
    assert client.get("/healthz").json() == {"status": "ok"}


# --- matches ----------------------------------------------------------------


def test_matches_are_returned_newest_first(client, seeded):
    body = client.get("/matches").json()
    assert [m["opponent"] for m in body] == ["Treffling", "Admira"]
    assert body[0]["goals"] == 1
    assert body[0]["home_away"] == "home"


# --- calendar ---------------------------------------------------------------


def test_only_upcoming_events_are_listed(client, seeded):
    body = client.get("/calendar/events").json()
    assert [e["title"] for e in body] == ["Training"]


def test_calendar_limit_is_honoured(client, seeded):
    assert client.get("/calendar/events?limit=0").json() == []


def test_calendar_response_does_not_leak_the_raw_payload(client, seeded):
    """`raw` is kept for re-derivation, not for the browser."""
    assert "raw" not in client.get("/calendar/events").json()[0]


# --- health data ------------------------------------------------------------


def test_daily_health_is_newest_first_and_limited(client, seeded):
    body = client.get("/health-data/daily?limit=1").json()
    assert [d["date"] for d in body] == ["2026-08-19"]


def test_daily_health_exposes_active_zone_minutes(client, seeded):
    """The training model's load unit — the dashboard needs it and the
    response model omitted it before."""
    assert client.get("/health-data/daily").json()[0]["active_zone_minutes"] == 12


def test_missing_metrics_come_back_as_null_not_zero(client, seeded):
    older = client.get("/health-data/daily").json()[1]
    assert older["hrv_ms"] is None
    assert older["active_zone_minutes"] is None


def test_latest_measurements_reach_back_past_the_last_weigh_in(client, db):
    """The whole point of /latest: weight is not recorded daily, so the last
    reading can sit outside any window the dashboard asked for and is still
    the current weight (ADR-018)."""
    db.add_all(
        [
            DailyHealth(date=date(2026, 8, 19), steps=2824, raw={}),
            DailyHealth(date=date(2026, 8, 15), weight_kg=79.2, raw={}),
            DailyHealth(date=date(2026, 8, 10), weight_kg=80.4, vo2max=48.0, raw={}),
        ]
    )
    db.flush()

    body = client.get("/health-data/latest").json()
    assert body["weight_kg"] == {"value": 79.2, "date": "2026-08-15"}
    # Each metric is found on its own day — VO2 max last landed five days
    # before that weight did.
    assert body["vo2max"] == {"value": 48.0, "date": "2026-08-10"}


def test_a_metric_never_recorded_comes_back_null(client, db):
    """Null, not a made-up zero: nothing has ever weighed 0 kg."""
    db.add(DailyHealth(date=date(2026, 8, 19), steps=2824, raw={}))
    db.flush()

    assert client.get("/health-data/latest").json() == {"weight_kg": None, "vo2max": None}


# --- exercise sessions ------------------------------------------------------


# The session shape confirmed live 2026-08-19 (api/integrations/google_health.py):
# int64-ish fields as JSON strings, an RFC-3339 interval with a local offset.
def exercise_point(day: str, start: str, end: str, kind: str, azm: str) -> dict:
    return {
        "exercise": {
            "exerciseType": kind,
            "interval": {"startTime": f"{day}T{start}+02:00", "endTime": f"{day}T{end}+02:00"},
            "metricsSummary": {
                "activeZoneMinutes": azm,
                "averageHeartRateBeatsPerMinute": "150",
                "distanceMeters": "8412",
            },
        }
    }


@pytest.fixture
def tracked_sessions(db):
    """Two days that carried sessions, with a rest day in between — the
    round-trip through JSONB is the point, so this needs a real Postgres."""
    db.add_all(
        [
            DailyHealth(
                date=date(2026, 8, 20),
                active_zone_minutes=34,
                raw={"exercise": [exercise_point("2026-08-20", "17:00:00", "18:05:00", "RUNNING", "34")]},
            ),
            DailyHealth(date=date(2026, 8, 19), steps=2000, raw={"steps": {}}),
            DailyHealth(
                date=date(2026, 8, 18),
                active_zone_minutes=70,
                raw={
                    "exercise": [
                        exercise_point("2026-08-18", "19:00:00", "20:30:00", "SOCCER", "58"),
                        exercise_point("2026-08-18", "07:00:00", "07:30:00", "WALKING", "12"),
                    ]
                },
            ),
        ]
    )
    db.flush()
    return db


def test_exercises_are_listed_newest_first_across_days(client, tracked_sessions):
    body = client.get("/health-data/exercises").json()

    assert [e["exercise_type"] for e in body] == ["RUNNING", "SOCCER", "WALKING"]
    assert [e["date"] for e in body] == ["2026-08-20", "2026-08-18", "2026-08-18"]


def test_an_exercise_carries_the_detail_the_daily_row_flattened_away(client, tracked_sessions):
    """`daily_health` keeps only the day's summed Active Zone Minutes; the
    per-session numbers were in `raw` all along."""
    session = client.get("/health-data/exercises").json()[0]

    assert session["duration_minutes"] == 65.0
    assert session["active_zone_minutes"] == 34.0
    assert session["average_heart_rate"] == 150.0
    assert session["metrics"] == {"distanceMeters": 8412.0}
    assert session["start_ts"].startswith("2026-08-20T17:00:00")


def test_rest_days_do_not_eat_the_exercise_limit(client, tracked_sessions):
    """The query filters on the JSONB key rather than scanning days back, so
    the untracked 19th does not cost a slot."""
    assert len(client.get("/health-data/exercises?limit=2").json()) == 2
    assert client.get("/health-data/exercises?limit=0").json() == []


def test_exercises_are_empty_when_nothing_was_ever_tracked(client, seeded):
    assert client.get("/health-data/exercises").json() == []


# --- one session's heart rate trace (ADR-020) -------------------------------


@pytest.fixture
def traced_session(db, tracked_sessions, monkeypatch):
    """The 20th's run, with a trace and Google's own time in zone.

    Resting HR is on a *different, earlier* day than the session on purpose:
    it is carried forward the way weight is (ADR-018), because a night off
    the wrist does not produce one.
    """
    monkeypatch.setattr(settings, "health_max_hr_bpm", 191)
    db.add(DailyHealth(date=date(2026, 8, 17), resting_hr=56, raw={}))
    db.add(
        ExerciseHeartRate(
            session_start=datetime(2026, 8, 20, 17, 0, tzinfo=timezone(timedelta(hours=2))),
            date=date(2026, 8, 20),
            session_end=datetime(2026, 8, 20, 18, 5, tzinfo=timezone(timedelta(hours=2))),
            samples=[[0, 95], [10, 120], [20, 152], [30, 148]],
            zone_seconds={"FAT_BURN": 600.0, "CARDIO": 2400.0},
            fetched_at=NOW,
        )
    )
    db.flush()
    return db


def test_a_session_serves_its_trace_and_the_zones_it_falls_in(client, traced_session):
    body = client.get("/health-data/exercises/2026-08-20%230/heart-rate").json()

    assert body["samples"] == [[0, 95], [10, 120], [20, 152], [30, 148]]
    assert body["sample_count"] == 4
    assert (body["min_bpm"], body["max_bpm"], body["average_bpm"]) == (95, 152, 128.8)
    # Karvonen off a carried-forward resting 56 and a configured max of 191.
    assert body["resting_hr"] == 56
    assert body["max_hr"] == 191
    assert [(z["zone"], z["lower_bpm"]) for z in body["zones"]] == [
        ("light", None),
        ("fat_burn", 110),
        ("cardio", 137),
        ("peak", 171),
    ]


def test_googles_own_time_in_zone_is_what_is_served(client, traced_session):
    """The numbers on the phone and the numbers here have to agree."""
    body = client.get("/health-data/exercises/2026-08-20%230/heart-rate").json()

    assert body["zone_source"] == "google"
    assert {z["zone"]: z["seconds"] for z in body["zones"]}["cardio"] == 2400.0


def test_without_a_configured_max_hr_there_are_no_zones_but_still_a_trace(
    client, traced_session, monkeypatch
):
    """An uncoloured chart of real readings beats a coloured one drawn
    against boundaries nobody measured."""
    monkeypatch.setattr(settings, "health_max_hr_bpm", None)
    monkeypatch.setattr(settings, "health_birth_year", None)

    body = client.get("/health-data/exercises/2026-08-20%230/heart-rate").json()

    assert body["zones"] == []
    assert body["zone_source"] is None
    assert body["max_hr"] is None
    assert len(body["samples"]) == 4


def test_a_session_with_no_trace_yet_is_not_an_error(client, tracked_sessions):
    """200 with nothing in it, and `fetched_at` null — the sync fetches the
    newest sessions first and a bounded number per run, so "not reached yet"
    is a normal state the sheet words differently from "nothing recorded"."""
    body = client.get("/health-data/exercises/2026-08-20%230/heart-rate").json()

    assert body["samples"] == []
    assert body["sample_count"] == 0
    assert body["fetched_at"] is None
    assert body["min_bpm"] is None


def test_an_unknown_session_is_a_404(client, tracked_sessions):
    # A day that holds no sessions, an index past the end, an id that is not
    # a tracked session at all (a match's estimated row), and junk.
    for session_id in ("2026-08-19%230", "2026-08-20%239", "match%231", "nonsense"):
        assert client.get(f"/health-data/exercises/{session_id}/heart-rate").status_code == 404


def test_a_date_window_takes_whole_days_not_a_session_count(tracked_sessions):
    """What the AI context asks for: everything since a date, however many
    sessions that turns out to be. The 18th carried two — a window that
    reaches it must bring back both."""
    since_the_18th = sessions_since(tracked_sessions, date(2026, 8, 18))
    assert [s.exercise_type for s in since_the_18th] == ["RUNNING", "SOCCER", "WALKING"]


def test_the_window_excludes_days_before_its_start(tracked_sessions):
    since_the_19th = sessions_since(tracked_sessions, date(2026, 8, 19))
    assert [s.exercise_type for s in since_the_19th] == ["RUNNING"]


def test_a_window_over_untracked_days_comes_back_empty(tracked_sessions):
    assert sessions_since(tracked_sessions, date(2026, 8, 21)) == []


# --- scheduled sessions the watch never tracked -----------------------------


@pytest.fixture
def schedule_history(db):
    """Three weeks of tracked days, then two days the watch missed: one
    holding a match (kick-off 15:00 UTC, off its "Spiel:" calendar event),
    one holding a calendar "Training" block (17:00 UTC).

    Dated off the real today, because the model always measures through
    today — a fixed date would drift out of the window as the calendar
    moves and quietly stop testing anything.
    """
    today = date.today()
    db.add_all(
        [
            DailyHealth(
                date=today - timedelta(days=days_ago),
                resting_hr=54,
                hrv_ms=70.0,
                sleep_minutes=420,
                active_zone_minutes=30,
                raw={},
            )
            # ...and deliberately no row at all for the two days below, which
            # is what an untracked day looks like.
            for days_ago in range(3, 21)
        ]
        + [
            MatchPerformance(
                oefb_game_id="g-untracked", match_date=today - timedelta(days=2),
                opponent="Treffling", home_away="home", result="4:3", started=True,
                minutes_played=90, goals=1,
            ),
            # The kick-off comes from here, not from the ÖFB row — see
            # services/training.py._match_kickoffs.
            CalendarEvent(
                id="fixture-treffling", calendar_id="primary",
                title="Spiel: Union Eidenberg/Geng - Treffling",
                start_ts=datetime.combine(today - timedelta(days=2), time(15, 0), tzinfo=UTC),
                end_ts=datetime.combine(today - timedelta(days=2), time(18, 0), tzinfo=UTC),
                raw={},
            ),
            CalendarEvent(
                id="training-yesterday", calendar_id="primary", title="Training",
                start_ts=datetime.combine(today - timedelta(days=1), time(17, 0), tzinfo=UTC),
                end_ts=datetime.combine(today - timedelta(days=1), time(20, 0), tzinfo=UTC),
                raw={},
            ),
        ]
    )
    db.flush()
    return db


def skip(client, source: str, ref_id: str, skipped: bool = True):
    return client.post(
        "/training/skips", json={"source": source, "ref_id": ref_id, "skipped": skipped}
    )


def listed(client) -> dict[str, dict]:
    return {session["id"]: session for session in client.get("/health-data/exercises").json()}


def tracked_day(db, day, *points, azm):
    """A daily_health row carrying real sessions, so coverage has something
    to compare scheduled times against."""
    db.add(DailyHealth(date=day, active_zone_minutes=azm, raw={"exercise": list(points)}))
    db.flush()


def loads_by_day(client) -> dict[str, float]:
    return {point["date"]: point["load"] for point in client.get("/training/status").json()["series"]}


def test_an_untracked_match_is_listed_with_the_load_it_added(client, schedule_history):
    """The load was in the chart all along; without this the list left it
    unexplained."""
    session = listed(client)["match#g-untracked"]

    assert session["source"] == "match"
    assert session["title"] == "vs Treffling"
    assert session["duration_minutes"] == 90.0
    # Estimated, not measured — the two never share a field.
    assert session["active_zone_minutes"] is None
    assert session["estimated_load"] == pytest.approx(
        90 * DEFAULT_MATCH_FALLBACK_LOAD_PER_MINUTE, abs=0.01
    )
    assert session["skipped"] is False


def test_an_untracked_training_is_listed_at_its_pitch_minutes(client, schedule_history):
    """Not the calendar block's three hours: the model counts 90 minutes on
    the pitch, and the card has to agree with the model."""
    session = listed(client)["training#training-yesterday"]

    assert session["source"] == "training"
    assert session["duration_minutes"] == 90.0
    assert session["estimated_load"] == pytest.approx(
        90 * DEFAULT_TRAINING_FALLBACK_LOAD_PER_MINUTE, abs=0.01
    )


def test_the_estimate_on_the_card_is_the_load_in_the_chart(client, schedule_history):
    """The one that matters. Two independently-derived numbers for the same
    session is the failure this feature is one refactor away from.

    Both fixture days hold nothing but the estimate, so the day's whole
    load is it — the mixed case is covered below, where a walk and an
    estimate share a day."""
    loads = loads_by_day(client)

    for session in listed(client).values():
        assert loads[session["date"]] == pytest.approx(session["estimated_load"])


# --- what counts as "the watch recorded it" (ADR-015) -----------------------


def test_a_morning_walk_no_longer_cancels_the_evening_training(client, db, schedule_history):
    """The bug this rule fixes. A 07:00 walk is not the 19:00 training, and
    under the old day-level rule it silently deleted the training's whole
    estimate — the day then scored 3 AZM for a day that also held 90
    minutes on the pitch."""
    day = date.today() - timedelta(days=1)
    tracked_day(db, day, exercise_point(day.isoformat(), "07:00:00", "07:30:00", "WALKING", "3"), azm=3)

    session = listed(client)["training#training-yesterday"]
    assert session["skipped"] is False
    assert session["estimated_load"] > 0

    # ...and the day is worth both of them, not one or the other.
    assert loads_by_day(client)[day.isoformat()] == pytest.approx(3 + session["estimated_load"])


def test_a_session_at_the_scheduled_time_replaces_the_estimate(client, db, schedule_history):
    """The double-count guard: a training the watch *did* record must not
    also be estimated."""
    day = date.today() - timedelta(days=1)
    # 19:10+02:00 is 17:10 UTC — ten minutes into the scheduled block.
    tracked_day(db, day, exercise_point(day.isoformat(), "19:10:00", "20:40:00", "SOCCER", "80"), azm=80)

    assert "training#training-yesterday" not in listed(client)
    assert loads_by_day(client)[day.isoformat()] == 80.0


def test_a_session_started_half_an_hour_early_counts_as_the_training(client, db, schedule_history):
    """A watch goes on at arrival. 18:30+02:00 is 16:30 UTC, exactly
    COVER_BEFORE_MINUTES before the block."""
    day = date.today() - timedelta(days=1)
    tracked_day(db, day, exercise_point(day.isoformat(), "18:30:00", "20:00:00", "SOCCER", "77"), azm=77)

    assert "training#training-yesterday" not in listed(client)


def test_a_session_after_the_window_is_a_different_session(client, db, schedule_history):
    """21:01+02:00 is 19:01 UTC — one minute past COVER_AFTER_MINUTES, so
    it is an evening run, not the training."""
    day = date.today() - timedelta(days=1)
    tracked_day(db, day, exercise_point(day.isoformat(), "21:01:00", "21:40:00", "RUNNING", "40"), azm=40)

    session = listed(client)["training#training-yesterday"]
    assert loads_by_day(client)[day.isoformat()] == pytest.approx(40 + session["estimated_load"])


def test_a_match_is_covered_by_a_session_at_kick_off(client, db, schedule_history):
    """Kick-off is 15:00 UTC; 17:20+02:00 is 15:20 UTC."""
    day = date.today() - timedelta(days=2)
    tracked_day(db, day, exercise_point(day.isoformat(), "17:20:00", "18:50:00", "SOCCER", "210"), azm=210)

    assert "match#g-untracked" not in listed(client)
    assert loads_by_day(client)[day.isoformat()] == 210.0


def test_a_match_worn_through_kick_off_is_not_also_estimated(client, db, schedule_history):
    """ADR-022, the reported bug. Kick-off is 15:00 UTC; 16:00+02:00 is
    14:00 UTC — an hour before kick-off and half an hour before the
    COVER_BEFORE_MINUTES window opens (a competitive-match warm-up). The
    session runs to 18:30+02:00 (16:30 UTC), so it spans kick-off and is
    the match: no estimate on top of the 210 AZM it recorded."""
    day = date.today() - timedelta(days=2)
    tracked_day(db, day, exercise_point(day.isoformat(), "16:00:00", "18:30:00", "SOCCER", "210"), azm=210)

    assert "match#g-untracked" not in listed(client)
    assert loads_by_day(client)[day.isoformat()] == 210.0


def test_a_match_with_no_fixture_event_falls_back_to_the_whole_day(client, db, schedule_history):
    """A match the calendar has no "Spiel:" event for has nothing to window
    against, so it behaves exactly as everything did before ADR-015."""
    day = date.today() - timedelta(days=2)
    db.delete_calendar_events(["fixture-treffling"])
    tracked_day(db, day, exercise_point(day.isoformat(), "07:00:00", "07:30:00", "WALKING", "3"), azm=3)

    assert "match#g-untracked" not in listed(client)


def test_two_fixtures_on_one_day_are_not_guessed_between(client, db, schedule_history):
    """Date is the only thing the two sources share — the club names do not
    agree closely enough to match on — so a second fixture that day makes
    the kick-off unknowable, and unknown falls back rather than guesses."""
    day = date.today() - timedelta(days=2)
    db.add(
        CalendarEvent(
            id="fixture-other", calendar_id="primary", title="Spiel: Reserve - Someone",
            start_ts=datetime.combine(day, time(11, 0), tzinfo=UTC), raw={},
        )
    )
    # A morning walk would leave the estimate standing if the kick-off were
    # known; with it unknown, the day-level rule covers the match instead.
    tracked_day(db, day, exercise_point(day.isoformat(), "07:00:00", "07:30:00", "WALKING", "3"), azm=3)

    assert "match#g-untracked" not in listed(client)


def test_a_session_that_cannot_be_placed_covers_its_day(client, db, schedule_history):
    """No interval, no start time, nothing to compare — and inventing a
    second helping of load on top of one already measured is the worse
    mistake, so it is treated as covering."""
    day = date.today() - timedelta(days=1)
    tracked_day(db, day, {"exercise": {"metricsSummary": {"activeZoneMinutes": "44"}}}, azm=44)

    assert "training#training-yesterday" not in listed(client)


def test_a_match_that_was_not_played_is_not_listed(client, db, schedule_history):
    day = date.today() - timedelta(days=4)
    db.add(
        MatchPerformance(
            oefb_game_id="g-benched", match_date=day,
            opponent="Admira", home_away="away", started=False, minutes_played=0,
        )
    )
    db.flush()

    assert "match#g-benched" not in listed(client)


def test_a_tracked_session_carries_no_estimate_and_nothing_to_skip(client, tracked_sessions):
    session = client.get("/health-data/exercises").json()[0]

    assert session["source"] == "tracked"
    assert session["ref_id"] is None
    assert session["estimated_load"] is None
    assert session["skipped"] is False


# --- skipping ---------------------------------------------------------------


def test_skipping_a_match_takes_its_load_back_off_the_day(client, schedule_history):
    day = (date.today() - timedelta(days=2)).isoformat()
    assert loads_by_day(client)[day] > 0

    assert skip(client, "match", "g-untracked").json()["skipped"] is True

    assert loads_by_day(client)[day] == 0.0


def test_a_skipped_session_stays_listed_so_it_can_be_undone(client, schedule_history):
    """Skipping is not deleting — the row is the only place the user can
    take it back, and the estimate stays on it as what was forgone."""
    skip(client, "match", "g-untracked")
    session = listed(client)["match#g-untracked"]

    assert session["skipped"] is True
    assert session["estimated_load"] > 0


def test_unskipping_puts_the_load_back(client, schedule_history):
    day = (date.today() - timedelta(days=1)).isoformat()
    skip(client, "training", "training-yesterday")
    assert loads_by_day(client)[day] == 0.0

    skip(client, "training", "training-yesterday", skipped=False)

    assert loads_by_day(client)[day] > 0


def test_skipping_twice_is_the_same_as_skipping_once(client, schedule_history):
    """A state, not a toggle: a replayed request must not un-skip."""
    skip(client, "match", "g-untracked")
    skip(client, "match", "g-untracked")

    assert listed(client)["match#g-untracked"]["skipped"] is True


def test_skipping_something_that_does_not_exist_is_a_404(client, schedule_history):
    assert skip(client, "match", "no-such-game").status_code == 404
    assert skip(client, "training", "no-such-event").status_code == 404


def test_only_a_training_block_counts_as_a_training_to_skip(client, seeded):
    """`seeded` holds a "Yesterday" event. Skipping it would change no
    number, so it is a 404 rather than a row that quietly does nothing."""
    assert skip(client, "training", "past").status_code == 404


def test_an_unknown_source_is_rejected_by_the_schema(client, schedule_history):
    assert skip(client, "sauna", "g-untracked").status_code == 422


# --- training ---------------------------------------------------------------


def test_training_status_reports_insufficient_data_on_a_thin_history(client, db):
    # A couple of recent days, anchored to today so the materialized
    # rest-day window (services/training._assemble) stays under
    # MIN_HISTORY_DAYS however long after this was written the suite runs.
    db.add_all(
        [
            DailyHealth(date=date.today() - timedelta(days=2), steps=2824, resting_hr=54, raw={}),
            DailyHealth(date=date.today() - timedelta(days=3), steps=9000, resting_hr=56, raw={}),
        ]
    )
    db.flush()

    body = client.get("/training/status").json()
    assert body["status"] == "insufficient_data"
    assert body["series"] == []
    # Declared response model, so every field is present even when unused.
    assert set(body) >= {"fitness", "fatigue", "form", "form_pct", "ramp_pct", "recovery", "notes"}


def test_training_status_with_no_health_data_at_all(client, db):
    assert client.get("/training/status").json()["status"] == "insufficient_data"


@pytest.fixture
def long_history(db):
    """Enough days that a 120-day request and a 400-day one see different
    amounts of history."""
    start = date(2026, 8, 20) - timedelta(days=299)
    db.add_all(
        [
            DailyHealth(
                date=start + timedelta(days=i),
                steps=8000,
                resting_hr=54,
                hrv_ms=70.0,
                sleep_minutes=420,
                active_zone_minutes=20 + (i % 5) * 10,
            )
            for i in range(300)
        ]
    )
    db.commit()


def test_asking_for_more_history_does_not_change_the_numbers(client, long_history):
    """The bug this pins: Fitness used to be seeded from the mean of
    whatever slice was requested, so the same day scored 41.6 over 120 days
    and 40.5 over 366. `days` now trims only what is plotted.
    """
    short = client.get("/training/status?days=120").json()
    long = client.get("/training/status?days=400").json()

    for field in ("fitness", "fatigue", "form", "form_pct", "ramp_pct", "recovery", "readiness", "status"):
        assert short[field] == long[field], field

    # ...while still returning only as much series as was asked for.
    assert len(short["series"]) < len(long["series"])
    assert len(short["series"]) <= 120
    assert short["series"][-1] == long["series"][-1]
    assert short["scores"][-1] == long["scores"][-1]


# --- reports ----------------------------------------------------------------


def test_latest_report_404s_when_there_are_none(client, db):
    assert client.get("/reports/latest").status_code == 404


def test_latest_report_returns_the_newest(client, db):
    db.add_all(
        [
            AiReport(
                created_at=NOW - timedelta(hours=2), trigger="morning_fallback", model="m",
                prompt_version="v1", summary_md="older", insights={},
            ),
            AiReport(
                created_at=NOW, trigger="wake", model="m", prompt_version="v1",
                summary_md="newest", insights={"readiness": "high"},
            ),
        ]
    )
    db.flush()
    body = client.get("/reports/latest").json()
    assert body["summary_md"] == "newest"
    assert body["insights"]["readiness"] == "high"
    assert body["prompt_version"] == "v1"


def test_report_created_since_spots_a_report_after_the_cutoff(db):
    from api.services.reports import report_created_since

    assert report_created_since(db, NOW - timedelta(hours=1)) is False
    db.add(
        AiReport(
            created_at=NOW, trigger="manual", model="m", prompt_version="v2",
            summary_md="x", insights={},
        )
    )
    db.flush()
    assert report_created_since(db, NOW - timedelta(hours=1)) is True
    # A cutoff after the report (e.g. tomorrow's local midnight) doesn't match.
    assert report_created_since(db, NOW + timedelta(hours=1)) is False


def test_generate_returns_the_report_it_stored(client, db, monkeypatch):
    import api.routers.reports as reports
    from api.store import rows

    def fake_run_analysis(store, trigger: str) -> rows.AiReport:
        report = rows.AiReport(
            id=store.next_ids("reports")[0],
            created_at=NOW,
            trigger=trigger,
            model="m",
            prompt_version="v5",
            summary_md="fresh",
            insights={"readiness": "high"},
        )
        store.put_report(report)
        return report

    monkeypatch.setattr(reports, "run_analysis", fake_run_analysis)

    body = client.post("/reports/generate").json()
    assert (body["trigger"], body["summary_md"]) == ("manual", "fresh")
    assert client.get("/reports/latest").json()["id"] == body["id"]


def test_generate_reports_a_spent_budget_as_429_not_500(client, monkeypatch):
    """GeminiQuotaExceeded subclasses RuntimeError, and the RuntimeError
    branch returns 500 — so the order of the two except clauses is the
    whole test."""
    import api.routers.reports as reports
    from api.services.gemini_usage import GeminiQuotaExceeded

    def boom(_store, _trigger):
        raise GeminiQuotaExceeded("All 6 of today's Gemini requests are spent")

    monkeypatch.setattr(reports, "run_analysis", boom)

    res = client.post("/reports/generate")
    assert res.status_code == 429
    assert "spent" in res.json()["detail"]


def test_generate_without_a_gemini_key_says_so(client):
    res = client.post("/reports/generate")
    assert res.status_code == 500
    assert "GEMINI_API_KEY" in res.json()["detail"]


def test_refresh_endpoint_pulls_the_google_sources_then_reports(client, db, monkeypatch):
    import api.routers.reports as reports
    from api.store import rows

    order: list[str] = []

    def pull(_store):
        order.append("sync")
        return {"health": "ok", "heart_rate": "ok", "calendar": "failed: grant revoked"}

    def fake_run_analysis(_store, trigger: str) -> rows.AiReport:
        order.append(trigger)
        return rows.AiReport(
            id=1,
            created_at=NOW,
            trigger=trigger,
            model="m",
            prompt_version="v5",
            summary_md="on fresh data",
            insights={},
        )

    monkeypatch.setattr(reports, "refresh_google_sources", pull)
    monkeypatch.setattr(reports, "run_analysis", fake_run_analysis)

    body = client.post("/reports/refresh").json()
    assert order == ["sync", "manual_refresh"]
    assert body["sources"]["calendar"].startswith("failed")
    assert body["report"]["summary_md"] == "on fresh data"


def test_refresh_endpoint_checks_the_gemini_budget_before_pulling(client, monkeypatch):
    import api.routers.reports as reports
    from api.services.gemini_usage import GeminiQuotaExceeded

    pulled: list[bool] = []
    monkeypatch.setattr(reports, "refresh_google_sources", lambda _store: pulled.append(True) or {})

    def out_of_budget(_store) -> None:
        raise GeminiQuotaExceeded("today's requests are spent")

    monkeypatch.setattr(reports.gemini_usage, "require_report_budget", out_of_budget)

    assert client.post("/reports/refresh").status_code == 429
    assert pulled == []  # no network work once the day is known to be spent


# --- push -------------------------------------------------------------------


SUB = {"endpoint": "https://push.example/abc", "keys": {"p256dh": "key", "auth": "auth"}}


# --- oauth ------------------------------------------------------------------


# --- coach ------------------------------------------------------------------


# --- workouts attached to a chat (ADR-021) ----------------------------------


# --- webhooks ---------------------------------------------------------------


# --- contract ---------------------------------------------------------------


def test_every_endpoint_declares_a_response_schema(client):
    """An endpoint returning a bare dict shows up as an untyped {} here,
    which is what made the frontend types hand-written guesswork."""
    # The /openapi.json URL is off (ADR-029); the schema itself is the same.
    spec = app.openapi()
    untyped = [
        f"{method.upper()} {path} -> {code}"
        for path, ops in spec["paths"].items()
        for method, op in ops.items()
        for code, resp in op.get("responses", {}).items()
        if resp.get("content", {}).get("application/json", {}).get("schema") == {}
    ]
    assert untyped == []
