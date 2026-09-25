"""api/routers/oauth.py — connecting Google Calendar and Google Health.

Calendar and Health are separate consent flows (ADR-008) — /login and
/status take a `target` of "calendar" or "health"; /callback is shared and
reads which target it is for out of the sealed `state`.

The one public route in the API besides /healthz is /callback: Google
redirects the browser there, without the app's ID token. The sealed,
ten-minute `state` is what protects it (api/integrations/google_oauth.py,
ADR-029) — only a state this server issued, to someone who was signed in,
gets a code exchanged.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, HTTPException, Query

from api.integrations import google_oauth
from api.schemas.oauth import GoogleStatusOut, OAuthCallbackOut, OAuthLoginOut, TokenStatusOut
from api.store.firestore import FirestoreStore, get_store

router = APIRouter(prefix="/oauth/google", tags=["oauth"])


@router.post("/login", response_model=OAuthLoginOut)
def login(target: str = Query()) -> OAuthLoginOut:
    """The consent URL for `target`. Signed-in only, like everything but
    the callback, so only the owner can start a flow."""
    try:
        return OAuthLoginOut(url=google_oauth.build_auth_url(target))
    except (KeyError, ValueError) as exc:
        raise HTTPException(status_code=400, detail=f"Unknown target {target!r}") from exc


@router.get("/callback", response_model=OAuthCallbackOut)
def callback(
    code: str | None = Query(default=None),
    state: str | None = Query(default=None),
    error: str | None = Query(default=None),
    store: FirestoreStore = Depends(get_store),
) -> OAuthCallbackOut:
    if error:
        raise HTTPException(status_code=400, detail=f"Google OAuth error: {error}")
    if not code or not state:
        raise HTTPException(status_code=400, detail="Missing code or state")

    target = google_oauth.resolve_state(state)
    if target is None:
        raise HTTPException(status_code=400, detail="Invalid or expired state")

    token_response = google_oauth.exchange_code(code)
    google_oauth.save_tokens(target, token_response, store=store)
    return OAuthCallbackOut(status="connected", target=target, scopes=token_response.get("scope", ""))


@router.get("/status", response_model=GoogleStatusOut)
def status(store: FirestoreStore = Depends(get_store)) -> GoogleStatusOut:
    return GoogleStatusOut(
        calendar=TokenStatusOut.model_validate(google_oauth.token_status(store, "calendar")),
        health=TokenStatusOut.model_validate(google_oauth.token_status(store, "health")),
    )
