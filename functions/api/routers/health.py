"""api/routers/health.py — read-only daily health metrics for the app.

Five shapes of the same sync: `/daily` is the one-row-per-day summary the
charts plot, `/exercises` the individual sessions behind it,
`/exercises/{id}` one of them by id, `/exercises/{id}/heart-rate` its
beat-by-beat trace (ADR-020), and `/latest` the last known value of the metrics that are not recorded daily.
Pulling the sessions out of the stored payloads is real assembly work, so it
lives in api/services/exercises.py and api/services/heart_rate.py rather
than here.
"""

from __future__ import annotations

from itertools import islice

from fastapi import APIRouter, Depends, HTTPException

from api.schemas.health import (
    DailyHealthOut,
    ExerciseSessionOut,
    LatestMeasurementsOut,
    MeasurementOut,
    SessionHeartRateOut,
)
from api.services.exercises import DEFAULT_LIMIT, find_session, list_exercise_sessions
from api.services.health import latest_measurements
from api.services.heart_rate import session_heart_rate
from api.store.firestore import FirestoreStore, get_store
from api.store.rows import DailyHealth

router = APIRouter(prefix="/health-data", tags=["health"])


@router.get("/daily", response_model=list[DailyHealthOut])
def list_daily_health(limit: int = 30, store: FirestoreStore = Depends(get_store)) -> list[DailyHealth]:
    """The newest `limit` stored days, newest first. Read a month at a time
    from the newest, so a year of history costs about a dozen reads."""
    if limit <= 0:
        return []
    return list(islice(store.health_days_desc(), limit))


@router.get("/exercises", response_model=list[ExerciseSessionOut])
def list_exercises(
    limit: int = DEFAULT_LIMIT, store: FirestoreStore = Depends(get_store)
) -> list[ExerciseSessionOut]:
    """The most recently tracked workouts, newest first."""
    return [ExerciseSessionOut.model_validate(s) for s in list_exercise_sessions(store, limit)]


@router.get("/exercises/{session_id}", response_model=ExerciseSessionOut)
def get_exercise(session_id: str, store: FirestoreStore = Depends(get_store)) -> ExerciseSessionOut:
    """One session by id, however old — what a match in the ÖFB log opens
    through its `session_id`, which can name a session long past the end of
    `/exercises`. 404 when the id names nothing."""
    session = find_session(store, session_id)
    if session is None:
        raise HTTPException(status_code=404, detail="No session with that id")
    return ExerciseSessionOut.model_validate(session)


@router.get("/exercises/{session_id}/heart-rate", response_model=SessionHeartRateOut)
def exercise_heart_rate(session_id: str, store: FirestoreStore = Depends(get_store)) -> SessionHeartRateOut:
    """One tracked session's heart rate trace (ADR-020).

    Its own request rather than a field on `/exercises`: a trace is a few
    hundred points even after thinning, and the list renders ten sessions
    that would each be carrying one nobody has opened. The detail sheet
    fetches this when it opens.

    404 is "no such session" — a bad id, or one naming a match or training
    the watch never recorded. A session that exists but has no readings
    answers 200 with an empty `samples`, which is a different thing and the
    sheet says so.
    """
    result = session_heart_rate(store, session_id)
    if result is None:
        raise HTTPException(status_code=404, detail="No tracked session with that id")
    return SessionHeartRateOut.model_validate(result)


@router.get("/latest", response_model=LatestMeasurementsOut)
def latest_health_measurements(store: FirestoreStore = Depends(get_store)) -> LatestMeasurementsOut:
    """The current weight and VO2 max, whichever day they were last measured
    on (ADR-018). Separate from `/daily` because it deliberately reaches past
    the window `/daily` was asked for: the last weigh-in can be older than
    any range the app shows, and it is still the current weight."""
    return LatestMeasurementsOut(
        **{name: MeasurementOut.model_validate(m) for name, m in latest_measurements(store).items()}
    )
