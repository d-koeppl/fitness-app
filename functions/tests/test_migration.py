"""tools/migrate/import_firestore.py on a small dump in the shape
export_postgres.py writes (Postgres' own json_agg output).

The real proof of the migration is the day-by-day comparison against the
old API on production data (ADR-031, tools/migrate/README.md). This
guards the importer itself between those runs: that every table lands,
ids survive, and running it twice changes nothing.
"""

from __future__ import annotations

import json
import sys
from datetime import UTC, date, datetime
from pathlib import Path

import pytest

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "tools" / "migrate"))

import import_firestore  # noqa: E402

DUMP = {
    "daily_health": [
        {
            "date": "2026-09-01",
            "steps": 9000,
            "resting_hr": 54,
            "hrv_ms": 81.5,
            "sleep_minutes": 420,
            "active_kcal": 500,
            "active_zone_minutes": 30,
            "weight_kg": 79.1,
            "vo2max": None,
            "source": "google_health",
            "raw": {"exercise": [{"a": [[1, 2]]}]},
            "updated_at": "2026-09-01T10:00:00.123456+00:00",
        }
    ],
    "calendar_events": [
        {
            "id": "evt1",
            "calendar_id": "primary",
            "title": "Training",
            "start_ts": "2026-09-02T16:30:00+00:00",
            "end_ts": "2026-09-02T19:30:00+00:00",
            "all_day": False,
            "category": None,
            "location": None,
            "raw": {"id": "evt1"},
            "updated_at": "2026-09-01T10:00:00+00:00",
        }
    ],
    "match_performances": [
        {
            "id": 7,
            "oefb_game_id": "4060289",
            "match_date": "2026-07-10",
            "opponent": "Gramastetten",
            "home_away": "home",
            "result": "4:0",
            "started": True,
            "minutes_played": 90,
            "goals": 0,
            "yellow_card": False,
            "red_card": False,
            "created_at": "2026-08-21T09:59:31.000296+00:00",
        }
    ],
    "exercise_heart_rate": [
        {
            "session_start": "2026-09-08T17:02:00.8+00:00",
            "date": "2026-09-08",
            "session_end": "2026-09-08T18:00:00+00:00",
            "samples": [[0, 90], [5, 101]],
            "zone_seconds": {},
            "fetched_at": "2026-09-08T20:00:00+00:00",
        }
    ],
    "skipped_activities": [
        {"source": "training", "ref_id": "evt1", "created_at": "2026-08-25T19:52:28+00:00"}
    ],
    "ai_reports": [
        {
            "id": 45,
            "created_at": "2026-09-25T06:30:00+00:00",
            "trigger": "manual",
            "period_start": None,
            "period_end": None,
            "model": "m",
            "prompt_version": "v",
            "summary_md": "s",
            "insights": {"flags": [], "trends": ["x"]},
            "tokens_used": 100,
        }
    ],
    "drink_logs": [
        {"id": 3, "logged_at": "2026-09-10T19:52:23.553696+00:00", "counted_report_id": 45, "drank_on": None},
        {"id": 30, "logged_at": "2026-09-24T20:00:00+00:00", "counted_report_id": None, "drank_on": None},
    ],
    "conversations": [
        {
            "id": 2,
            "title": "t",
            "created_at": "2026-09-10T07:12:50+00:00",
            "updated_at": "2026-09-10T07:16:09+00:00",
            "include": {"health": True},
            "lookback_days": 14,
            "session_ids": [],
        }
    ],
    "conversation_messages": [
        {
            "id": 1,
            "conversation_id": 2,
            "role": "user",
            "content": "q",
            "created_at": "2026-09-10T07:12:50+00:00",
        },
        {
            "id": 2,
            "conversation_id": 2,
            "role": "assistant",
            "content": "a",
            "created_at": "2026-09-10T07:12:50+00:00",
        },
    ],
    "gemini_usage": [
        {
            "day": "2026-08-25",
            "model": "gemini-3.6-flash",
            "requests": 2,
            "updated_at": "2026-08-25T19:53:58+00:00",
        }
    ],
    "oauth_tokens": [
        {
            "provider": "google_health",
            "access_token_enc": "a",
            "refresh_token_enc": "r",
            "expiry": "2026-09-25T08:00:00+00:00",
            "scopes": "s",
            "updated_at": "2026-09-25T07:00:00+00:00",
        }
    ],
}


@pytest.fixture
def dump(tmp_path: Path) -> Path:
    for table, rows in DUMP.items():
        (tmp_path / f"{table}.json").write_text(json.dumps(rows), encoding="utf-8")
    return tmp_path


def test_every_table_lands_with_its_ids(store, dump):
    written = import_firestore.migrate(dump, store)
    assert written == {table: len(rows) for table, rows in DUMP.items()}

    day = store.health_day(date(2026, 9, 1))
    assert (day.steps, day.hrv_ms, day.vo2max) == (9000, 81.5, None)
    assert day.raw == {"exercise": [{"a": [[1, 2]]}]}
    assert store.calendar_event("evt1").start_ts == datetime(2026, 9, 2, 16, 30, tzinfo=UTC)
    assert store.match("4060289").id == 7
    trace = store.hr_trace(datetime(2026, 9, 8, 17, 2, 0, 800000, tzinfo=UTC))
    assert trace.samples == [[0, 90], [5, 101]]
    assert [(s.source, s.ref_id) for s in store.skipped()] == [("training", "evt1")]
    assert store.latest_report().id == 45
    assert [d.id for d in store.pending_drinks()] == [30]
    assert store.conversation(2).message_count == 2
    assert [m.content for m in store.messages(2)] == ["q", "a"]
    assert store.gemini_usage(date(2026, 8, 25)) == {"gemini-3.6-flash": 2}
    assert store.oauth_token("google_health").refresh_token_enc == "r"


def test_new_ids_continue_after_the_migrated_ones(store, dump):
    import_firestore.migrate(dump, store)
    assert store.next_ids("drinks") == [31]
    assert store.next_ids("reports") == [46]
    assert store.next_ids("conversations") == [3]


def test_importing_twice_is_the_same_as_once(store, dump):
    import_firestore.migrate(dump, store)
    import_firestore.migrate(dump, store)

    assert len(store.health_days()) == 1
    assert len(store.calendar_events()) == 1
    assert len(store.pending_drinks()) == 1
    assert store.gemini_usage(date(2026, 8, 25)) == {"gemini-3.6-flash": 2}
    assert len(store.messages(2)) == 2
