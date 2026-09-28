from __future__ import annotations

from datetime import date, datetime

from pydantic import BaseModel, ConfigDict

from api.schemas.matches import MatchOut


class DailyHealthOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    date: date
    steps: int | None
    resting_hr: int | None
    hrv_ms: float | None
    sleep_minutes: int | None
    # Summed Active Zone Minutes for the day — the training model's load
    # unit (see api/analysis/training_load.py). None means the watch tracked
    # no exercise session at all, which is not the same as one that scored 0.
    active_zone_minutes: int | None
    weight_kg: float | None
    vo2max: float | None


class MeasurementOut(BaseModel):
    """One reading of a metric that is not recorded every day, with the day
    it was taken. Mirrors api.services.health.Measurement."""

    model_config = ConfigDict(from_attributes=True)

    value: float
    date: date


class LatestMeasurementsOut(BaseModel):
    """The last known value of each sparse metric (ADR-018).

    Every field is optional and omitted when the metric has never been
    recorded — an absent key is "no reading ever", which is not the same as
    a reading of zero. The values here are deliberately not folded into
    `DailyHealthOut`: a daily row says what was measured *that day*, and a
    carried-forward weight in that shape would make the charts draw a flat
    line through days nobody stood on the scale.
    """

    weight_kg: MeasurementOut | None = None
    vo2max: MeasurementOut | None = None


class ExerciseSessionOut(BaseModel):
    """One session behind a day's load — mirrors
    api.services.exercises.ExerciseSession.

    `metrics` is an open bag of whatever else Google recorded for the
    session, keyed by its own camelCase field name. It is untyped on
    purpose: the set varies by activity type and by what the Health API has
    shipped, and pinning it down here would mean a schema change every time
    the watch learns a new number. The four fields above it are the ones
    confirmed live and used for display — see the service module.
    """

    model_config = ConfigDict(from_attributes=True)

    id: str
    date: date
    start_ts: datetime | None
    end_ts: datetime | None
    exercise_type: str | None
    duration_minutes: float | None
    active_zone_minutes: float | None
    average_heart_rate: float | None
    metrics: dict[str, float]

    # "tracked" | "match" | "training". The last two are sessions the watch
    # never recorded, whose load the model estimated from the schedule
    # instead (ADR-014): `estimated_load` carries that estimate, and
    # `active_zone_minutes` stays null because nothing measured it.
    source: str
    # The key to send back to POST /training/skips. Null when tracked.
    ref_id: str | None
    # What to call the session when there is no exercise type — the
    # opponent, or the calendar block's title.
    title: str | None
    estimated_load: float | None
    # The user marked it as not done. The model has already stopped
    # counting it; `estimated_load` still says what it would have been.
    skipped: bool
    # The ÖFB match this session was — result, minutes played, goals — when
    # it covered a kick-off, or is the estimate for a match the watch missed.
    match: MatchOut | None


class HeartRateZoneOut(BaseModel):
    """One heart rate zone over a session: where it starts, and how long was
    spent in it.

    `lower_bpm` is null only for the lowest zone and `upper_bpm` only for the
    highest — they are the ends of the scale, not missing values. The bounds
    are derived (the API publishes minutes per zone but not the boundaries
    between them); `SessionHeartRateOut.zone_source` says where the seconds
    came from.
    """

    model_config = ConfigDict(from_attributes=True)

    # "light" | "fat_burn" | "cardio" | "peak", ascending.
    zone: str
    lower_bpm: int | None
    upper_bpm: int | None
    seconds: float


class SessionHeartRateOut(BaseModel):
    """One tracked session's heart rate trace — mirrors
    api.services.heart_rate.SessionHeartRate.

    `samples` is `[seconds_from_start, bpm]` pairs, thinned to what a
    phone-width chart can draw; `sample_count` is how many readings are
    stored behind them, so the client can say how much it is showing.

    Empty `samples` means two different things, told apart by `fetched_at`:
    with a timestamp, the watch recorded no heart rate for this session;
    without one, the sync has not reached it yet (ADR-020 fetches the newest
    sessions first, a bounded number per run).
    """

    model_config = ConfigDict(from_attributes=True)

    session_id: str
    date: date
    start_ts: datetime | None
    end_ts: datetime | None
    fetched_at: datetime | None
    samples: list[tuple[int, int]]
    sample_count: int
    min_bpm: int | None
    max_bpm: int | None
    average_bpm: float | None
    zones: list[HeartRateZoneOut]
    # "google" — Google's own time-in-zone for this session, the numbers the
    # Google Health app shows — or "derived", counted off the samples here.
    # Null when no zones could be worked out at all.
    zone_source: str | None
    # What the boundaries were derived from, so the UI can explain them.
    resting_hr: int | None
    max_hr: int | None
