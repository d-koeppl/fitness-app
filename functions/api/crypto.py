"""api/crypto.py — encrypt OAuth tokens at rest (ADR-006).

TOKEN_ENCRYPTION_KEY must be a Fernet key (32 url-safe base64-encoded
bytes). Generate one with:

    python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
"""

from __future__ import annotations

from functools import lru_cache

from cryptography.fernet import Fernet

from api.config import settings


@lru_cache(maxsize=1)
def _fernet() -> Fernet:
    key = settings.token_encryption_key
    if not key:
        raise RuntimeError(
            "TOKEN_ENCRYPTION_KEY is not set — required to store OAuth tokens. "
            "Generate one with: python -c \"from cryptography.fernet import Fernet; "
            'print(Fernet.generate_key().decode())"'
        )
    return Fernet(key.encode())


def encrypt(value: str) -> str:
    return _fernet().encrypt(value.encode()).decode()


def decrypt(token: str) -> str:
    return _fernet().decrypt(token.encode()).decode()


def seal(value: str) -> str:
    """Like `encrypt`, for short-lived values the caller checks the age of
    with `unseal(..., ttl=)` — the OAuth `state` (ADR-029). URL-safe."""
    return _fernet().encrypt(value.encode()).decode()


def unseal(token: str, ttl: int) -> str:
    """The sealed value, or `cryptography.fernet.InvalidToken` if it was
    forged, altered, or sealed more than `ttl` seconds ago."""
    return _fernet().decrypt(token.encode(), ttl=ttl).decode()
