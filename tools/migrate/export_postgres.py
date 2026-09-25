"""Export the fitness-dashboard Postgres tables as JSON, one file per table.

    python tools/migrate/export_postgres.py OUT_DIR \
        --psql "docker exec -i fitness-dashboard-db-1 psql -U fitness -d fitness_prod"

`--psql` is the command that runs psql against the source database;
whatever it is, this only ever sends it SELECTs. Postgres renders the rows
itself (`json_agg`), so no Postgres driver is needed here, and timestamps
come out as ISO 8601 with their offset.

OUT_DIR holds a whole health history plus the encrypted OAuth refresh
tokens: keep it outside both repositories.

Not exported: `alembic_version` (Postgres' own bookkeeping),
`health_samples` (never written; empty in production), and
`push_subscriptions` (Web Push endpoints; FCM replaces them in phase 6
and each device registers again).
"""

from __future__ import annotations

import argparse
import json
import shlex
import subprocess
import sys
from pathlib import Path

TABLES = (
    "daily_health",
    "calendar_events",
    "match_performances",
    "exercise_heart_rate",
    "skipped_activities",
    "ai_reports",
    "drink_logs",
    "conversations",
    "conversation_messages",
    "gemini_usage",
    "oauth_tokens",
)


def export(out_dir: Path, psql: list[str]) -> dict[str, int]:
    out_dir.mkdir(parents=True, exist_ok=True)
    counts: dict[str, int] = {}
    for table in TABLES:
        sql = f"SELECT coalesce(json_agg(t), '[]'::json) FROM {table} t"
        result = subprocess.run(
            [*psql, "-At", "-v", "ON_ERROR_STOP=1", "-c", sql],
            check=True,
            capture_output=True,
            text=True,
            encoding="utf-8",
        )
        rows = json.loads(result.stdout)
        (out_dir / f"{table}.json").write_text(json.dumps(rows, ensure_ascii=False), encoding="utf-8")
        counts[table] = len(rows)
    return counts


def main() -> None:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("out_dir", type=Path)
    parser.add_argument("--psql", required=True, help="command that runs psql against the source database")
    args = parser.parse_args()
    counts = export(args.out_dir, shlex.split(args.psql, posix=sys.platform != "win32"))
    for table, count in counts.items():
        print(f"{count:6d}  {table}")


if __name__ == "__main__":
    main()
