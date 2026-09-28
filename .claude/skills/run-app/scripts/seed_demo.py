"""Fill the Firestore emulator with ~90 days of made-up data.

    FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 functions/venv/bin/python seed_demo.py fitness-75c22

Writes through api/store/firestore.py, like tools/migrate/import_firestore.py,
so the layout is what live writes produce. Deterministic (fixed seed) and
idempotent: every write replaces a whole document. Refuses to run without
the emulator, so it cannot touch production.
"""

from __future__ import annotations

import math
import os
import random
import sys
from datetime import date, datetime, timedelta
from pathlib import Path

REPO = Path(__file__).resolve().parents[4]
sys.path.insert(0, str(REPO / "functions"))

from google.cloud import firestore  # noqa: E402

from api.integrations.google_health import local_tz  # noqa: E402
from api.store import rows  # noqa: E402
from api.store.firestore import FirestoreStore  # noqa: E402


def main(project: str) -> None:
    if not os.environ.get("FIRESTORE_EMULATOR_HOST"):
        sys.exit("FIRESTORE_EMULATOR_HOST is not set; refusing to write to a real Firestore")

    tz = local_tz()
    store = FirestoreStore(firestore.Client(project=project), tz)
    rnd = random.Random(7)
    today = date.today()
    days = [today - timedelta(days=i) for i in range(90, -1, -1)]

    health, events = [], []
    for i, d in enumerate(days):
        # Training Tuesday and Thursday; a match every other Saturday.
        train = d.weekday() in (1, 3)
        match = d.weekday() == 5 and i % 14 < 7
        active = train or match
        health.append(
            rows.DailyHealth(
                date=d,
                steps=int(7500 + 3500 * rnd.random() + (3000 if active else 0)),
                resting_hr=int(round(54 - i * 0.03 + rnd.gauss(0, 1.5))),
                hrv_ms=round(58 + 6 * math.sin(i / 9) + rnd.gauss(0, 4), 1),
                sleep_minutes=int(430 + rnd.gauss(0, 35)),
                active_kcal=int(450 + 300 * rnd.random() + (500 if active else 0)),
                active_zone_minutes=int(20 + 25 * rnd.random() + (60 if train else 0) + (80 if match else 0)),
                weight_kg=round(78.5 - i * 0.01 + rnd.gauss(0, 0.3), 1),
                vo2max=round(49 + i * 0.01, 1),
            )
        )
        # Titles as settings.calendar_training_title / calendar_match_title
        # expect them.
        if train:
            start = datetime(d.year, d.month, d.day, 18, 30, tzinfo=tz)
            events.append(
                rows.CalendarEvent(
                    id=f"tr{d:%Y%m%d}",
                    calendar_id="primary",
                    title="Training",
                    start_ts=start,
                    end_ts=start + timedelta(hours=3),
                )
            )
        if match:
            start = datetime(d.year, d.month, d.day, 16, 0, tzinfo=tz)
            events.append(
                rows.CalendarEvent(
                    id=f"sp{d:%Y%m%d}",
                    calendar_id="primary",
                    title="Spiel: SV Demo - FC Beispiel",
                    start_ts=start,
                    end_ts=start + timedelta(hours=2),
                )
            )

    store.put_health_days(health)
    store.put_calendar_events(events)
    store.put_report(
        rows.AiReport(
            id=1,
            created_at=datetime.now(tz),
            trigger="manual",
            model="demo",
            prompt_version="demo",
            summary_md=(
                "## Demo report\n\nSeeded test data — **not** a real Gemini report.\n\n"
                "- Load is steady.\n- Sleep averages about 7 h."
            ),
            period_start=days[-14],
            period_end=today,
        )
    )
    store.raise_counter("reports", 1)
    print(f"seeded {len(health)} days, {len(events)} calendar events, 1 report")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "fitness-75c22")
