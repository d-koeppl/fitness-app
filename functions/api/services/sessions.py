"""api/services/sessions.py — one tracked workout, read back out of `raw`.

There is no exercise table, and this needed no migration to add: the health
sync already writes every session's raw Google Health data point into
`daily_health.raw["exercise"]` (a list per day) and normalizes only the sum
of their Active Zone Minutes into a column, because that sum is all the
training model consumes (ADR-009). The per-session detail was therefore
being stored all along, just never read back. This module reads it.

It sits below both readers of it — `services/training.py`, which needs
each session's start time to decide whether it is the training that was
scheduled (ADR-015), and `services/exercises.py`, which lists them. It was
part of the latter until the model became session-aware; two readers and
one parser is the only arrangement that keeps the two from disagreeing
about what a session is, and keeps the imports a DAG.

Attribution is not re-derived here. A session belongs to the day whose row
holds it, which is the local-time attribution
`integrations/google_health.py` already made — deriving it a second time
from the timestamp would be a second chance to disagree with the daily
Active Zone Minutes the same session was counted into.

**Parsing is deliberately forgiving.** Confirmed live 2026-08-19 (the same
session that produced ADR-009): `exercise.exerciseType`,
`exercise.interval.{startTime,endTime}` and
`exercise.metricsSummary.{activeZoneMinutes,averageHeartRateBeatsPerMinute}`.
Those four get named fields. Everything *else* a session carries varies by
activity and by whatever Google has shipped this month, so rather than guess
field names it is passed through as a bag of numbers (`metrics`) for the UI
to label: a field that appears later shows up on its own, and one that
disappears leaves a gap instead of raising. See ADR-012.

That the bag is the right shape was confirmed the moment this went live
(2026-08-23, over real history): `metricsSummary` also carried `steps`,
`caloriesKcal`, `distanceMillimeters`, `averagePaceSecondsPerMeter` and —
on a swim only — `totalSwimLengths`. Two of those (millimetres, and a pace
in seconds per metre) are not units anyone would have guessed, and the
per-activity variation is real. A fixed column list would have shipped
wrong on day one.

Two absences are also real and must not be papered over: a session can
arrive with no `activeZoneMinutes` and no heart rate at all — the 2026-08-23
swim did — which is why both are nullable rather than defaulted to zero.
A third absence matters more since ADR-015: a session can arrive with no
usable `interval` either, and an unplaceable session is the one case
coverage cannot reason about — see `placed_start`.

The dataclass carries a few fields this module never fills: a listed
session can also *be* a match or a training the watch never recorded, which
`services/exercises.py` builds. They live on the same dataclass because the
dashboard shows them in one list.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import date as date_type
from datetime import datetime

from api.integrations.google_health import EXERCISE_DATA_TYPE, as_number
from api.store.rows import MatchPerformance

# Lifted out of `metrics` into named fields of their own: these two are the
# ones the list rows and the summary line are built from, so the frontend
# should not have to know Google's spelling of them.
AZM_FIELD = "activeZoneMinutes"
HEART_RATE_FIELD = "averageHeartRateBeatsPerMinute"

# `source` on a listed session: recorded by the watch, or estimated from
# the schedule. The other two names are the ones a skip is filed under and
# the ones the model counts under, so they come from there rather than
# being spelled a third time here.
TRACKED = "tracked"


@dataclass
class ExerciseSession:
    """One session behind a day's load, as the dashboard shows it.

    Usually a tracked workout. It can also be a match or a training block
    the watch never recorded, in which case the numbers come from the
    schedule and the model's fallback rate instead — see the module
    docstring, and the fields below the metrics bag.
    """

    id: str
    date: date_type
    start_ts: datetime | None
    end_ts: datetime | None
    exercise_type: str | None
    duration_minutes: float | None
    active_zone_minutes: float | None
    average_heart_rate: float | None
    # Every other numeric field Google recorded for the session, under its
    # own camelCase name. Deliberately untyped — see the module docstring.
    metrics: dict[str, float] = field(default_factory=dict)

    # --- where this row came from ---------------------------------------
    # TRACKED, MATCH or TRAINING. Everything below is null/false on a
    # tracked session, and it is the only kind that has real AZM.
    source: str = TRACKED
    # The natural key a skip is filed under (oefb_game_id / Google event
    # id). None when tracked: there is nothing to skip, the session
    # happened.
    ref_id: str | None = None
    # What to call it when there is no exercise type to prettify —
    # "vs Treffling", or the calendar block's own title.
    title: str | None = None
    # The load the model credits this session with, in AZM, when the day
    # holds no tracked session. Separate from active_zone_minutes on
    # purpose: that field means "the watch measured this", and this one
    # means "nobody measured it, so it was estimated from minutes".
    estimated_load: float | None = None
    # Marked as not-done by the user. The estimate above is what it *would*
    # have contributed and is deliberately still reported — the model has
    # already stopped counting it, and a struck-through number says more
    # about a skipped session than a zero does.
    skipped: bool = False
    # The ÖFB match this session was, when it was one: the tracked workout
    # the watch recorded through kick-off, or the estimated row for a match
    # it missed. Attached by `services/exercises.py`, which is the layer
    # that has the schedule to decide it from.
    match: MatchPerformance | None = None


def _timestamp(interval: dict, key: str) -> datetime | None:
    stamp = interval.get(key)
    if not isinstance(stamp, str):
        return None
    try:
        return datetime.fromisoformat(stamp)
    except ValueError:
        return None


def _duration_minutes(start: datetime | None, end: datetime | None) -> float | None:
    if start is None or end is None:
        return None
    minutes = (end - start).total_seconds() / 60
    # A negative or absurd span means the interval is not what we think it
    # is; report nothing rather than a wrong number on the card.
    return round(minutes, 1) if 0 <= minutes <= 24 * 60 else None


def _metrics_bag(summary: dict) -> dict[str, float]:
    """The numeric leftovers of `metricsSummary`, minus what got promoted.

    Only scalar numbers survive: a nested object (zone breakdowns, say) has
    no obvious one-line rendering, and the raw payload is still in the
    database for whoever wants to add one deliberately.
    """
    bag: dict[str, float] = {}
    for name, raw in summary.items():
        if name in (AZM_FIELD, HEART_RATE_FIELD):
            continue
        value = as_number(raw)
        if value is not None:
            bag[name] = value
    return bag


def sessions_for_day(day: date_type, points: object) -> list[ExerciseSession]:
    """The sessions stored on one `daily_health.raw["exercise"]` list.

    Ordered by start time, and identified by their position in *that* order
    rather than in storage order: a re-sync rewrites `raw` and Google's
    paging does not promise to hand the same day back in the same sequence,
    so a storage-order id would change under a row that had not.
    """
    if not isinstance(points, list):
        return []

    sessions: list[ExerciseSession] = []
    for point in points:
        if not isinstance(point, dict):
            continue
        exercise = point.get(EXERCISE_DATA_TYPE)
        if not isinstance(exercise, dict):
            continue

        interval = exercise.get("interval") or {}
        summary = exercise.get("metricsSummary") or {}
        start = _timestamp(interval, "startTime")
        end = _timestamp(interval, "endTime")
        exercise_type = exercise.get("exerciseType")

        sessions.append(
            ExerciseSession(
                id="",  # assigned below, once the day's sessions are ordered
                date=day,
                start_ts=start,
                end_ts=end,
                exercise_type=str(exercise_type) if exercise_type is not None else None,
                duration_minutes=_duration_minutes(start, end),
                active_zone_minutes=as_number(summary.get(AZM_FIELD)),
                average_heart_rate=as_number(summary.get(HEART_RATE_FIELD)),
                metrics=_metrics_bag(summary),
            )
        )

    # Sessions with no start time sort last, in the order they were stored —
    # there is nothing better to order them by.
    sessions.sort(key=lambda s: (s.start_ts is None, s.start_ts.timestamp() if s.start_ts else 0.0))
    for index, session in enumerate(sessions):
        session.id = f"{day.isoformat()}#{index}"
    return sessions


def placed_start(session: ExerciseSession) -> datetime | None:
    """The session's start, if it can be compared to a scheduled time.

    A session with no `interval`, or with a timestamp that carried no UTC
    offset, cannot be placed against anything — and the coverage rule
    (analysis/training_load.covers) is entirely about where a session sits
    in the day. Callers treat an unplaceable session as covering its whole
    day, which is the conservative reading: it might have been the
    training, and inventing a second helping of load on top of one that was
    already measured is the worse of the two mistakes.
    """
    if session.start_ts is None or session.start_ts.tzinfo is None:
        return None
    return session.start_ts
