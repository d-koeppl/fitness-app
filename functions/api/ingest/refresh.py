"""api/ingest/refresh.py — the data sources, callable one at a time or on demand.

The hourly `jobs` function (api/jobs.py) runs these on a schedule; this
module is the one place that knows the full set, so it can also run the
Google ones *now* — for `POST /sync`, which the app's sync chip (ADR-026)
and its **New report** button (ADR-027) call. The ÖFB scrape is the one
source no button runs: it is the slow one, and the nightly scrape covers a
schedule that changes weekly.

Each source is isolated: one failure is logged and collected into the
returned map, not raised. A revoked calendar grant must not stop the Google
Health pull that the daily report actually waits on.
"""

from __future__ import annotations

import logging
import time
from collections.abc import Callable

from api.store.firestore import FirestoreStore

logger = logging.getLogger("api.ingest.refresh")


def sync_calendar(store: FirestoreStore) -> None:
    from api.ingest.calendar import sync_calendar_events

    sync_calendar_events(store)


def sync_health(store: FirestoreStore) -> None:
    from api.ingest.health import sync_daily_health

    sync_daily_health(store)


def sync_heart_rate(store: FirestoreStore) -> None:
    from api.ingest.heart_rate import sync_exercise_heart_rate

    sync_exercise_heart_rate(store)


# The order the buttons run them in. Health first: it is the source the
# report most depends on (sleep lands late), so it should get its network
# round-trip in before anything else can fail. Heart rate second, not
# first: it reads the exercise sessions the health sync has just written.
# The ÖFB scrape is not in here (ADR-027): it took most of the button's
# wait, and match results change once a week.
_GOOGLE_SOURCES: tuple[tuple[str, Callable[[FirestoreStore], None]], ...] = (
    ("health", sync_health),
    ("heart_rate", sync_heart_rate),
    ("calendar", sync_calendar),
)


def refresh_google_sources(store: FirestoreStore) -> dict[str, str]:
    """Pull Google Health, its heart rate traces and the calendar once,
    synchronously. Returns {source: "ok"} or {source: "failed: <reason>"} —
    never raises for a single dead source.

    Logs how long each source took and the total: this is the "Syncing…"
    half of New report (ADR-027), and the line to read when it feels slow."""
    results: dict[str, str] = {}
    timings: list[str] = []
    started = time.perf_counter()
    for label, fn in _GOOGLE_SOURCES:
        source_started = time.perf_counter()
        try:
            fn(store)
            results[label] = "ok"
        except Exception as exc:  # noqa: BLE001 — one bad source must not sink the rest
            logger.exception("%s refresh failed", label)
            results[label] = f"failed: {exc}"
        timings.append(f"{label} {time.perf_counter() - source_started:.1f}s")
    logger.info("Google sync took %.1fs (%s)", time.perf_counter() - started, ", ".join(timings))
    return results
