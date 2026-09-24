"""Write the API's OpenAPI schema to openapi/openapi.json.

Run from functions/:  python -m tools.export_openapi
"""

from __future__ import annotations

import json
from pathlib import Path

from api.main import app

SNAPSHOT = Path(__file__).resolve().parents[2] / "openapi" / "openapi.json"


def main() -> None:
    SNAPSHOT.parent.mkdir(exist_ok=True)
    SNAPSHOT.write_text(json.dumps(app.openapi(), indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(f"wrote {SNAPSHOT}")


if __name__ == "__main__":
    main()
