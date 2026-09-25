"""api/routers/sync.py — pull the Google sources now, from the app's sync
chip (ADR-026) and the first half of New report (ADR-027)."""

from __future__ import annotations

from fastapi import APIRouter, Depends

from api.ingest.refresh import refresh_google_sources
from api.schemas.sync import SyncOut
from api.store.firestore import FirestoreStore, get_store

router = APIRouter(prefix="/sync", tags=["sync"])


@router.post("", response_model=SyncOut)
def sync_now(store: FirestoreStore = Depends(get_store)) -> SyncOut:
    """Google Health, heart rate and the calendar, once, synchronously — the
    caller is watching a spinner. Not the ÖFB scrape: that stays nightly.

    No Gemini call and no report, so no budget to check. A dead source does
    not fail the request; it comes back as "failed: …" in `sources`, and the
    app still re-reads whatever did land."""
    return SyncOut(sources=refresh_google_sources(store))
