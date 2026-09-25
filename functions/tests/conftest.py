"""Shared fixtures.

Most tests are pure logic and need nothing. The ones that use the `store`
fixture need the Firestore emulator, because the store's job is to get
Firestore's semantics right (null equality, range queries, field paths,
batches) and only the real thing can say whether it did — the same reason
the fitness-dashboard tests ran against real Postgres rather than SQLite.
Without FIRESTORE_EMULATOR_HOST they skip, so `pytest` still works with no
emulator running. CI always runs them, inside `firebase emulators:exec`.

Locally:

    firebase emulators:start --only firestore --project demo-fitness-test
    FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 pytest
"""

from __future__ import annotations

import os
import urllib.request

import pytest

# A "demo-" project id is one the emulator guarantees can never reach a
# real Firebase project, whatever credentials happen to be lying around.
TEST_PROJECT = "demo-fitness-test"

_NEUTRALIZED = {
    "google_client_id": "",
    "google_client_secret": "",
    "gemini_api_key": "",
    "token_encryption_key": "",
    "health_max_hr_bpm": None,
    "health_birth_year": None,
}


@pytest.fixture(autouse=True)
def neutral_settings(monkeypatch):
    """Blank the credentials for every test, so local runs and CI agree.
    A test that needs one sets it explicitly, where it can be seen."""
    from api.config import settings

    for name, value in _NEUTRALIZED.items():
        monkeypatch.setattr(settings, name, value)


def _clear_emulator(host: str) -> None:
    request = urllib.request.Request(
        f"http://{host}/emulator/v1/projects/{TEST_PROJECT}/databases/(default)/documents",
        method="DELETE",
    )
    urllib.request.urlopen(request, timeout=10).close()


@pytest.fixture(scope="session")
def _firestore_client():
    host = os.environ.get("FIRESTORE_EMULATOR_HOST")
    if not host:
        # CI sets REQUIRE_FIRESTORE_EMULATOR, so a broken emulator setup
        # fails the run instead of quietly skipping every store test.
        if os.environ.get("REQUIRE_FIRESTORE_EMULATOR"):
            pytest.fail("REQUIRE_FIRESTORE_EMULATOR is set but FIRESTORE_EMULATOR_HOST is not")
        pytest.skip("FIRESTORE_EMULATOR_HOST not set — start the Firestore emulator to run store tests")
    try:
        _clear_emulator(host)
    except OSError as exc:  # pragma: no cover - environment dependent
        pytest.skip(f"Firestore emulator at {host} unreachable: {exc}")

    from google.cloud import firestore

    return firestore.Client(project=TEST_PROJECT)


@pytest.fixture
def store(_firestore_client):
    """A FirestoreStore on an empty emulator database."""
    from api.integrations.google_health import local_tz
    from api.store.firestore import FirestoreStore

    _clear_emulator(os.environ["FIRESTORE_EMULATOR_HOST"])
    return FirestoreStore(_firestore_client, local_tz())


@pytest.fixture
def db(store):
    """The store behind a SQLAlchemy-shaped shim, for the tests ported from
    fitness-dashboard (see tests/legacy_db.py). The API calls those tests
    make run as a signed-in owner: auth has its own tests (test_auth.py),
    and these are about what the endpoints return."""
    from api.auth import User, require_user
    from api.main import app
    from tests.legacy_db import LegacySession

    app.dependency_overrides[require_user] = lambda: User(uid="u1", email="owner@example.com")
    yield LegacySession(store)
    app.dependency_overrides.pop(require_user, None)


@pytest.fixture
def api_client(store, monkeypatch):
    """The API with the store on the emulator and a signed-in owner."""
    from fastapi.testclient import TestClient

    from api.auth import get_token_verifier
    from api.config import settings
    from api.main import app
    from api.store.firestore import get_store

    monkeypatch.setattr(settings, "allowed_emails", ["owner@example.com"])
    app.dependency_overrides[get_store] = lambda: store
    app.dependency_overrides[get_token_verifier] = lambda: (
        lambda token: {"uid": "u1", "email": "owner@example.com", "email_verified": True}
    )
    client = TestClient(app, headers={"Authorization": "Bearer test"})
    yield client
    app.dependency_overrides.clear()
