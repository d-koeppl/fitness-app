"""api/config.py — every setting, one typed object.

The only place in functions/ that reads the environment, as in the
fitness-dashboard backend this code came from. Anything else that needs a
setting imports `settings` from here.
"""

from __future__ import annotations

from pydantic import field_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # The Flutter web build is served from Firebase Hosting; the two
    # domains below are the ones Hosting gives every project. Native
    # Android/iOS requests carry no Origin and are not subject to CORS.
    cors_allow_origins: list[str] = [
        "https://fitness-75c22.web.app",
        "https://fitness-75c22.firebaseapp.com",
    ]
    # `flutter run -d chrome` serves from a random localhost port, so an
    # exact list cannot name it. Loopback only: a page on any other host
    # still cannot read this API.
    cors_allow_origin_regex: str = r"^http://(localhost|127\.0\.0\.1)(:\d+)?$"

    # The Google accounts allowed to use the API (ADR-029), as a JSON list:
    # ALLOWED_EMAILS=["someone@gmail.com"]. Empty means nobody: a deploy
    # that forgot to set it is locked, never open. Deployed from
    # functions/.env.<project-id>, which is not committed.
    allowed_emails: list[str] = []

    @field_validator("allowed_emails")
    @classmethod
    def _lowercase(cls, emails: list[str]) -> list[str]:
        return [e.strip().lower() for e in emails if e.strip()]


settings = Settings()
