from __future__ import annotations

from datetime import date, datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator, model_validator


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


CheckInFeeling = Literal["energised", "good", "okay", "tired", "stressed", "sore", "ill", "cold", "other"]


class CheckInIn(BaseModel):
    """How the user says they feel today, sent with New report. It is read
    by the report it comes with and saved on it, so the reports of the next
    days see it too."""

    feeling: CheckInFeeling
    strength: int = Field(ge=1, le=5, description="How strong the feeling is, 1 (barely) to 5 (very strong).")
    note: str | None = Field(
        default=None, max_length=80, description="The user's own words, required for `other`."
    )

    @field_validator("note")
    @classmethod
    def _strip_note(cls, note: str | None) -> str | None:
        return (note.strip() or None) if note is not None else None

    @model_validator(mode="after")
    def _other_needs_a_note(self) -> CheckInIn:
        if self.feeling == "other" and not self.note:
            raise ValueError("feeling 'other' needs a note")
        return self
