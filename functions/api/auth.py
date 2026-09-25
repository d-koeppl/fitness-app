"""api/auth.py — who may call the API.

Access control used to be the network's job (Cloudflare Access, ADR-006).
A native app cannot do that browser-cookie login, so the API checks it
itself now (ADR-029): every request carries a Firebase ID token in
`Authorization: Bearer …`, and the token's verified email must be on the
allowlist. Firebase Auth lets *any* Google account sign in to the
project, so the allowlist is the actual gate — verifying the token only
says who someone is.

`require_user` is attached to the whole app in api/main.py. Routes are
protected unless their path is in PUBLIC_PATHS, so a new router cannot be
left open by forgetting a dependency.
"""

from __future__ import annotations

import functools
from dataclasses import dataclass

from fastapi import Depends, HTTPException, Request, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

from api.config import settings

# Liveness only; it says nothing about the data. The Google OAuth callback
# joins this list in phase 3 (Google redirects there without our token;
# a signed `state` protects it instead).
PUBLIC_PATHS = frozenset({"/healthz"})

_bearer = HTTPBearer(auto_error=False)


@dataclass(frozen=True)
class User:
    uid: str
    email: str


class InvalidToken(Exception):
    """The token is missing a field, expired, revoked or not ours."""


@functools.cache
def _firebase_app():
    # Initialised on first use, not at import: the deployed server forks
    # its workers after importing main.py (see the note there).
    import firebase_admin

    return firebase_admin.initialize_app()


def verify_firebase_token(token: str) -> dict:
    """Verify a Firebase ID token and return its claims.

    With FIREBASE_AUTH_EMULATOR_HOST set (the emulator sets it for the
    functions it runs), firebase-admin accepts the emulator's unsigned
    tokens instead — which is why that variable must never be set in a
    deployed function.
    """
    from firebase_admin import auth

    try:
        return auth.verify_id_token(token, app=_firebase_app())
    except (ValueError, auth.InvalidIdTokenError, auth.ExpiredIdTokenError, auth.RevokedIdTokenError) as exc:
        raise InvalidToken(str(exc)) from exc


def get_token_verifier():
    """The dependency tests override to skip real signature checks."""
    return verify_firebase_token


def _unauthorized(detail: str) -> HTTPException:
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail=detail,
        headers={"WWW-Authenticate": "Bearer"},
    )


def require_user(
    request: Request,
    credentials: HTTPAuthorizationCredentials | None = Depends(_bearer),
    verify=Depends(get_token_verifier),
) -> User | None:
    if request.url.path in PUBLIC_PATHS:
        return None
    if credentials is None or credentials.scheme.lower() != "bearer":
        raise _unauthorized("Sign in required")
    try:
        claims = verify(credentials.credentials)
    except InvalidToken:
        raise _unauthorized("Invalid or expired token") from None

    email = (claims.get("email") or "").lower()
    # Google accounts always arrive verified; the check stops an
    # email/password account that merely *claims* an allowlisted address.
    if not email or not claims.get("email_verified"):
        raise HTTPException(status.HTTP_403_FORBIDDEN, "A verified email is required")
    if email not in settings.allowed_emails:
        # Signed in, but not the owner: 403, not 401 — signing in again
        # with the same account cannot fix it.
        raise HTTPException(status.HTTP_403_FORBIDDEN, "This account is not allowed")
    return User(uid=claims["uid"], email=email)


def current_user(request: Request, user: User | None = Depends(require_user)) -> User:
    """For handlers that need the caller; never used on a public path."""
    if user is None:
        raise _unauthorized("Sign in required")
    return user
