"""Ask the old or the new API the same questions, and write down the answers.

    # the old API (fitness-dashboard), against a restored copy of production
    DATABASE_URL=postgresql+psycopg2://... python snapshot_api.py old OLD_REPO OUT.json

    # the new API, against the migrated data on the Firestore emulator
    FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 \
        python snapshot_api.py new FUNCTIONS_DIR OUT.json --project demo-fitness-migration

Both apps are called in-process through FastAPI's TestClient, never
entering their lifespan — so the old app's scheduler does not start, and
neither side reaches Google, Gemini or the ÖFB site. Run the two within
the same minute: several answers depend on "today".

The requests cover every endpoint that exists on both sides, with windows
wide enough to reach the whole history: the training status and its
per-day series, every daily row, every session and every stored heart
rate trace, the drink history back two years, matches, the calendar and
the latest report. compare_snapshots.py diffs the two files.
"""

from __future__ import annotations

import json
import sys
from collections import Counter
from pathlib import Path
from urllib.parse import quote

FIXED_REQUESTS = [
    "/training/status?days=730",
    "/health-data/daily?limit=1000",
    "/health-data/latest",
    "/health-data/exercises?limit=1000",
    "/matches",
    "/matches/missing",
    "/calendar/events?limit=200",
    "/drinks",
    "/drinks/days?days=730",
    "/reports/latest",
]


def _old_client(repo: Path):
    sys.path.insert(0, str(repo))
    from fastapi.testclient import TestClient

    from api.main import app

    return TestClient(app)


def _new_client(functions_dir: Path, project: str):
    sys.path.insert(0, str(functions_dir))
    from fastapi.testclient import TestClient
    from google.cloud import firestore

    from api.auth import User, require_user
    from api.integrations.google_health import local_tz
    from api.main import app
    from api.store.firestore import FirestoreStore, get_store

    store = FirestoreStore(firestore.Client(project=project), local_tz())
    app.dependency_overrides[get_store] = lambda: store
    app.dependency_overrides[require_user] = lambda: User(uid="snapshot", email="snapshot@local")
    return TestClient(app)


def snapshot(client) -> dict[str, dict]:
    answers: dict[str, dict] = {}

    def ask(path: str):
        response = client.get(path)
        body = response.json() if response.content else None
        answers[path] = {"status": response.status_code, "body": body}
        return body

    for path in FIXED_REQUESTS:
        ask(path)
    # Every tracked session's trace, by the ids the list itself hands out.
    # Encoded: an id is `<date>#<index>`, and a bare `#` would end the path
    # and turn the rest into a URL fragment — every request a quiet 404.
    for session in answers["/health-data/exercises?limit=1000"]["body"] or []:
        if session.get("source") == "tracked":
            ask(f"/health-data/exercises/{quote(session['id'], safe='')}/heart-rate")
    return answers


def main() -> None:
    side, root, out, *rest = sys.argv[1:]
    if side == "old":
        client = _old_client(Path(root))
    elif side == "new":
        project = rest[rest.index("--project") + 1]
        client = _new_client(Path(root), project)
    else:
        sys.exit("side must be 'old' or 'new'")
    answers = snapshot(client)
    Path(out).write_text(json.dumps(answers, indent=1, sort_keys=True, ensure_ascii=False), encoding="utf-8")
    # Printed so a run where everything failed identically on both sides
    # (which compares as "no differences") cannot pass unnoticed.
    statuses = dict(sorted(Counter(a["status"] for a in answers.values()).items()))
    print(f"{side}: {len(answers)} answers -> {out}; status codes {statuses}")


if __name__ == "__main__":
    main()
