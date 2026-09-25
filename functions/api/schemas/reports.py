from __future__ import annotations

from datetime import date, datetime

from pydantic import BaseModel, ConfigDict


class AiReportOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    created_at: datetime
    trigger: str
    period_start: date | None
    period_end: date | None
    model: str
    prompt_version: str
    summary_md: str
    insights: dict
    tokens_used: int | None


class RefreshReportOut(BaseModel):
    """What POST /reports/refresh returns: the per-source pull result plus
    the report generated on the freshly-pulled data."""

    sources: dict[str, str]
    report: AiReportOut
