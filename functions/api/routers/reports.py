"""api/routers/reports.py — the latest AI report.

Only the read side so far. Generating a report needs the Gemini client
and the sync, which move over in phases 3 and 5 (ADR-027's
sync-then-generate button is what calls them).
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException

from api.schemas.reports import AiReportOut
from api.services.reports import latest_report
from api.store.firestore import FirestoreStore, get_store
from api.store.rows import AiReport

router = APIRouter(prefix="/reports", tags=["reports"])


@router.get("/latest", response_model=AiReportOut)
def get_latest_report(store: FirestoreStore = Depends(get_store)) -> AiReport:
    report = latest_report(store)
    if report is None:
        raise HTTPException(status_code=404, detail="No reports yet")
    return report
