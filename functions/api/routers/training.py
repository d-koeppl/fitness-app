"""api/routers/training.py — Fitness / Fatigue / Form for the dashboard.

The DayInput assembly lives in api/services/training.py because the coach
endpoint needs the same numbers; the maths itself is in
api/analysis/training_load.py.

`/skips` is here rather than under `/health-data` even though the sessions
it names are listed there: what a skip changes is the training status, not
the health sync, and nothing about it reaches Google.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException

from api.schemas.training import SkipIn, SkipOut, TrainingStatusOut
from api.services.skips import activity_exists, set_skipped
from api.services.training import DEFAULT_HISTORY_DAYS, get_training_status
from api.store.firestore import FirestoreStore, get_store

router = APIRouter(prefix="/training", tags=["training"])


@router.get("/status", response_model=TrainingStatusOut)
def training_status(
    days: int = DEFAULT_HISTORY_DAYS, store: FirestoreStore = Depends(get_store)
) -> TrainingStatusOut:
    return TrainingStatusOut.model_validate(get_training_status(store, days))


@router.post("/skips", response_model=SkipOut)
def set_skip(body: SkipIn, store: FirestoreStore = Depends(get_store)) -> SkipOut:
    """Mark a scheduled match or training as missed, or undo that.

    Only untracked days are affected in the first place — a day the watch
    recorded is scored on what it recorded, and a skip there changes
    nothing (see api/services/exercises.py). The 404 is what stops a stale
    id becoming a row that silently matches nothing for ever.
    """
    if not activity_exists(store, body.source, body.ref_id):
        raise HTTPException(status_code=404, detail=f"No {body.source} with id {body.ref_id!r}")
    set_skipped(store, body.source, body.ref_id, body.skipped)
    return SkipOut(source=body.source, ref_id=body.ref_id, skipped=body.skipped)
