"""api/integrations/google_oauth.py — Google OAuth 2.0 authorization code flow.

Carried over from fitness-dashboard with the token rows moved to Firestore
(`oauth_tokens/<provider>`, ADR-031). Two separate consent flows/tokens,
not one: health.googleapis.com rejects a token whose scope list includes
anything outside its own googlehealth.* domain (DISALLOWED_OAUTH_SCOPES),
so Calendar and Health each get their own row, "google_calendar" and
"google_health" (ADR-008).

Refresh tokens are the durable credential — stored encrypted
(api/crypto.py) and used server-side only; the app never sees a Google
token.

Still to change in phase 3: the pending-state store below is an in-memory
dict, which was fine for one long-running process and is not for Cloud
Functions, where the login and the callback can land on different
instances. Phase 3 replaces it with a signed `state` (ADR-029).
"""

from __future__ import annotations

import secrets
import time
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from urllib.parse import urlencode

import requests

from api.config import settings
from api.crypto import decrypt, encrypt
from api.store.rows import OAuthToken

GOOGLE_AUTH_URL = "https://accounts.google.com/o/oauth2/v2/auth"
GOOGLE_TOKEN_URL = "https://oauth2.googleapis.com/token"

# Each target gets its own consent flow + token row — see module docstring.
# Health scopes per https://developers.google.com/health/scopes.
SCOPE_SETS: dict[str, list[str]] = {
    "calendar": [
        "https://www.googleapis.com/auth/calendar.readonly",
    ],
    "health": [
        "https://www.googleapis.com/auth/googlehealth.activity_and_fitness.readonly",
        "https://www.googleapis.com/auth/googlehealth.health_metrics_and_measurements.readonly",
        "https://www.googleapis.com/auth/googlehealth.sleep.readonly",
    ],
}


def _provider_for(target: str) -> str:
    if target not in SCOPE_SETS:
        raise ValueError(f"Unknown OAuth target {target!r} — expected one of {list(SCOPE_SETS)}")
    return f"google_{target}"


def _store(store):
    if store is not None:
        return store
    from api.store.firestore import get_store

    return get_store()


# CSRF state store, mapping state -> (target, expiry). See the module
# docstring: replaced by a signed state in phase 3.
_PENDING_STATES: dict[str, tuple[str, float]] = {}
_STATE_TTL_SECONDS = 600


def _require_client_config() -> None:
    if not settings.google_client_id or not settings.google_client_secret:
        raise RuntimeError(
            "GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET are not set — create an "
            "OAuth client in Google Cloud Console and add them to the functions' env"
        )


def _prune_expired_states() -> None:
    now = time.time()
    for state, (_target, expires_at) in list(_PENDING_STATES.items()):
        if expires_at < now:
            _PENDING_STATES.pop(state, None)


def build_auth_url(target: str) -> str:
    # Validate the target before the client config: an unknown target is a
    # bad request whatever the server's configuration.
    scopes = SCOPE_SETS[target]  # raises KeyError -> caller turns into 400
    _require_client_config()
    _prune_expired_states()

    state = secrets.token_urlsafe(24)
    _PENDING_STATES[state] = (target, time.time() + _STATE_TTL_SECONDS)

    params = {
        "client_id": settings.google_client_id,
        "redirect_uri": settings.google_redirect_uri,
        "response_type": "code",
        "scope": " ".join(scopes),
        "access_type": "offline",
        # Force the consent screen so Google reliably reissues a refresh
        # token — it only sends one on the very first grant otherwise.
        "prompt": "consent",
        "state": state,
    }
    return f"{GOOGLE_AUTH_URL}?{urlencode(params)}"


def resolve_state(state: str) -> str | None:
    """Consume a state token, returning its target ('calendar'/'health')
    or None if it's unknown/expired."""
    _prune_expired_states()
    entry = _PENDING_STATES.pop(state, None)
    return entry[0] if entry else None


def exchange_code(code: str) -> dict:
    _require_client_config()
    resp = requests.post(
        GOOGLE_TOKEN_URL,
        data={
            "client_id": settings.google_client_id,
            "client_secret": settings.google_client_secret,
            "code": code,
            "grant_type": "authorization_code",
            "redirect_uri": settings.google_redirect_uri,
        },
        timeout=15,
    )
    resp.raise_for_status()
    return resp.json()


def _refresh_access_token(refresh_token: str) -> dict:
    _require_client_config()
    resp = requests.post(
        GOOGLE_TOKEN_URL,
        data={
            "client_id": settings.google_client_id,
            "client_secret": settings.google_client_secret,
            "refresh_token": refresh_token,
            "grant_type": "refresh_token",
        },
        timeout=15,
    )
    resp.raise_for_status()
    return resp.json()


def save_tokens(target: str, token_response: dict, store=None) -> None:
    """Persist tokens from an initial code exchange.

    Google only returns a refresh_token on the first grant (or when
    prompt=consent forces reissue) — fail loudly if it's missing rather
    than silently losing the ability to do the daily server-side pull.
    """
    provider = _provider_for(target)

    refresh_token = token_response.get("refresh_token")
    if not refresh_token:
        raise RuntimeError(
            "Google did not return a refresh_token. Revoke prior access at "
            "https://myaccount.google.com/permissions and retry — "
            "prompt=consent should force reissue."
        )

    access_token = token_response.get("access_token")
    expires_in = token_response.get("expires_in", 3600)
    scope = token_response.get("scope", " ".join(SCOPE_SETS[target]))
    now = datetime.now(UTC)
    _store(store).put_oauth_token(
        OAuthToken(
            provider=provider,
            refresh_token_enc=encrypt(refresh_token),
            access_token_enc=encrypt(access_token) if access_token else None,
            expiry=now + timedelta(seconds=expires_in),
            scopes=scope,
            updated_at=now,
        )
    )


def get_valid_access_token(target: str, store=None) -> str:
    """Return a live access token for `target` ('calendar' or 'health'),
    refreshing via the stored refresh token if the cached one is missing
    or within 60s of expiring. Server-side only."""
    provider = _provider_for(target)
    store = _store(store)

    row = store.oauth_token(provider)
    if row is None:
        raise RuntimeError(
            f"No Google OAuth token stored for {target!r} — connect it from the app's settings first"
        )

    now = datetime.now(UTC)
    needs_refresh = (
        row.access_token_enc is None or row.expiry is None or row.expiry <= now + timedelta(seconds=60)
    )
    if not needs_refresh:
        return decrypt(row.access_token_enc)

    token_response = _refresh_access_token(decrypt(row.refresh_token_enc))
    access_token = token_response["access_token"]
    expires_in = token_response.get("expires_in", 3600)
    row.access_token_enc = encrypt(access_token)
    row.expiry = now + timedelta(seconds=expires_in)
    row.updated_at = now
    store.put_oauth_token(row)
    return access_token


@dataclass(frozen=True)
class TokenStatus:
    """What we can say about a stored grant *without* calling Google.

    `connected` only means a row exists: a grant the user revoked at
    myaccount.google.com still leaves one behind, and the failure only
    surfaces on the next refresh. The extra fields let the app show
    staleness instead of a bare green light that lies.
    """

    connected: bool
    scopes: str | None = None
    access_token_expires_at: datetime | None = None
    updated_at: datetime | None = None


def token_status(store, target: str) -> TokenStatus:
    row = store.oauth_token(_provider_for(target))
    if row is None:
        return TokenStatus(connected=False)
    return TokenStatus(
        connected=True,
        scopes=row.scopes or None,
        access_token_expires_at=row.expiry,
        updated_at=row.updated_at,
    )
