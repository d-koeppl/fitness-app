from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, ConfigDict


class CalendarEventOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: str
    title: str | None
    start_ts: datetime | None
    end_ts: datetime | None
    all_day: bool
    location: str | None
