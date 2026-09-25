"""api/routers/calendar.py — read-only calendar event listing for the app."""

from __future__ import annotations

from datetime import UTC, datetime

from fastapi import APIRouter, Depends

from api.schemas.calendar import CalendarEventOut
from api.store.firestore import FirestoreStore, get_store
from api.store.rows import CalendarEvent

router = APIRouter(prefix="/calendar", tags=["calendar"])


@router.get("/events", response_model=list[CalendarEventOut])
def list_upcoming_events(limit: int = 20, store: FirestoreStore = Depends(get_store)) -> list[CalendarEvent]:
    return store.calendar_events_from(datetime.now(UTC), limit)
