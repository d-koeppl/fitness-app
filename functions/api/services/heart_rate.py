"""api/services/heart_rate.py — one session's trace, ready to draw.

The read side of ADR-020. The sync (api/ingest/heart_rate.py) stores every
sample it was given; this module turns one stored row into the answer the
detail sheet asks for: a chart-sized trace, the bpm the zones start at, and
how long was spent in each of them.

It is the only place that decides *which* time-in-zone answer is shown.
Google's own is used wherever the sync managed to store it, because those
are the numbers the Google Health app shows and a dashboard disagreeing
with the phone in the user's other hand is a bug report waiting to happen.
Only when it is missing are the minutes counted off the samples here,
against the derived boundaries — and the answer says which of the two it
is (`zone_source`), so a number that came from our own arithmetic is never
presented as Google's.

The zone *boundaries* are always ours: the API does not publish them (see
api/analysis/heart_rate.py). They need a resting HR, which is measured and
comes from the daily rows, and a max HR — the highest the watch has ever
recorded (ADR-039), or a configured one if that is higher. Without either
there are no bands, no zone times and no colouring — the sheet then shows
the plain trace, which is still every reading the watch took.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date as date_type
from datetime import datetime

from api.analysis.heart_rate import (
    LIGHT,
    ZONE_FROM_GOOGLE,
    ZONE_ORDER,
    Sample,
    ZoneBand,
    covered_seconds,
    downsample,
    summarize,
    time_in_zones,
    zone_bands,
)
from api.config import settings
from api.integrations.google_health import EXERCISE_DATA_TYPE
from api.services.sessions import ExerciseSession, sessions_for_day
from api.store.firestore import FirestoreStore
from api.store.rows import ExerciseHeartRate

# What `zone_source` can say. "google" is `time-in-heart-rate-zone` as
# stored; "derived" is this module counting the samples itself.
GOOGLE = "google"
DERIVED = "derived"


@dataclass
class ZoneTime:
    zone: str
    lower_bpm: int | None
    upper_bpm: int | None
    seconds: float


@dataclass
class SessionHeartRate:
    """Everything the session chart draws.

    `samples` is `(seconds_from_start, bpm)`, thinned to what a phone-width
    chart can show; `sample_count` is how many readings are actually stored
    behind it, so the sheet can say "1 of every 8" rather than implying the
    watch sampled this coarsely.

    An empty `samples` with a `fetched_at` set is a real answer — the watch
    recorded no heart rate for this session. An empty one with `fetched_at`
    null means the sync has not reached this session yet, which the sheet
    words differently.
    """

    session_id: str
    date: date_type
    start_ts: datetime | None
    end_ts: datetime | None
    fetched_at: datetime | None
    samples: list[Sample]
    sample_count: int
    min_bpm: int | None = None
    max_bpm: int | None = None
    average_bpm: float | None = None
    # The zones in ascending order, with the bpm each starts at. Empty when
    # no max HR is configured.
    zones: list[ZoneTime] = field(default_factory=list)
    zone_source: str | None = None
    # What the bands were derived from, so the sheet can explain them.
    resting_hr: int | None = None
    max_hr: int | None = None


def _find_session(store: FirestoreStore, session_id: str) -> ExerciseSession | None:
    """The tracked session an id names, or None.

    The id is `<date>#<index>` — the same one `services/sessions.py` assigns
    — so the day is read straight out of it and only that day's row is
    loaded. An id for a match or a training (`match#12345`) names a session
    no watch recorded, which by definition has no trace; it does not parse
    here and the caller answers 404.
    """
    day, _, index = session_id.partition("#")
    if not index.isdigit():
        return None
    try:
        parsed_day = date_type.fromisoformat(day)
    except ValueError:
        return None

    row = store.health_day(parsed_day)
    if row is None:
        return None
    for session in sessions_for_day(parsed_day, (row.raw or {}).get(EXERCISE_DATA_TYPE)):
        if session.id == session_id:
            return session
    return None


def _resting_hr(store: FirestoreStore, day: date_type) -> int | None:
    """The resting HR the zones are measured from — that day's, or the most
    recent one before it.

    Carried forward for the same reason weight is (ADR-018): resting HR is
    an overnight measurement that a night off the wrist simply does not
    produce, and the boundaries move by about a beat for every beat of
    resting HR, so last week's is a far better answer than none.
    """
    return next(
        (row.resting_hr for row in store.health_days_desc(before=day) if row.resting_hr is not None),
        None,
    )


def _stored_samples(row: ExerciseHeartRate | None) -> list[Sample]:
    """The stored pairs, defensively: a hand-edited or half-written row must
    leave the chart empty, not raise on a page load."""
    if row is None or not isinstance(row.samples, list):
        return []
    samples: list[Sample] = []
    for pair in row.samples:
        if isinstance(pair, (list, tuple)) and len(pair) == 2:
            offset, bpm = pair
            if isinstance(offset, (int, float)) and isinstance(bpm, (int, float)):
                samples.append((int(offset), int(bpm)))
    return samples


def _zone_times(
    bands: list[ZoneBand], samples: list[Sample], google_seconds: dict
) -> tuple[list[ZoneTime], str | None]:
    """The four zone rows and where their seconds came from."""
    if not bands:
        return [], None

    from_google = {
        ZONE_FROM_GOOGLE[name]: float(value)
        for name, value in (google_seconds or {}).items()
        if name in ZONE_FROM_GOOGLE and isinstance(value, (int, float))
    }

    if from_google:
        # Google names only the three scoring zones. Everything else the
        # trace covered was below the first of them — the same subtraction
        # the Google Health app's own "light" bar is, and taken against the
        # time the samples actually cover so a dropout is not counted as
        # time spent taking it easy.
        seconds = dict(from_google)
        seconds[LIGHT] = max(0.0, covered_seconds(samples) - sum(from_google.values()))
        source = GOOGLE
    else:
        seconds = time_in_zones(samples, bands)
        if not seconds:
            return [], None
        source = DERIVED

    by_zone = {band.zone: band for band in bands}
    return [
        ZoneTime(
            zone=zone,
            lower_bpm=by_zone[zone].lower_bpm,
            upper_bpm=by_zone[zone].upper_bpm,
            seconds=round(seconds.get(zone, 0.0), 1),
        )
        for zone in ZONE_ORDER
        if zone in by_zone
    ], source


def max_heart_rate(store: FirestoreStore) -> int | None:
    """The max HR the zones are measured from, or None (ADR-039).

    The higher of the highest heart rate on record and the configured one.
    A recorded peak is a floor under the true maximum — the heart got at
    least that high — so a configured number or an age formula below it is
    simply out of date, and the zones follow the new peak without anyone
    editing a setting.
    """
    candidates = [bpm for bpm in (store.recorded_max_hr(), settings.max_heart_rate) if bpm]
    return max(candidates) if candidates else None


def session_heart_rate(
    store: FirestoreStore, session_id: str, max_points: int | None = None
) -> SessionHeartRate | None:
    """One tracked session's heart rate, or None if no such session exists.

    `max_points` is how many of the stored readings come back in `samples`;
    None means the chart's budget. It is a parameter rather than a constant
    because the two readers want different amounts of the same trace: the
    detail sheet wants what a phone can draw, and the coach's attached-workout
    payload (ADR-021) wants the readings the chart throws away. Everything
    else in the answer — the stats, the zone times — is computed from the
    full stored trace either way, so the two never disagree about how fast
    the heart was going, only about how many points say so.
    """
    session = _find_session(store, session_id)
    if session is None:
        return None

    row: ExerciseHeartRate | None = store.hr_trace(session.start_ts) if session.start_ts is not None else None
    samples = _stored_samples(row)

    resting_hr = _resting_hr(store, session.date)
    max_hr = max_heart_rate(store)
    bands = zone_bands(max_hr, resting_hr)
    zones, zone_source = _zone_times(bands, samples, row.zone_seconds if row else {})
    stats = summarize(samples)

    return SessionHeartRate(
        session_id=session.id,
        date=session.date,
        start_ts=session.start_ts,
        end_ts=session.end_ts,
        fetched_at=row.fetched_at if row else None,
        samples=downsample(samples, max_points or settings.health_hr_chart_points),
        sample_count=len(samples),
        min_bpm=stats.min_bpm if stats else None,
        max_bpm=stats.max_bpm if stats else None,
        average_bpm=stats.average_bpm if stats else None,
        zones=zones,
        zone_source=zone_source,
        resting_hr=resting_hr,
        max_hr=max_hr if bands else None,
    )
