"""api/jobs.py — what the hourly `jobs` function does (ADR-028).

One Cloud Scheduler job instead of fitness-dashboard's five APScheduler
jobs: the free tier allows three per billing account. It runs at half past
every hour, local time, and does:

- every hour: Google Health, then its heart-rate traces, then the calendar
  — the same three sources, in the same order, that POST /sync runs;
- at OEFB_SYNC_HOUR only: the ÖFB scrape, which looks back
  OEFB_SYNC_DAYS_BACK days so a night the site was down is caught up,
  then logs an ERROR if the calendar had a game yesterday that the ÖFB
  log still lacks (as fitness-dashboard's scheduler did);
- at WAKE_FALLBACK_HOUR only (18, so 18:30): the end-of-day fallback
  report, if nothing else made one today (ADR-004). It runs after the
  sync, so it reports on data at most a minute old — the old scheduler's
  18:00 job reported on whatever the last half-hourly sync had left.
- an hour later (19:30): the same again, which only does anything when
  18:30 left the day without a report — Gemini overloaded, typically — and
  may fall back to the second model once (ADR-034).

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
        _log_missing_match(store, now)

    last_try = now.hour == (settings.wake_fallback_hour + 1) % 24
    if now.hour == settings.wake_fallback_hour or last_try:
        from api.analysis.gemini import run_daily_fallback

        try:
            results["report"] = run_daily_fallback(store, last_try=last_try)
        except Exception as exc:  # noqa: BLE001 — logged; the sync above still counts
            logger.exception("Daily fallback report failed")
            results["report"] = f"failed: {exc}"

    logger.info("Hourly job at %s: %s", now.isoformat(timespec="minutes"), results)
    return results


def _log_missing_match(store: FirestoreStore, now: datetime) -> None:
    """After the scrape, whether it got yesterday's game — as the old
    scheduler did.

    The scraper logs and returns on a failed fetch rather than raising, so
    a dead ÖFB page looks like a quiet night. The calendar knows better: if
    it had a fixture yesterday and the log still has no game that day, say
    so at ERROR. Runs even when the scrape raised."""
    from api.services.matches import missing_match

    try:
        missing = missing_match(store, now)
    except Exception:  # noqa: BLE001 — a failed check must not fail the job
        logger.exception("Could not check the ÖFB log for yesterday's game")
        return
    if missing is not None:
        logger.error(
            "ÖFB scrape has no data for yesterday's game %r (%s, kick-off %s): the scrape "
            "failed, the report isn't online yet, you weren't in the squad, or it was called off",
            missing.title,
            missing.day,
            missing.kickoff.isoformat(),
        )
