"""The access gate (ADR-029). A fake verifier stands in for firebase-admin:
the signature check is Google's code, the decisions around it are ours."""

from __future__ import annotations

import pytest
from fastapi.testclient import TestClient

from api.auth import PUBLIC_PATHS, InvalidToken, get_token_verifier
from api.config import settings
from api.main import app

OWNER = "owner@example.com"

# token -> the claims a verified Firebase ID token would carry
TOKENS = {
    "owner": {"uid": "u1", "email": OWNER, "email_verified": True},
    "owner-shouting": {"uid": "u1", "email": "Owner@Example.com", "email_verified": True},
    "stranger": {"uid": "u2", "email": "stranger@example.com", "email_verified": True},
    "unverified-owner": {"uid": "u3", "email": OWNER, "email_verified": False},
    "no-email": {"uid": "u4"},
}


def fake_verify(token: str) -> dict:
    if token not in TOKENS:
        raise InvalidToken("unknown token")
    return TOKENS[token]


@pytest.fixture
def client(monkeypatch):
    monkeypatch.setattr(settings, "allowed_emails", [OWNER])
    app.dependency_overrides[get_token_verifier] = lambda: fake_verify
    yield TestClient(app)
    app.dependency_overrides.clear()


def _get(client, path: str, token: str | None = None, scheme: str = "Bearer"):
    headers = {"Authorization": f"{scheme} {token}"} if token else {}
    return client.get(path, headers=headers)


def test_the_owner_gets_in(client):
    response = _get(client, "/me", "owner")
    assert response.status_code == 200
    assert response.json() == {"uid": "u1", "email": OWNER}


def test_the_allowlist_ignores_email_case(client):
    assert _get(client, "/me", "owner-shouting").status_code == 200


def test_no_token_is_401(client):
    response = _get(client, "/me")
    assert response.status_code == 401
    assert response.headers["www-authenticate"] == "Bearer"


def test_a_bad_token_is_401(client):
    assert _get(client, "/me", "forged").status_code == 401


def test_a_non_bearer_scheme_is_401(client):
    assert _get(client, "/me", "owner", scheme="Basic").status_code == 401


def test_another_google_account_is_403(client):
    # The case the allowlist exists for: Firebase lets anyone sign in.
    assert _get(client, "/me", "stranger").status_code == 403


def test_an_unverified_email_is_403_even_if_it_matches(client):
    assert _get(client, "/me", "unverified-owner").status_code == 403


def test_a_token_without_an_email_is_403(client):
    assert _get(client, "/me", "no-email").status_code == 403


def test_an_empty_allowlist_locks_everyone_out(client, monkeypatch):
    monkeypatch.setattr(settings, "allowed_emails", [])
    assert _get(client, "/me", "owner").status_code == 403


def test_healthz_stays_public(client):
    assert _get(client, "/healthz").status_code == 200


def test_every_route_but_the_public_ones_is_guarded(client):
    # Guards the design, not one route: a router added later without
    # thinking about auth must still come out locked.
    for route in app.routes:
        path = getattr(route, "path", None)
        if path is None or path in PUBLIC_PATHS or "GET" not in getattr(route, "methods", ()):
            continue
        assert _get(client, path).status_code == 401, path


def test_the_docs_and_schema_urls_are_off(client):
    for path in ("/docs", "/redoc", "/openapi.json"):
        assert _get(client, path).status_code == 404, path
