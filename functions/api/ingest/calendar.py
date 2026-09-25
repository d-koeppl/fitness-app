"""api/ingest/calendar.py — Google Calendar sync into calendar_events.

Read-only: fetches upcoming (and recently past) events for each configured
calendar (GOOGLE_CALENDAR_IDS — the primary calendar plus a subscribed team
calendar) and upserts them. Run hourly by the `jobs` function (ADR-028).
Carried over from fitness-dashboard with the writes going through the
store, which also moves an event whose start changed month (ADR-031).
"""

from __future__ import annotations

import logging
from datetime import UTC, datetime, timedelta

import requests

from api.config import settings
from api.integrations.google_oauth import get_valid_access_token
from api.store.firestore import FirestoreStore
from api.store.rows import CalendarEvent

logger = logging.getLogger("api.ingest.calendar")

EVENTS_URL_TEMPLATE = "https://www.googleapis.com/calendar/v3/calendars/{calendar_id}/events"

DAYS_BACK = 3
DAYS_AHEAD = 30


def _parse_when(value: dict) -> tuple[datetime | None, bool]:
    """Google returns {"dateTime": ...} for timed events or {"date": ...}
    (no time component) for all-day events."""
    if "dateTime" in value:
        return datetime.fromisoformat(value["dateTime"]), False
    if "date" in value:
        return datetime.fromisoformat(value["date"]).replace(tzinfo=UTC), True
    return None, False


def fetch_events(calendar_id: str) -> list[dict]:
    access_token = get_valid_access_token("calendar")
    now = datetime.now(UTC)

    resp = requests.get(
        EVENTS_URL_TEMPLATE.format(calendar_id=calendar_id),
        headers={"Authorization": f"Bearer {access_token}"},
        params={
            "timeMin": (now - timedelta(days=DAYS_BACK)).isoformat(),
            "timeMax": (now + timedelta(days=DAYS_AHEAD)).isoformat(),
            "singleEvents": "true",
            "orderBy": "startTime",
            "maxResults": 250,
        },
        timeout=20,
    )
    resp.raise_for_status()
    return resp.json().get("items", [])


def to_event(item: dict, calendar_id: str) -> CalendarEvent:
    start_ts, all_day = _parse_when(item.get("start", {}))
    end_ts, _ = _parse_when(item.get("end", {}))
    return CalendarEvent(
        id=item["id"],
        calendar_id=calendar_id,
        title=item.get("summary"),
        start_ts=start_ts,
        end_ts=end_ts,
        all_day=all_day,
        location=item.get("location"),
        raw=item,
    )


def sync_calendar_events(store: FirestoreStore, calendar_ids: list[str] | None = None) -> int:
    calendar_ids = calendar_ids if calendar_ids is not None else settings.calendar_ids

    events: list[CalendarEvent] = []
    for calendar_id in calendar_ids:
        items = fetch_events(calendar_id)
        logger.info("Fetched %d calendar event(s) for %s", len(items), calendar_id)
        # A cancelled event is skipped, not deleted — as before: the old
        # stack never deleted events either, and the training model only
        # reads events whose titles it recognises.
        events.extend(to_event(item, calendar_id) for item in items if item.get("status") != "cancelled")

    for start in range(0, len(events), 100):
        store.put_calendar_events(events[start : start + 100])
    logger.info("Synced %d calendar event(s)", len(events))
    return len(events)
