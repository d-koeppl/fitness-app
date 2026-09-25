"""Yesterday's game missing from the ÖFB log (api/services/matches.py), the
endpoint the dashboard reads it from, and the check after the nightly scrape."""

from __future__ import annotations

from datetime import date, datetime, time, timedelta
from zoneinfo import ZoneInfo

from fastapi.testclient import TestClient

from api.main import app
from api.services.matches import missing_match
from api.store.firestore import get_store
from tests.legacy_db import CalendarEvent, MatchPerformance

VIENNA = ZoneInfo("Europe/Vienna")
# 09:00 local on a Sunday: after the 03:30 scrape.
NOW = datetime(2026, 9, 20, 9, 0, tzinfo=VIENNA)
YESTERDAY = date(2026, 9, 19)


def _fixture(day: date, hour: int, title: str = "Spiel: Union Eidenberg/Geng - Treffling") -> CalendarEvent:
    start = datetime.combine(day, time(hour, 0), tzinfo=VIENNA)
    return CalendarEvent(
        id=f"fixture-{day}-{hour}", calendar_id="primary", title=title,
        start_ts=start, end_ts=start + timedelta(hours=2), raw={},
    )


def _logged(day: date) -> MatchPerformance:
    return MatchPerformance(
        oefb_game_id=f"g-{day}", match_date=day, opponent="Treffling", home_away="home",
    )


def test_a_fixture_yesterday_with_no_logged_game_is_missing(db):
    db.add(_fixture(YESTERDAY, 16))
    db.flush()

    missing = missing_match(db, NOW)

    assert missing is not None
    assert missing.day == YESTERDAY
    assert missing.title == "Spiel: Union Eidenberg/Geng - Treffling"
    assert missing.kickoff == datetime.combine(YESTERDAY, time(16, 0), tzinfo=VIENNA)


def test_a_logged_game_clears_it(db):
    db.add_all([_fixture(YESTERDAY, 16), _logged(YESTERDAY)])
    db.flush()

    assert missing_match(db, NOW) is None


def test_only_yesterday_counts(db):
    # The day before yesterday is outside the window, and so is a training.
    db.add_all(
        [
            _fixture(YESTERDAY - timedelta(days=1), 16),
            _fixture(YESTERDAY, 19, title="Training"),
            # Midnight local starts today, not yesterday.
            _fixture(NOW.date(), 0, title="Spiel: today's game"),
        ]
    )
    db.flush()

    assert missing_match(db, NOW) is None


def test_a_late_kickoff_is_still_yesterday_in_local_time(db):
    # 23:30 in Vienna is already the next day in UTC.
    late = datetime.combine(YESTERDAY, time(23, 30), tzinfo=VIENNA)
    db.add(
        CalendarEvent(
            id="late", calendar_id="primary", title="Spiel: late one",
            start_ts=late, end_ts=late + timedelta(hours=2), raw={},
        )
    )
    db.flush()

    missing = missing_match(db, NOW)
    assert missing is not None and missing.title == "Spiel: late one"


def test_nothing_is_missing_before_the_nightly_scrape_has_run(db):
    db.add(_fixture(YESTERDAY, 16))
    db.flush()

    assert missing_match(db, NOW.replace(hour=2)) is None


def test_endpoint_returns_the_fixture_or_null(db, monkeypatch):
    import api.routers.matches as matches_router

    app.dependency_overrides[get_store] = lambda: db
    try:
        client = TestClient(app)
        monkeypatch.setattr(matches_router, "missing_match", lambda session: missing_match(session, NOW))

        assert client.get("/matches/missing").json() is None

        db.add(_fixture(YESTERDAY, 16))
        db.flush()
        body = client.get("/matches/missing").json()
        assert body["day"] == "2026-09-19"
        assert body["title"] == "Spiel: Union Eidenberg/Geng - Treffling"
    finally:
        app.dependency_overrides.clear()


class _NoSession:
    def __enter__(self):
        return None

    def __exit__(self, *exc):
        return False


