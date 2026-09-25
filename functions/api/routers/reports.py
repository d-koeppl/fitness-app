"""api/routers/reports.py — the latest AI report, and New report."""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException
from requests import HTTPError

from api.analysis.gemini import run_analysis
from api.ingest.refresh import refresh_google_sources
from api.schemas.reports import AiReportOut, RefreshReportOut
from api.services import gemini_usage
from api.services.gemini_usage import GeminiQuotaExceeded
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


def _analyse(store: FirestoreStore, trigger: str) -> AiReport:
    """run_analysis, with its failures turned into the status the app shows."""
    try:
        return run_analysis(store, trigger)
    except GeminiQuotaExceeded as exc:
        # Before the RuntimeError branch below — this one is a subclass, and
        # "the day's budget is gone" is a 429, not a server fault.
        raise HTTPException(status_code=429, detail=str(exc)) from exc
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc
    except HTTPError as exc:
        raise HTTPException(status_code=502, detail=f"Gemini request failed: {exc}") from exc


@router.post("/generate", response_model=AiReportOut)
def generate_report(store: FirestoreStore = Depends(get_store)) -> AiReport:
    """A report on the data already stored, with no sync of its own. The
    app's **New report** calls POST /sync first, as a separate request, so
    the button can show "Syncing…" and then "Analyzing…" (ADR-027).
    Synchronous (the caller is already watching a loading state) and not
    debounced — a deliberate tap always gets a fresh analysis. No push
    either: the user is already looking at the screen that shows it.

    Undebounced does not mean unbounded: every tap spends one of the day's
    Gemini requests, and run_analysis refuses once they are gone (ADR-013)."""
    return _analyse(store, "manual")


@router.post("/refresh", response_model=RefreshReportOut)
def refresh_and_generate(store: FirestoreStore = Depends(get_store)) -> RefreshReportOut:
    """Sync, then report, in one request — for curl and scripts (ADR-016).
    The app makes the same two steps as two requests, /sync then
    /generate, so it can show which it is waiting on (ADR-027).

    The Gemini budget is checked *before* the pull so a spent day fails in
    a second instead of after a minute of network work. A dead single
    source doesn't abort — it comes back in `sources` as "failed:…" and the
    report still runs on whatever else refreshed."""
    try:
        gemini_usage.require_report_budget(store)
    except GeminiQuotaExceeded as exc:
        raise HTTPException(status_code=429, detail=str(exc)) from exc

    sources = refresh_google_sources(store)
    report = _analyse(store, "manual_refresh")
    return RefreshReportOut(sources=sources, report=AiReportOut.model_validate(report))
