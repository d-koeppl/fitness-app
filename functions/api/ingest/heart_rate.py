"""api/ingest/heart_rate.py — pull each tracked session's heart rate trace.

Carried over from fitness-dashboard (ADR-020) with its reads and writes
going through the store. Runs after the daily health sync, and reads what
that sync wrote: the sessions come out of `daily_health.raw["exercise"]`
(via services/sessions.py, the one parser), and each one's `interval` is
the window this asks Google for. Intraday heart rate is a sample type — one
reading every few seconds — so it is fetched per session rather than per
day, and only for sessions that do not have a trace yet.

Three rules keep the request count sane and the data honest:

**Bounded per run.** `HEALTH_HR_SESSIONS_PER_SYNC` sessions at most, newest
first. A first run against 30 days of history, or a manual backfill, then
fills in over the next few hourly syncs instead of firing hundreds of
requests at once — and the newest session, which is the one someone is
about to open, is always the first one fetched.

**An empty trace is an answer.** A session that comes back with no samples
(the watch was not worn, or the activity did not record heart rate) is
stored as an empty trace, so it is not re-fetched every hour forever. A
fetch that *failed* stores nothing and is retried on the next run: "no
readings" and "we could not ask" must not look the same in storage.

**Fetched too early is re-fetched.** A sync that lands mid-session, or
before Google has finished backfilling one, stores a short trace that would
otherwise stand forever. A trace is treated as settled only once it was
fetched a few hours after the session ended; until then it is eligible to
be replaced, which costs at most one extra fetch per session.

Each stored trace also feeds the **recorded maximum heart rate** the zone
boundaries are measured from (ADR-039): a workout that goes higher than any
before it raises it, and the first run after the feature shipped seeds it
from every trace already stored.
"""

from __future__ import annotations

import logging
from datetime import date, datetime, timedelta

import requests

from api.analysis.heart_rate import sustained_peak
from api.config import settings
from api.integrations.google_health import (
    EXERCISE_DATA_TYPE,
    fetch_heart_rate_samples,
    fetch_time_in_zones,
    local_tz,
)
from api.services.sessions import ExerciseSession, placed_start, sessions_for_day
from api.store.firestore import FirestoreStore
from api.store.rows import ExerciseHeartRate

logger = logging.getLogger("api.ingest.heart_rate")

# How long after a session ends a stored trace is taken to be complete.
# Generous on purpose: the cost of being wrong the other way is a trace
# that is permanently missing its last hour.
SETTLE_HOURS = 6


def _tracked_sessions(store: FirestoreStore, since: date) -> list[ExerciseSession]:
    """Every tracked session from `since` onwards that can be asked about,
    newest first.

    A session with no start, no end, or a timestamp that carried no UTC
    offset is skipped rather than guessed at: it has no window to ask
    Google for. That is the same unplaceable session
    `services/sessions.py::placed_start` describes, and dropping it here
    also keeps the sort below comparing like with like — a naive datetime
    beside an aware one does not compare at all.
    """
    sessions: list[ExerciseSession] = []
    for row in store.health_days(first=since):
        if EXERCISE_DATA_TYPE not in (row.raw or {}):
            continue
        for session in sessions_for_day(row.date, row.raw.get(EXERCISE_DATA_TYPE)):
            start, end = placed_start(session), session.end_ts
            if start and end and end.tzinfo and end > start:
                sessions.append(session)

    sessions.sort(key=lambda s: s.start_ts, reverse=True)
    return sessions


def _needs_fetch(session: ExerciseSession, stored: ExerciseHeartRate | None, now: datetime) -> bool:
    if stored is None:
        return True
    settled_at = session.end_ts + timedelta(hours=SETTLE_HOURS)
    # Stored before the session had settled, and the settle window has since
    # passed — worth exactly one more look. Both halves matter: without the
    # second, every hourly sync in between would re-fetch the same session.
    return stored.fetched_at < settled_at <= now


def _record_peak(store: FirestoreStore, row: ExerciseHeartRate) -> None:
    peak = sustained_peak([(offset, bpm) for offset, bpm in row.samples])
    if peak is not None and store.raise_recorded_max_hr(peak, row.session_start):
        logger.info("New highest heart rate on record: %d bpm (session at %s)", peak, row.session_start)


def _seed_recorded_max_hr(store: FirestoreStore) -> None:
    """Take the maximum from every trace ever stored, once.

    Runs whenever nothing is on record yet, which after the first trace
    with readings is never again. Until then it reads every stored trace,
    but those are few and all empty.
    """
    if store.recorded_max_hr() is not None:
        return
    peaks = [
        (peak, row.session_start)
        for row in store.hr_traces_since(date.min)
        if (peak := sustained_peak([(offset, bpm) for offset, bpm in row.samples])) is not None
    ]
    if peaks:
        peak, session_start = max(peaks, key=lambda p: p[0])
        store.raise_recorded_max_hr(peak, session_start)
        logger.info("Seeded the highest heart rate on record: %d bpm (session at %s)", peak, session_start)


def sync_exercise_heart_rate(store: FirestoreStore, days_back: int | None = None) -> int:
    """Fetch and store traces for recent sessions that do not have one.

    Returns the number of sessions stored this run.
    """
    days_back = settings.health_sync_days_back if days_back is None else days_back
    now = datetime.now(local_tz())
    since = now.date() - timedelta(days=days_back)

    _seed_recorded_max_hr(store)

    sessions = _tracked_sessions(store, since)
    stored = {row.session_start: row for row in store.hr_traces_since(since)}

    pending = [s for s in sessions if _needs_fetch(s, stored.get(s.start_ts), now)]
    if not pending:
        logger.info("No sessions need a heart rate trace")
        return 0

    budget = settings.health_hr_sessions_per_sync
    logger.info(
        "Fetching heart rate for %d of %d session(s) without a settled trace",
        min(budget, len(pending)),
        len(pending),
    )

    saved = 0
    for session in pending[:budget]:
        try:
            samples = fetch_heart_rate_samples(session.start_ts, session.end_ts)
        except requests.HTTPError as exc:
            # Nothing is written: a failed ask must stay distinguishable
            # from a session that genuinely recorded nothing.
            logger.warning("Heart rate fetch failed for session at %s: %s", session.start_ts, exc)
            continue

        zone_seconds: dict[str, float] = {}
        if samples:
            try:
                zone_seconds = fetch_time_in_zones(session.start_ts, session.end_ts)
            except requests.HTTPError as exc:
                # Strictly a nicety — the reader derives these from the
                # samples when they are missing — so it never costs the
                # trace that was just fetched.
                logger.info("Time-in-zone unavailable for session at %s: %s", session.start_ts, exc)

        row = ExerciseHeartRate(
            session_start=session.start_ts,
            date=session.date,
            session_end=session.end_ts,
            samples=[[int((when - session.start_ts).total_seconds()), bpm] for when, bpm in samples],
            zone_seconds=zone_seconds,
            fetched_at=datetime.now(local_tz()),
        )
        store.put_hr_trace(row)
        _record_peak(store, row)
        saved += 1

    logger.info("Stored heart rate traces for %d session(s)", saved)
    return saved
