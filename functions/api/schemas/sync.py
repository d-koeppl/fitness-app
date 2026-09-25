from __future__ import annotations

from pydantic import BaseModel


class SyncOut(BaseModel):
    """What POST /sync returns: one entry per source, "ok" or
    "failed: <reason>"."""

    sources: dict[str, str]
