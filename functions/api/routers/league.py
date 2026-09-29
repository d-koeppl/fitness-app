"""api/routers/league.py — the league table and the games still to play.

Both come from the nightly ÖFB scrape (oefb/scraper.py); the comparison of
an opponent with us is api/services/league.py.
"""

from __future__ import annotations

from datetime import UTC, datetime

from fastapi import APIRouter, Depends

from api.schemas.league import FixtureOut, LeagueTableOut
from api.services.league import UpcomingFixture, upcoming_fixtures
from api.store.firestore import FirestoreStore, get_store
from api.store.rows import LeagueTable

router = APIRouter(tags=["league"])


@router.get("/league/table", response_model=LeagueTableOut | None)
def get_league_table(store: FirestoreStore = Depends(get_store)) -> LeagueTable | None:
    """The newest scraped table, or null before the first scrape."""
    return store.league_table()


@router.get("/league/fixtures", response_model=list[FixtureOut])
def list_fixtures(store: FirestoreStore = Depends(get_store)) -> list[UpcomingFixture]:
    """The games still to play, soonest first, each with the opponent's
    standing in the current table."""
    return upcoming_fixtures(store, datetime.now(UTC))
