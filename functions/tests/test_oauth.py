"""Connecting Google (ADR-008, ADR-029): the sealed state, and the routes."""

from __future__ import annotations

import time

import pytest
from cryptography.fernet import Fernet
from fastapi.testclient import TestClient

from api import crypto
from api.config import settings
from api.integrations import google_oauth
from api.main import app


@pytest.fixture(autouse=True)
def fernet_key(monkeypatch):
    monkeypatch.setattr(settings, "token_encryption_key", Fernet.generate_key().decode())
    crypto._fernet.cache_clear()
    yield
    crypto._fernet.cache_clear()


def test_a_state_names_the_target_it_was_made_for():
    assert google_oauth.resolve_state(google_oauth.make_state("health")) == "health"
    assert google_oauth.resolve_state(google_oauth.make_state("calendar")) == "calendar"


def test_every_state_is_different():
    assert google_oauth.make_state("health") != google_oauth.make_state("health")


def test_a_tampered_or_forged_state_is_refused():
    state = google_oauth.make_state("health")
    assert google_oauth.resolve_state(state[:-4] + "AAAA") is None
    assert google_oauth.resolve_state("not-a-state") is None


def test_a_state_from_another_key_is_refused(monkeypatch):
    state = google_oauth.make_state("health")
    monkeypatch.setattr(settings, "token_encryption_key", Fernet.generate_key().decode())
    crypto._fernet.cache_clear()
    assert google_oauth.resolve_state(state) is None


def test_a_state_expires_after_ten_minutes(monkeypatch):
    state = google_oauth.make_state("health")
    real_time = time.time
    monkeypatch.setattr(time, "time", lambda: real_time() + 601)
    assert google_oauth.resolve_state(state) is None


def test_a_state_for_an_unknown_target_is_refused():
    assert google_oauth.resolve_state(crypto.seal('{"target": "gmail"}')) is None


# --- routes ----------------------------------------------------------------------------


def test_login_answers_the_consent_url_with_a_state(db, monkeypatch):
    monkeypatch.setattr(settings, "google_client_id", "client-id")
    monkeypatch.setattr(settings, "google_client_secret", "client-secret")
    monkeypatch.setattr(settings, "google_redirect_uri", "https://example.test/oauth/google/callback")

    response = TestClient(app).post("/oauth/google/login", params={"target": "health"})

    assert response.status_code == 200
    url = response.json()["url"]
    assert url.startswith(google_oauth.GOOGLE_AUTH_URL)
    assert "state=" in url and "googlehealth" in url


def test_login_rejects_an_unknown_target(db):
    assert TestClient(app).post("/oauth/google/login", params={"target": "gmail"}).status_code == 400


def test_login_requires_sign_in():
    # No `db` fixture here, so the real ADR-029 gate is in front of it.
    assert TestClient(app).post("/oauth/google/login", params={"target": "health"}).status_code == 401


def test_the_callback_is_public_but_refuses_a_bad_state(store):
    from api.store.firestore import get_store

    app.dependency_overrides[get_store] = lambda: store
    try:
        response = TestClient(app).get("/oauth/google/callback", params={"code": "c", "state": "forged"})
    finally:
        app.dependency_overrides.clear()
    assert response.status_code == 400
    assert response.json()["detail"] == "Invalid or expired state"


def test_the_callback_stores_the_grant_for_its_target(store, monkeypatch):
    from api.store.firestore import get_store

    monkeypatch.setattr(
        google_oauth,
        "exchange_code",
        lambda code: {"access_token": "at", "refresh_token": "rt", "expires_in": 3600, "scope": "s"},
    )
    app.dependency_overrides[get_store] = lambda: store
    try:
        state = google_oauth.make_state("calendar")
        response = TestClient(app).get("/oauth/google/callback", params={"code": "c", "state": state})
    finally:
        app.dependency_overrides.clear()

    assert response.json() == {"status": "connected", "target": "calendar", "scopes": "s"}
    stored = store.oauth_token("google_calendar")
    assert crypto.decrypt(stored.refresh_token_enc) == "rt"


def test_status_reports_both_targets_as_disconnected_when_empty(db):
    from api.store.firestore import get_store

    app.dependency_overrides[get_store] = lambda: db
    response = TestClient(app).get("/oauth/google/status")
    app.dependency_overrides.pop(get_store, None)
    assert response.json()["calendar"]["connected"] is False
    assert response.json()["health"]["connected"] is False
