"""The sync jobs, with Google stubbed out and the store on the emulator.

The heart-rate and calendar tests at the top are carried over from
fitness-dashboard (test_heart_rate.py's sync section, test_config_and_
ingest.py); the rest pin what phase 3 changed — the writes now go through
the store, and one hourly function runs them all.
"""

from __future__ import annotations

from datetime import UTC, date, datetime, timedelta
from zoneinfo import ZoneInfo

import pytest
import requests

from api import jobs
from api.ingest import calendar as calendar_ingest
from api.ingest import health as health_ingest
from api.ingest import heart_rate as ingest
from api.ingest import refresh
from api.services import sessions as hr_sessions
from api.store.rows import DailyHealth
from tests.legacy_db import DailyHealth as LegacyDailyHealth

VIENNA = ZoneInfo("Europe/Vienna")

# --- which sessions the sync picks up (ADR-020) -----------------------------


def session_at(start: datetime, end: datetime | None) -> hr_sessions.ExerciseSession:
    return hr_sessions.ExerciseSession(
        id="x",
        date=start.date(),
        start_ts=start,
        end_ts=end,
        exercise_type="RUNNING",
        duration_minutes=None,
        active_zone_minutes=None,
        average_heart_rate=None,
    )


SESSION = session_at(datetime(2026, 8, 20, 17, 0, tzinfo=UTC), datetime(2026, 8, 20, 18, 5, tzinfo=UTC))
SETTLED_AT = SESSION.end_ts + timedelta(hours=ingest.SETTLE_HOURS)


class _Stored:
    def __init__(self, fetched_at):
        self.fetched_at = fetched_at


@pytest.mark.parametrize(
    "stored, now, expected",
    [
        (None, SETTLED_AT, True),
        # Fetched mid-session and the settle window has passed: one more look.
        (_Stored(SESSION.start_ts + timedelta(minutes=20)), SETTLED_AT, True),
        # Same row, but the window has not passed yet — re-fetching now would
        # happen again on every hourly sync until it has.
        (_Stored(SESSION.start_ts + timedelta(minutes=20)), SETTLED_AT - timedelta(hours=1), False),
        # Settled: whatever it holds, samples or none, is what there is.
        (_Stored(SETTLED_AT + timedelta(minutes=1)), SETTLED_AT + timedelta(days=3), False),
    ],
    ids=["never fetched", "caught mid-session", "still settling", "settled"],
)
def test_which_stored_traces_are_worth_another_look(stored, now, expected):
    assert ingest._needs_fetch(SESSION, stored, now) is expected


def test_the_sync_skips_sessions_it_could_not_ask_about(db):
    """A session with no end, or a timestamp that carried no offset, has no
    window to fetch — and mixing a naive one into the list would break the
    sort as well as the request."""
    day = date(2026, 8, 20)
    db.add(
        LegacyDailyHealth(
            date=day,
            raw={
                "exercise": [
                    # Fetchable.
                    {
                        "exercise": {
                            "interval": {
                                "startTime": "2026-08-20T17:00:00+02:00",
                                "endTime": "2026-08-20T18:05:00+02:00",
                            }
                        }
                    },
                    # No offset on the timestamps — unplaceable.
                    {
                        "exercise": {
                            "interval": {"startTime": "2026-08-20T07:00:00", "endTime": "2026-08-20T07:30:00"}
                        }
                    },
                    # No end.
                    {"exercise": {"interval": {"startTime": "2026-08-20T12:00:00+02:00"}}},
                ]
            },
        )
    )
    db.flush()

    sessions = ingest._tracked_sessions(db, date(2026, 8, 1))

    assert [s.start_ts.isoformat() for s in sessions] == ["2026-08-20T17:00:00+02:00"]


# --- calendar _parse_when -------------------------------------------------------


def test_timed_event_keeps_its_offset():
    when, all_day = calendar_ingest._parse_when({"dateTime": "2026-08-20T19:00:00+02:00"})
    assert all_day is False
    assert when == datetime(2026, 8, 20, 19, 0, tzinfo=when.tzinfo)
    assert when.utcoffset().total_seconds() == 2 * 3600


def test_all_day_event_is_flagged_and_given_a_timezone():
    when, all_day = calendar_ingest._parse_when({"date": "2026-08-20"})
    assert all_day is True
    assert when == datetime(2026, 8, 20, tzinfo=UTC)


def test_event_with_neither_shape():
    assert calendar_ingest._parse_when({}) == (None, False)


def test_no_button_runs_the_oefb_scrape():
    # Both the sync chip (ADR-026) and New report (ADR-027) pull these three;
    # the ÖFB scrape is left to the nightly run.
    assert [label for label, _ in refresh._GOOGLE_SOURCES] == ["health", "heart_rate", "calendar"]


# --- the syncs write through the store ------------------------------------------------


def test_health_sync_rounds_integers_and_merges_raw(store, monkeypatch):
    day = date(2026, 9, 1)
    store.put_health_days([DailyHealth(date=day, weight_kg=80.0, raw={"weight": {"kept": True}})])
    monkeypatch.setattr(
        health_ingest,
        "fetch_all_daily_metrics",
        lambda: {day: {"steps": 9000.4, "hrv_ms": 81.5, "raw": {"steps": {"new": True}}}},
    )

    assert health_ingest.sync_daily_health(store) == 1

    row = store.health_day(day)
    assert row.steps == 9000 and isinstance(row.steps, int)
    assert row.hrv_ms == 81.5
    assert row.weight_kg == 80.0  # a metric this pull did not return is left alone
    assert row.raw == {"weight": {"kept": True}, "steps": {"new": True}}


def test_calendar_sync_stores_events_and_skips_cancelled_ones(store, monkeypatch):
    items = [
        {
            "id": "a",
            "summary": "Training",
            "start": {"dateTime": "2026-09-02T18:30:00+02:00"},
            "end": {"dateTime": "2026-09-02T21:30:00+02:00"},
        },
        {"id": "b", "status": "cancelled", "start": {"dateTime": "2026-09-03T18:30:00+02:00"}},
        {"id": "c", "summary": "Birthday", "start": {"date": "2026-09-04"}, "end": {"date": "2026-09-05"}},
    ]
    monkeypatch.setattr(calendar_ingest, "fetch_events", lambda calendar_id: items)

    assert calendar_ingest.sync_calendar_events(store, ["primary"]) == 2

    stored = store.calendar_events()
    assert [e.id for e in stored] == ["a", "c"]
    assert stored[0].title == "Training" and stored[0].raw["id"] == "a"
    assert stored[1].all_day is True


def test_a_rescheduled_event_moves_month_on_the_next_sync(store, monkeypatch):
    item = {"id": "a", "summary": "Spiel: X - Y", "start": {"dateTime": "2026-09-30T18:00:00+02:00"}}
    monkeypatch.setattr(calendar_ingest, "fetch_events", lambda calendar_id: [item])
    calendar_ingest.sync_calendar_events(store, ["primary"])

    item["start"] = {"dateTime": "2026-10-03T18:00:00+02:00"}
    calendar_ingest.sync_calendar_events(store, ["primary"])

    assert [e.start_ts.isoformat() for e in store.calendar_events()] == ["2026-10-03T16:00:00+00:00"]


def _health_row_with_session(day: date) -> DailyHealth:
    return DailyHealth(
        date=day,
        raw={
            "exercise": [
                {
                    "exercise": {
                        "interval": {
                            "startTime": f"{day.isoformat()}T17:00:00+02:00",
                            "endTime": f"{day.isoformat()}T18:00:00+02:00",
                        }
                    }
                }
            ]
        },
    )


def test_heart_rate_sync_stores_a_trace_and_an_empty_one(store, monkeypatch):
    today = datetime.now(VIENNA).date()
    days = [today - timedelta(days=2), today - timedelta(days=1)]
    store.put_health_days([_health_row_with_session(d) for d in days])

    def samples(start, end):
        if start.date() == days[1]:
            return [(start, 120), (start + timedelta(seconds=5), 125)]
        return []  # the watch recorded nothing — an answer, stored empty

    monkeypatch.setattr(ingest, "fetch_heart_rate_samples", samples)
    monkeypatch.setattr(ingest, "fetch_time_in_zones", lambda start, end: {"CARDIO": 5.0})

    assert ingest.sync_exercise_heart_rate(store) == 2

    traces = {t.date: t for t in store.hr_traces_since(days[0])}
    assert traces[days[1]].samples == [[0, 120], [5, 125]]
    assert traces[days[1]].zone_seconds == {"CARDIO": 5.0}
    assert traces[days[0]].samples == [] and traces[days[0]].zone_seconds == {}


def test_a_failed_heart_rate_fetch_stores_nothing(store, monkeypatch):
    day = datetime.now(VIENNA).date() - timedelta(days=1)
    store.put_health_days([_health_row_with_session(day)])

    def fail(start, end):
        raise requests.HTTPError("503")

    monkeypatch.setattr(ingest, "fetch_heart_rate_samples", fail)

    assert ingest.sync_exercise_heart_rate(store) == 0
    assert store.hr_traces_since(day) == []


# --- the hourly job -------------------------------------------------------------------


@pytest.fixture
def sources(monkeypatch):
    """Record what the job ran, instead of reaching Google or the ÖFB site."""
    ran: list[str] = []
    monkeypatch.setattr(
        refresh,
        "_GOOGLE_SOURCES",
        tuple(
            (label, lambda store, label=label: ran.append(label))
            for label in ("health", "heart_rate", "calendar")
        ),
    )
    import oefb.scraper

    monkeypatch.setattr(oefb.scraper, "run", lambda store, days: ran.append(f"oefb:{days}") or 0)
    return ran


def test_every_hour_syncs_the_three_google_sources(sources):
    jobs.run_hourly(object(), datetime(2026, 9, 25, 14, 30, tzinfo=VIENNA))
    assert sources == ["health", "heart_rate", "calendar"]


def test_the_oefb_scrape_runs_only_in_its_hour(sources):
    from api.config import settings

    results = jobs.run_hourly(object(), datetime(2026, 9, 25, settings.oefb_sync_hour, 30, tzinfo=VIENNA))
    assert sources[-1] == f"oefb:{settings.oefb_sync_days_back}"
    assert results["oefb"] == "ok (0 new)"


def test_a_failing_source_does_not_stop_the_others(monkeypatch):
    ran: list[str] = []

    def boom(store):
        raise RuntimeError("revoked")

    monkeypatch.setattr(
        refresh,
        "_GOOGLE_SOURCES",
        (
            ("health", boom),
            ("heart_rate", lambda s: ran.append("hr")),
            ("calendar", lambda s: ran.append("cal")),
        ),
    )
    results = refresh.refresh_google_sources(object())
    assert results == {"health": "failed: revoked", "heart_rate": "ok", "calendar": "ok"}
    assert ran == ["hr", "cal"]


def test_the_fallback_report_runs_only_in_its_hour_and_after_the_sync(sources, monkeypatch):
    from api.analysis import gemini
    from api.config import settings

    tries: list[bool] = []

    def fallback(store, last_try=False):
        sources.append("report")
        tries.append(last_try)
        return "ok (report 1)"

    monkeypatch.setattr(gemini, "run_daily_fallback", fallback)

    jobs.run_hourly(object(), datetime(2026, 9, 25, 14, 30, tzinfo=VIENNA))
    assert "report" not in sources

    results = jobs.run_hourly(object(), datetime(2026, 9, 25, settings.wake_fallback_hour, 30, tzinfo=VIENNA))
    # After the sync, so the report reads data at most a minute old.
    assert sources[-4:] == ["health", "heart_rate", "calendar", "report"]
    assert results["report"] == "ok (report 1)"

    # An hour later, the last try (ADR-034); nothing the hour after.
    jobs.run_hourly(object(), datetime(2026, 9, 25, settings.wake_fallback_hour + 1, 30, tzinfo=VIENNA))
    jobs.run_hourly(object(), datetime(2026, 9, 25, settings.wake_fallback_hour + 2, 30, tzinfo=VIENNA))
    assert tries == [False, True]


def test_a_failed_fallback_report_is_logged_not_raised(sources, monkeypatch):
    from api.analysis import gemini
    from api.config import settings

    def boom(store, last_try=False):
        raise RuntimeError("GEMINI_API_KEY is not set")

    monkeypatch.setattr(gemini, "run_daily_fallback", boom)
    results = jobs.run_hourly(object(), datetime(2026, 9, 25, settings.wake_fallback_hour, 30, tzinfo=VIENNA))
    assert results["report"] == "failed: GEMINI_API_KEY is not set"
    assert results["health"] == "ok"
