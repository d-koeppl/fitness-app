"""api/jobs.py — what the hourly `jobs` function does (ADR-028).

One Cloud Scheduler job instead of fitness-dashboard's five APScheduler
jobs: the free tier allows three per billing account. It runs at half past
every hour, local time, and does:

- every hour: Google Health, then its heart-rate traces, then the calendar
  — the same three sources, in the same order, that POST /sync runs;
- at OEFB_SYNC_HOUR only: the ÖFB scrape, which looks back
  OEFB_SYNC_DAYS_BACK days so a night the site was down is caught up.

The 18:00 end-of-day fallback report joins this job in phase 5, with the
report code it runs.

Kept apart from main.py so the schedule logic is plain Python a test can
call with any clock.
"""

from __future__ import annotations

import logging
from datetime import datetime

from api.config import settings
from api.ingest.refresh import refresh_google_sources
from api.store.firestore import FirestoreStore

logger = logging.getLogger("api.jobs")

# Cron for Cloud Scheduler, in wake_fallback_tz (Europe/Vienna). Minute 30,
# as the old scheduler ran the ÖFB scrape at 03:30: late enough after the
# hour that Google has flushed the previous hour's data.
SCHEDULE = "30 * * * *"


def run_hourly(store: FirestoreStore, now: datetime) -> dict[str, str]:
    """One run. `now` is local time; returns what each source did."""
    results = refresh_google_sources(store)

    if now.hour == settings.oefb_sync_hour:
        from oefb.scraper import run as run_scraper

        try:
            stored = run_scraper(store, days=settings.oefb_sync_days_back)
            results["oefb"] = f"ok ({stored} new)"
        except Exception as exc:  # noqa: BLE001 — logged, and the Google results still count
            logger.exception("ÖFB scrape failed")
            results["oefb"] = f"failed: {exc}"

    logger.info("Hourly job at %s: %s", now.isoformat(timespec="minutes"), results)
    return results
