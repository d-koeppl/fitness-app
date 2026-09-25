from __future__ import annotations

from datetime import datetime
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field


class PushTokenIn(BaseModel):
    """An FCM registration token. FCM's are about 160 characters; the bound
    only keeps a garbage body out of Firestore."""

    token: str = Field(min_length=1, max_length=4096)


class PushDeviceIn(PushTokenIn):
    platform: Literal["android", "web"]


class PushDeviceOut(BaseModel):
    """What was stored. The token is not echoed back: the caller has it."""

    model_config = ConfigDict(from_attributes=True)

    platform: Literal["android", "web"]
    registered_at: datetime
