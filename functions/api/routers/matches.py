"""api/routers/matches.py — the ÖFB match log.

Populated by the scraper, which the scheduled job runs daily (ADR-004,
ADR-028). `/matches/missing` says when the calendar had a game yesterday
that the log does not (api/services/matches.py).
"""

from __future__ import annotations

from fastapi import APIRouter, Depends

from api.schemas.matches import MatchOut, MissingMatchOut
from api.services.matches import MissingMatch, missing_match, newest_first
from api.store.firestore import FirestoreStore, get_store
from api.store.rows import MatchPerformance

router = APIRouter(tags=["matches"])


@router.get("/matches", response_model=list[MatchOut])
def list_matches(store: FirestoreStore = Depends(get_store)) -> list[MatchPerformance]:
    """Newest first, undated rows before all of them."""
    return newest_first(store)


@router.get("/matches/missing", response_model=MissingMatchOut | None)
def missing_yesterday(store: FirestoreStore = Depends(get_store)) -> MissingMatch | None:
    """Yesterday's calendar fixture if the ÖFB log has no game that day,
    else null. The app shows it as a notice on the Today tab."""
    return missing_match(store)
