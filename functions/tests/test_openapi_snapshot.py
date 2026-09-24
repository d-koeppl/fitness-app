"""The Dart client is generated from openapi/openapi.json, not from the
live app, so a backend change reaches the app only by a deliberate update.
This fails when the two have drifted apart; fix it with

    python -m tools.export_openapi
"""

from __future__ import annotations

import json

from api.main import app
from tools.export_openapi import SNAPSHOT


def test_openapi_snapshot_is_current():
    assert SNAPSHOT.exists(), "run: python -m tools.export_openapi"
    assert json.loads(SNAPSHOT.read_text(encoding="utf-8")) == app.openapi(), (
        "openapi/openapi.json is stale — run: python -m tools.export_openapi"
    )
