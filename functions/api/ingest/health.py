"""api/ingest/health.py — sync Google Health API daily rollups into daily_health.

Carried over from fitness-dashboard with the rows read and written through
the store (ADR-031). See api/integrations/google_health.py for the caveat:
per-metric field parsing is best-effort until verified against a live
response.
"""

from __future__ import annotations

import logging

from api.integrations.google_health import fetch_all_daily_metrics
from api.store.firestore import FirestoreStore
from api.store.rows import DailyHealth

logger = logging.getLogger("api.ingest.health")

# Every extractor in integrations/google_health.py returns a float (Google
# serializes int64 fields as JSON strings, so as_number coerces everything
# through float). These columns are integers, so round explicitly rather
# than storing 9000.0 where every reader expects 9000.
_INT_COLUMNS = frozenset({"steps", "resting_hr", "sleep_minutes", "active_zone_minutes"})
_FLOAT_COLUMNS = frozenset({"hrv_ms", "weight_kg", "vo2max"})
_SYNCED_COLUMNS = _INT_COLUMNS | _FLOAT_COLUMNS


def sync_daily_health(store: FirestoreStore) -> int:
    by_date = fetch_all_daily_metrics()
    logger.info("Fetched Google Health data for %d day(s)", len(by_date))
    if not by_date:
        return 0

    # One read of the months the pull covers, then one write per month —
    # rather than a read and a write per day.
    existing = {row.date: row for row in store.health_days(min(by_date), max(by_date))}
    rows: list[DailyHealth] = []
    for day, values in by_date.items():
        row = existing.get(day) or DailyHealth(date=day)
        for column in _SYNCED_COLUMNS:
            if column not in values:
                continue
            value = values[column]
            if value is not None and column in _INT_COLUMNS:
                value = round(value)
            setattr(row, column, value)
        # Merged, not replaced: a data type that failed this run keeps what
        # an earlier run stored for the day.
        row.raw = {**(row.raw or {}), **values["raw"]}
        row.source = "google_health"
        row.updated_at = None  # the store stamps it
        rows.append(row)

    store.put_health_days(rows)
    logger.info("Synced daily_health for %d day(s)", len(rows))
    return len(rows)
