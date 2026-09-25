"""api/integrations/gemini_models.py — which Gemini models to call (ADR-025).

The primary is GEMINI_MODEL, normally the rolling `gemini-flash-latest`
alias. The fallback, when GEMINI_FALLBACK_MODEL is `auto`, rolls with it:
the newest *stable* Flash that is older than whatever the alias currently
serves — 3.7 while the alias is on 3.8, 3.8 once it moves to 3.9. It has to
be a different model, because the fallback exists to be a second
requests-per-day budget (ADR-013), and Google counts that per model.

Two things feed that, both confirmed against Google's docs (2026-09-24):

- `models.list` (GET /v1beta/models) says which models exist. A model id
  there is `models/<id>`; a stable Flash is exactly `gemini-<version>-flash`,
  so `-lite`, `-preview-…`, `-image` and friends are left out by the pattern.
  Listing is not a generateContent call, so it spends none of the budget.
- Every generateContent response carries `modelVersion`, "the model version
  used to generate the response" — the only place the alias's target shows.
  `_post_gemini` hands it over through `note_primary_answered`.

Until the primary has answered once in this process, the alias is assumed to
be on the newest stable Flash, so the fallback is the one below that. If the
alias is really on a newer preview, that fallback is still a different model,
just not the closest one; the first answer corrects it.
"""

from __future__ import annotations

import logging
import re
import threading
import time

import requests

from api.config import settings

logger = logging.getLogger("api.integrations.gemini_models")

AUTO = "auto"
LIST_URL = "https://generativelanguage.googleapis.com/v1beta/models"

# Refreshed twice a day — new releases are weeks apart, and a list that is a
# few hours stale still names models that exist. A failed fetch is retried
# sooner, so an outage at startup does not cost the fallback all day.
_LIST_TTL_S = 12 * 3600
_RETRY_AFTER_FAILURE_S = 10 * 60

_STABLE_FLASH = re.compile(r"^gemini-(\d+(?:\.\d+)*)-flash$")
# Prefix match: modelVersion may be a preview (gemini-3.9-flash-preview-…),
# and its version is what the fallback has to stay below.
_ANY_FLASH = re.compile(r"^gemini-(\d+(?:\.\d+)*)-flash(?:-|$)")

_lock = threading.Lock()
_stable: list[str] = []  # newest first
_fetched_at: float | None = None
_retry_at = 0.0
_primary_served: str | None = None


def flash_version(model_id: str) -> tuple[int, ...] | None:
    """(3, 8) for gemini-3.8-flash and for gemini-3.8-flash-preview-…;
    None for anything that is not a numbered Flash model."""
    match = _ANY_FLASH.match(model_id.removeprefix("models/"))
    return tuple(int(part) for part in match.group(1).split(".")) if match else None


def stable_flash_models(listed: list[dict]) -> list[str]:
    """The stable Flash ids in a models.list page, newest first."""
    ids = []
    for model in listed:
        model_id = model.get("name", "").removeprefix("models/")
        if _STABLE_FLASH.match(model_id) and "generateContent" in model.get("supportedGenerationMethods", []):
            ids.append(model_id)
    return sorted(ids, key=flash_version, reverse=True)


def pick_fallback(stable: list[str], primary: str) -> str | None:
    """The newest stable Flash older than `primary`. An alias has no version
    of its own, so until one is known it is taken to be the newest listed."""
    ceiling = flash_version(primary) or (flash_version(stable[0]) if stable else None)
    if ceiling is None:
        return None
    return next((m for m in stable if flash_version(m) < ceiling), None)


def _fetch_stable() -> list[str]:
    listed: list[dict] = []
    params = {"key": settings.gemini_api_key, "pageSize": 1000}
    while True:
        resp = requests.get(LIST_URL, params=params, timeout=10)
        resp.raise_for_status()
        page = resp.json()
        listed.extend(page.get("models", []))
        if not page.get("nextPageToken"):
            return stable_flash_models(listed)
        params["pageToken"] = page["nextPageToken"]


def _stable_models() -> list[str]:
    global _stable, _fetched_at, _retry_at
    with _lock:
        now = time.monotonic()
        fresh = _fetched_at is not None and now - _fetched_at < _LIST_TTL_S
        if fresh or now < _retry_at or not settings.gemini_api_key:
            return _stable
        try:
            _stable = _fetch_stable()
            _fetched_at = now
            logger.info("Gemini stable Flash models: %s", ", ".join(_stable) or "none")
        except requests.RequestException:
            # Keep whatever the last good list said; with none, the day runs
            # on the primary alone rather than failing.
            logger.warning("Listing Gemini models failed — keeping %s", _stable or "no fallback")
            _retry_at = now + _RETRY_AFTER_FAILURE_S
        return _stable


def note_primary_answered(model_version: str | None) -> None:
    """Remember what the primary actually ran on, from the response's
    modelVersion, so the rolling fallback stays below it."""
    global _primary_served
    if model_version and model_version != _primary_served:
        if _primary_served is not None:
            logger.info("Gemini primary moved: %s -> %s", _primary_served, model_version)
        _primary_served = model_version


def candidates() -> list[str]:
    """Primary model first, then the fallback — blanks and duplicates dropped.

    Also the answer to "how many separate requests-per-day budgets do we
    have", which is what the day's allowance is sized from
    (api/services/gemini_usage.py).
    """
    primary = settings.gemini_model
    fallback = settings.gemini_fallback_model
    if fallback == AUTO:
        fallback = pick_fallback(_stable_models(), _primary_served or primary)
    models: list[str] = []
    for name in (primary, fallback):
        if name and name not in models:
            models.append(name)
    return models


def _reset() -> None:
    """Forget everything learned — for tests."""
    global _stable, _fetched_at, _retry_at, _primary_served
    _stable, _fetched_at, _retry_at, _primary_served = [], None, 0.0, None
