from __future__ import annotations

from datetime import datetime

from pydantic import BaseModel, ConfigDict


class TokenStatusOut(BaseModel):
    """`connected` is row-existence only: a grant revoked in the Google
    account settings still leaves a row behind and only fails on the next
    refresh. The timestamps let the dashboard show staleness."""

    model_config = ConfigDict(from_attributes=True)

    connected: bool
    scopes: str | None = None
    access_token_expires_at: datetime | None = None
    updated_at: datetime | None = None


class GoogleStatusOut(BaseModel):
    calendar: TokenStatusOut
    health: TokenStatusOut


class OAuthLoginOut(BaseModel):
    """Google's consent URL, for the app to open in a browser. A JSON answer
    rather than the old redirect: the app cannot attach its ID token to a
    browser navigation, so it asks for the URL with the token first
    (ADR-029)."""

    url: str


class OAuthCallbackOut(BaseModel):
    status: str
    target: str
    scopes: str
