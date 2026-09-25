"""The FastAPI app on its own, and the same app through the Cloud Function
adapter in main.py — the second is the part phase 0 has to prove, since
every later route depends on it."""

from __future__ import annotations

import subprocess
import sys
import threading
from pathlib import Path

from fastapi.testclient import TestClient
from flask import Request
from werkzeug.test import EnvironBuilder

import main
from api.main import app


def _call_function(path: str, method: str = "GET", headers: dict[str, str] | None = None):
    environ = EnvironBuilder(path=path, method=method, headers=headers).get_environ()
    return main.api(Request(environ))


def test_healthz():
    response = TestClient(app).get("/healthz")
    assert response.status_code == 200
    assert response.json() == {"status": "ok"}


def test_healthz_through_the_cloud_function_adapter():
    response = _call_function("/healthz")
    assert response.status_code == 200
    assert response.get_json() == {"status": "ok"}


def test_importing_main_does_not_start_the_adapter():
    # The deployed server forks after importing main; an adapter (and its
    # event-loop thread) built at import time hangs every request there.
    # A fresh interpreter, not importlib.reload: main.py declares its
    # Secret Manager parameters at import, and Firebase refuses a second
    # declaration of the same name.
    probe = "import main; print(main._wsgi_app.cache_info().currsize)"
    result = subprocess.run(
        [sys.executable, "-c", probe],
        cwd=Path(main.__file__).parent,
        capture_output=True,
        text=True,
        check=True,
    )
    assert result.stdout.strip() == "0"


def test_a_json_body_reaches_the_app_after_the_server_has_read_it():
    """The emulated server drains the socket into Flask's cache before the
    function runs; a2wsgi reading the raw input then waited forever, and
    every PUT and POST with a body hung (phase 5). The request is answered
    at all — 401, since it carries no token — rather than timing out."""
    environ = EnvironBuilder(path="/drinks", method="PUT", json={"count": 2}).get_environ()
    request = Request(environ)
    request.get_data()
    result: list = []
    worker = threading.Thread(target=lambda: result.append(main.api(request)), daemon=True)
    worker.start()
    worker.join(timeout=10)
    assert result, "the request hung waiting for its body"
    assert result[0].status_code == 401


def test_unknown_path_is_a_404_not_an_adapter_error():
    assert _call_function("/nope").status_code == 404


def test_cors_allows_a_local_flutter_web_origin():
    response = _call_function(
        "/healthz",
        method="OPTIONS",
        headers={"Origin": "http://localhost:53124", "Access-Control-Request-Method": "GET"},
    )
    assert response.status_code == 200
    assert response.headers["access-control-allow-origin"] == "http://localhost:53124"


def test_cors_refuses_any_other_origin():
    response = _call_function(
        "/healthz",
        method="OPTIONS",
        headers={"Origin": "https://evil.example", "Access-Control-Request-Method": "GET"},
    )
    assert "access-control-allow-origin" not in response.headers
