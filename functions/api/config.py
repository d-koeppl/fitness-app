"""api/config.py — every setting, one typed object.

The only place in functions/ that reads the environment, as in the
fitness-dashboard backend this code came from. Anything else that needs a
setting imports `settings` from here and reads it at call time, so a test
can override a value by assigning to the attribute.

Carried over from fitness-dashboard's api/config.py (origin/main
2026-09-25) with the settings Route C retired removed: the database URL
(Firestore needs none, ADR-028), Web Push's VAPID keys (FCM, phase 6), and
the Home Assistant wake webhook (dropped). The production values of
everything that affects the numbers were the code defaults, so the
defaults here reproduce production.
"""

from __future__ import annotations

from datetime import date
from typing import Annotated

from pydantic import field_validator
from pydantic_settings import BaseSettings, NoDecode, SettingsConfigDict

# List settings are comma-separated in the environment, not JSON — except
# ALLOWED_EMAILS, which predates this and is a JSON list. `NoDecode` stops
# pydantic-settings from trying json.loads before the validator splits.
CsvList = Annotated[list[str], NoDecode]


def _split_csv(value: object) -> object:
    if isinstance(value, str):
        return [item.strip() for item in value.split(",") if item.strip()]
    return value


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    # --- access (ADR-029) -------------------------------------------------
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

    # The Google accounts allowed to use the API, as a JSON list:
    # ALLOWED_EMAILS=["someone@gmail.com"]. Empty means nobody: a deploy
    # that forgot to set it is locked, never open. Deployed from
    # functions/.env.<project-id>, which is not committed.
    allowed_emails: list[str] = []

    # --- process ----------------------------------------------------------
    log_level: str = "INFO"

    # --- Google OAuth (ADR-006, ADR-008) ----------------------------------
    google_client_id: str = ""
    google_client_secret: str = ""
    google_redirect_uri: str = ""
    # The primary calendar plus any subscribed team calendar.
    google_calendar_ids: CsvList = ["primary"]

    # --- Google Health (ADR-003) ------------------------------------------
    # Sleep is keyed by local wake-up date, so a UTC read of the raw
    # timestamp shifts it a day for anyone east of UTC.
    health_local_tz: str = "Europe/Vienna"
    health_sync_days_back: int = 30
    health_list_max_pages: int = 50

    # --- per-session heart rate (ADR-020) ---------------------------------
    # Intraday heart rate is fetched per tracked session, only for sessions
    # that do not have it yet; the cap stops a first run or a backfill from
    # firing hundreds of requests in one pass.
    health_hr_sessions_per_sync: int = 25
    health_hr_page_size: int = 1000
    health_hr_max_pages: int = 20
    # How many samples the API sends the chart. The stored series keeps
    # every sample; this is what a ~360 px wide phone chart can draw
    # (api/analysis/heart_rate.py::downsample).
    health_hr_chart_points: int = 400

    # --- heart rate zones (ADR-020) ---------------------------------------
    # The API reports minutes per zone but never the bpm boundaries, so the
    # bands are derived (Karvonen) from resting HR and a max HR we are told.
    # A measured max wins over an age formula; with neither, the chart
    # draws a plain trace — the honest fallback, and production's setting.
    health_max_hr_bpm: int | None = None
    health_birth_year: int | None = None

    # --- secrets at rest (ADR-006) ----------------------------------------
    token_encryption_key: str = ""

    # --- Gemini (budget per ADR-013, model alias per ADR-025) -------------
    gemini_api_key: str = ""
    gemini_model: str = "gemini-flash-latest"
    gemini_fallback_model: str = "auto"
    gemini_requests_per_day: int = 20
    gemini_report_reserve: int = 3
    # Google resets requests-per-day at midnight Pacific, so that is the
    # day the budget is keyed by — anything else lets one quota day be
    # spent twice.
    gemini_quota_tz: str = "America/Los_Angeles"
    coach_daily_message_limit: int | None = None
    coach_history_messages: int = 20
    coach_history_max_chars: int = 60_000
    # --- workouts attached to a chat (ADR-021) ----------------------------
    coach_max_attached_sessions: int = 10
    coach_session_hr_max_samples: int = 3000

    # --- schedule (ADR-004, ADR-028) --------------------------------------
    # End-of-day safety net: if nothing produced a report by this local
    # time, the scheduled job runs one. Also the timezone "the first report
    # of the day" is judged in (ADR-019).
    wake_fallback_hour: int = 18
    wake_fallback_minute: int = 0
    wake_fallback_tz: str = "Europe/Vienna"
    oefb_sync_hour: int = 3
    oefb_sync_minute: int = 30
    oefb_sync_days_back: int = 3

    # --- training model ---------------------------------------------------
    # The "Training" calendar block runs 3 hours, but the on-pitch session
    # is a fixed 90 minutes.
    calendar_training_minutes: int = 90
    calendar_training_title: str = "training"
    # Matches are "Spiel: <home> - <away>" on the same calendar, and the
    # event carries the kick-off (ADR-015). A SQL LIKE *pattern*, matched
    # case-insensitively by api/store/like.py, because the opponent's name
    # is part of the title.
    calendar_match_title: str = "spiel:%"

    @field_validator("google_calendar_ids", mode="before")
    @classmethod
    def _csv(cls, value: object) -> object:
        return _split_csv(value)

    @field_validator("allowed_emails")
    @classmethod
    def _lowercase(cls, emails: list[str]) -> list[str]:
        return [e.strip().lower() for e in emails if e.strip()]

    @property
    def max_heart_rate(self) -> int | None:
        """The max HR the zone boundaries are measured from, or None.

        HEALTH_MAX_HR_BPM wins: a ramp-test number is a measurement, and
        220 − age is a population average routinely 10–20 bpm out.
        """
        if self.health_max_hr_bpm:
            return self.health_max_hr_bpm
        if self.health_birth_year:
            age = date.today().year - self.health_birth_year
            if 5 <= age <= 120:
                return 220 - age
        return None

    @property
    def calendar_ids(self) -> list[str]:
        return self.google_calendar_ids


settings = Settings()
