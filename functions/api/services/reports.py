"""api/services/reports.py — queries over ai_reports.

`latest_report` is shared by /reports/latest and the wake webhook's
debounce check, which used to hold the same query twice.

`report_exists_today` is the other shared question — "has this local day
had a report yet" — asked by the end-of-day fallback (to skip a run the
day is already covered for) and by the beer counter (whose reset is
exactly the *first* report of a day, ADR-019). One definition of the day
boundary, so the two cannot disagree about which report was the first.
"""

from __future__ import annotations

from datetime import datetime
from zoneinfo import ZoneInfo

from api.config import settings
from api.store.firestore import FirestoreStore
from api.store.rows import AiReport


def latest_report(store: FirestoreStore) -> AiReport | None:
    return store.latest_report()


def report_created_since(store: FirestoreStore, cutoff: datetime) -> bool:
    """True if any report was created at or after `cutoff`. The end-of-day
    fallback uses it with local midnight to skip a run the day already has
    a report for — the calendar day, not a rolling window, is what "did I
    already get one today" means."""
    return store.report_created_since(cutoff)


def local_day_start(now: datetime | None = None) -> datetime:
    """Midnight of the current local day, in `wake_fallback_tz` — the zone
    the fallback is scheduled in, and so the one the user means by "today"."""
    tz = ZoneInfo(settings.wake_fallback_tz)
    return (now or datetime.now(tz)).astimezone(tz).replace(
        hour=0, minute=0, second=0, microsecond=0
    )


def report_exists_today(store: FirestoreStore) -> bool:
    """Whether the current local day already has a report, from any trigger."""
    return report_created_since(store, local_day_start())
