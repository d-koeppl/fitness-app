"""The FastAPI app on its own, and the same app through the Cloud Function
adapter in main.py — the second is the part phase 0 has to prove, since
every later route depends on it."""

from __future__ import annotations

import importlib

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
    importlib.reload(main)
    assert main._wsgi_app.cache_info().currsize == 0


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
