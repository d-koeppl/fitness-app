"""Tests for api/services/session_context.py — a workout, in full, for the coach.

Needs the Firestore emulator (the `db` fixture, tests/conftest.py): a
session is read back out of the stored day's `raw`, and that round-trip is
half of what is being checked here.

What matters in this file is that the payload is *honest*. The model cannot
see the dashboard, so every one of these is about the payload saying what it
is holding rather than leaving the model to assume: how much of the trace is
in front of it, why a trace is absent, and what the zone seconds are an
answer to.
"""

from __future__ import annotations

from datetime import date, datetime, timedelta, timezone

import pytest

from api.config import settings
from api.services.exercises import find_sessions
from api.services.session_context import (
    NO_READINGS,
    NOT_SYNCED,
    STORED,
    UNTRACKED,
    attached_sessions,
)
from tests.legacy_db import DailyHealth, ExerciseHeartRate

VIENNA = timezone(timedelta(hours=2))


def exercise_point(day: str, start: str, end: str, kind: str, azm: str) -> dict:
    """The live-confirmed session shape (api/services/sessions.py) — int64-ish
    fields as JSON strings, an RFC-3339 interval with a local offset."""
    return {
        "exercise": {
            "exerciseType": kind,
            "interval": {"startTime": f"{day}T{start}+02:00", "endTime": f"{day}T{end}+02:00"},
            "metricsSummary": {
                "activeZoneMinutes": azm,
                "averageHeartRateBeatsPerMinute": "150",
                "distanceMillimeters": "8412000",
            },
        }
    }


@pytest.fixture
def untraced_run(db, monkeypatch):
    """One tracked run on the 20th, before its trace has been fetched."""
    monkeypatch.setattr(settings, "health_max_hr_bpm", 191)
    db.add_all(
        [
            DailyHealth(date=date(2026, 8, 17), resting_hr=56, raw={}),
            DailyHealth(
                date=date(2026, 8, 20),
                active_zone_minutes=34,
                raw={"exercise": [exercise_point("2026-08-20", "17:00:00", "18:05:00", "RUNNING", "34")]},
            ),
        ]
    )
    db.flush()
    return db


@pytest.fixture
def run(untraced_run):
    """The same run, with a trace and Google's time in zone."""
    db = untraced_run
    db.add(
        ExerciseHeartRate(
            session_start=datetime(2026, 8, 20, 17, 0, tzinfo=VIENNA),
            date=date(2026, 8, 20),
            session_end=datetime(2026, 8, 20, 18, 5, tzinfo=VIENNA),
            samples=[[0, 95], [10, 120], [20, 152], [30, 148]],
            zone_seconds={"FAT_BURN": 600.0, "CARDIO": 2400.0},
            fetched_at=datetime(2026, 8, 20, 20, 0, tzinfo=VIENNA),
        )
    )
    db.flush()
    return db


# --- the lookup -------------------------------------------------------------


def test_a_session_is_found_by_id_however_old_it_is(run):
    """`list_exercise_sessions` answers "the newest N"; a pinned workout has
    to keep resolving long past the end of that list."""
    found = find_sessions(run, ["2026-08-20#0"])
    assert list(found) == ["2026-08-20#0"]
    assert found["2026-08-20#0"].exercise_type == "RUNNING"


def test_a_match_id_is_not_mistaken_for_a_tracked_one(run, db, monkeypatch):
    """A match's ref is the OEFB game id, which is all digits — so "the part
    after the # is a number" matches `match#99182` as well as it matches
    `2026-08-20#0`, and reading the id that way loses every untracked
    session. The prefix is what tells them apart."""
    from api.services import exercises

    untracked = exercises.ExerciseSession(
        id="match#99182",
        date=date(2026, 8, 16),
        start_ts=datetime(2026, 8, 16, 16, 30, tzinfo=VIENNA),
        end_ts=None,
        exercise_type=None,
        duration_minutes=90.0,
        active_zone_minutes=None,
        average_heart_rate=None,
        source="match",
        ref_id="99182",
        title="vs Treffling",
        estimated_load=224.0,
    )
    monkeypatch.setattr(exercises, "_estimated_rows", lambda _estimated: [untracked])

    assert list(find_sessions(run, ["match#99182"])) == ["match#99182"]


def test_an_untracked_session_says_there_was_never_a_trace(run, db, monkeypatch):
    """ "No watch was involved" is not the same claim as "the watch recorded
    nothing" — only the second is about the session going unmeasured."""
    from api.services import exercises

    monkeypatch.setattr(
        exercises,
        "_estimated_rows",
        lambda _estimated: [
            exercises.ExerciseSession(
                id="match#99182",
                date=date(2026, 8, 16),
                start_ts=datetime(2026, 8, 16, 16, 30, tzinfo=VIENNA),
                end_ts=None,
                exercise_type=None,
                duration_minutes=90.0,
                active_zone_minutes=None,
                average_heart_rate=None,
                source="match",
                ref_id="99182",
                title="vs Treffling",
                estimated_load=224.0,
            )
        ],
    )

    session = attached_sessions(run, ["match#99182"]).sessions[0]
    assert session["title"] == "vs Treffling"
    assert session["estimated_load"] == 224.0
    assert session["active_zone_minutes"] is None
    assert session["heart_rate"]["status"] == UNTRACKED
    assert "never was" in session["heart_rate"]["note"]
    # Not stubbed through the schedule, so no match is attached — the field
    # is still there, and says so.
    assert session["match"] is None


def test_an_id_that_names_nothing_is_absent_rather_than_raising(run):
    assert find_sessions(run, ["2026-08-20#7", "not-an-id", "1999-01-01#0"]) == {}


def test_the_lookup_answers_in_the_order_it_was_asked(run, db):
    db.add(
        DailyHealth(
            date=date(2026, 8, 18),
            active_zone_minutes=12,
            raw={"exercise": [exercise_point("2026-08-18", "07:00:00", "07:30:00", "WALKING", "12")]},
        )
    )
    db.flush()
    assert list(find_sessions(run, ["2026-08-20#0", "2026-08-18#0"])) == [
        "2026-08-20#0",
        "2026-08-18#0",
    ]


# --- the payload ------------------------------------------------------------


def test_nothing_attached_is_not_a_query(run):
    assert attached_sessions(run, []) == attached_sessions(run, [])
    assert attached_sessions(run, []).sessions == []


def test_the_whole_session_comes_through_named_fields_and_metrics_bag(run):
    session = attached_sessions(run, ["2026-08-20#0"]).sessions[0]

    assert session["type"] == "RUNNING"
    assert session["duration_minutes"] == 65.0
    assert session["active_zone_minutes"] == 34.0
    assert session["average_heart_rate"] == 150.0
    # Passed through under Google's own name, units included (ADR-012).
    assert session["metrics"] == {"distanceMillimeters": 8412000.0}
    # The user's clock, like every other time in the context — a model given
    # the UTC hour just repeats it back as if it were local.
    assert session["start"].startswith("2026-08-20T17:00:00+02:00")


def test_the_trace_comes_through_whole_with_its_zones(run):
    heart_rate = attached_sessions(run, ["2026-08-20#0"]).sessions[0]["heart_rate"]

    assert heart_rate["status"] == STORED
    assert heart_rate["samples"] == [[0, 95], [10, 120], [20, 152], [30, 148]]
    assert heart_rate["sample_count"] == 4
    assert heart_rate["samples_included"] == 4
    assert (heart_rate["min_bpm"], heart_rate["max_bpm"]) == (95, 152)
    assert heart_rate["zone_source"] == "google"
    assert {z["zone"]: z["seconds"] for z in heart_rate["zones"]}["cardio"] == 2400.0


def test_the_coach_gets_more_of_the_trace_than_the_chart_does(run, db, monkeypatch):
    """The whole reason this module exists: the detail sheet asks for what a
    phone can draw, and the model is being asked to analyse the readings the
    chart throws away."""
    monkeypatch.setattr(settings, "health_hr_chart_points", 10)
    monkeypatch.setattr(settings, "coach_session_hr_max_samples", 3000)
    row = db.get(ExerciseHeartRate, datetime(2026, 8, 20, 17, 0, tzinfo=VIENNA))
    row.samples = [[i * 3, 100 + (i % 40)] for i in range(600)]
    db.flush()

    heart_rate = attached_sessions(run, ["2026-08-20#0"]).sessions[0]["heart_rate"]
    assert heart_rate["samples_included"] == 600
    assert heart_rate["sampling"] == "every reading the watch took"


def test_a_thinned_trace_says_so_and_keeps_the_extremes(run, db, monkeypatch):
    """A model told "here is the heart rate" and handed a tenth of it would
    reason about peaks that were never in front of it."""
    monkeypatch.setattr(settings, "coach_session_hr_max_samples", 20)
    row = db.get(ExerciseHeartRate, datetime(2026, 8, 20, 17, 0, tzinfo=VIENNA))
    row.samples = [[i, 100] for i in range(500)] + [[500, 188], [501, 61]]
    db.flush()

    heart_rate = attached_sessions(run, ["2026-08-20#0"]).sessions[0]["heart_rate"]

    assert heart_rate["sample_count"] == 502
    assert heart_rate["samples_included"] <= 20
    assert "thinned from 502 stored readings" in heart_rate["sampling"]
    # The stats are over the full stored trace either way, and the peak and
    # the trough survive the thinning, so the range in the samples matches.
    assert (heart_rate["min_bpm"], heart_rate["max_bpm"]) == (61, 188)
    bpms = [bpm for _, bpm in heart_rate["samples"]]
    assert max(bpms) == 188


def test_a_session_the_sync_has_not_reached_is_not_a_session_without_a_heart_rate(untraced_run):
    """Two very different sentences. Only one of them is about the workout."""
    heart_rate = attached_sessions(untraced_run, ["2026-08-20#0"]).sessions[0]["heart_rate"]
    assert heart_rate["status"] == NOT_SYNCED
    assert "Not fetched yet" in heart_rate["note"]


def test_a_fetched_session_with_no_readings_says_that_instead(run, db):
    row = db.get(ExerciseHeartRate, datetime(2026, 8, 20, 17, 0, tzinfo=VIENNA))
    row.samples = []
    db.flush()

    heart_rate = attached_sessions(run, ["2026-08-20#0"]).sessions[0]["heart_rate"]
    assert heart_rate["status"] == NO_READINGS
    assert "recorded no heart rate" in heart_rate["note"]


def test_without_a_max_hr_the_readings_still_come_through_unzoned(run, monkeypatch):
    """The same honest fallback the chart makes: no configured max means no
    boundaries anybody measured, which is not a reason to withhold the
    readings."""
    monkeypatch.setattr(settings, "health_max_hr_bpm", None)
    monkeypatch.setattr(settings, "health_birth_year", None)

    heart_rate = attached_sessions(run, ["2026-08-20#0"]).sessions[0]["heart_rate"]
    assert heart_rate["samples"]
    assert "zones" not in heart_rate
    assert "HEALTH_MAX_HR_BPM" in heart_rate["zones_note"]


def test_an_id_that_no_longer_resolves_is_reported_not_dropped(run):
    """The user can see the chip in the composer, so a workout that quietly
    never gets mentioned reads as the coach ignoring the question."""
    result = attached_sessions(run, ["2026-08-20#0", "2026-08-20#9"])

    assert [s["session_id"] for s in result.sessions] == ["2026-08-20#0"]
    assert result.missing == ["2026-08-20#9"]


def test_more_than_the_cap_is_reported_rather_than_silently_trimmed(run, monkeypatch):
    """Being told "only the first one was sent" is the difference between a
    bounded feature and a silently wrong answer."""
    monkeypatch.setattr(settings, "coach_max_attached_sessions", 1)
    result = attached_sessions(run, ["2026-08-20#0", "2026-08-20#1"])

    assert [s["session_id"] for s in result.sessions] == ["2026-08-20#0"]
    assert result.missing == ["2026-08-20#1"]
