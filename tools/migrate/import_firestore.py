"""Load an export_postgres.py dump into Firestore through the API's own store.

    # into the emulator (the default; FIRESTORE_EMULATOR_HOST must be set)
    python tools/migrate/import_firestore.py DUMP_DIR --project demo-fitness-migration

    # into production — only with both flags, and only after a dry run
    python tools/migrate/import_firestore.py DUMP_DIR --project fitness-75c22 --production

Writes go through api/store/firestore.py, the same methods the API uses,
so the migrated data is laid out exactly as live writes would lay it out
(ADR-031). Every id Postgres assigned is kept, and the id counters are
raised past them, so nothing the app writes afterwards can collide.

Idempotent: every write replaces a document or a field whole, so running
it twice leaves the same state as running it once. It does not delete
anything, so run it into an empty database.
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from collections import defaultdict
from datetime import date, datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2] / "functions"))

from api.store import rows  # noqa: E402
from api.store.firestore import FirestoreStore  # noqa: E402


def _d(value: str | None) -> date | None:
    return date.fromisoformat(value) if value else None


def _ts(value: str | None) -> datetime | None:
    return datetime.fromisoformat(value) if value else None


def _load(dump: Path, table: str) -> list[dict]:
    return json.loads((dump / f"{table}.json").read_text(encoding="utf-8"))


def migrate(dump: Path, store: FirestoreStore) -> dict[str, int]:
    written: dict[str, int] = {}

    health = [
        rows.DailyHealth(
            date=_d(r["date"]),
            steps=r["steps"],
            resting_hr=r["resting_hr"],
            hrv_ms=r["hrv_ms"],
            sleep_minutes=r["sleep_minutes"],
            active_kcal=r["active_kcal"],
            active_zone_minutes=r["active_zone_minutes"],
            weight_kg=r["weight_kg"],
            vo2max=r["vo2max"],
            source=r["source"],
            raw=r["raw"],
            updated_at=_ts(r["updated_at"]),
        )
        for r in _load(dump, "daily_health")
    ]
    store.put_health_days(health)
    written["daily_health"] = len(health)

    events = [
        rows.CalendarEvent(
            id=r["id"],
            calendar_id=r["calendar_id"],
            title=r["title"],
            start_ts=_ts(r["start_ts"]),
            end_ts=_ts(r["end_ts"]),
            all_day=r["all_day"],
            category=r["category"],
            location=r["location"],
            raw=r["raw"],
            updated_at=_ts(r["updated_at"]),
        )
        for r in _load(dump, "calendar_events")
    ]
    # One batch is capped at 500 writes; a sync writes tens of events.
    for start in range(0, len(events), 100):
        store.put_calendar_events(events[start : start + 100])
    written["calendar_events"] = len(events)

    matches = _load(dump, "match_performances")
    for r in matches:
        store.put_match(
            rows.MatchPerformance(
                id=r["id"],
                oefb_game_id=r["oefb_game_id"],
                match_date=_d(r["match_date"]),
                opponent=r["opponent"],
                home_away=r["home_away"],
                result=r["result"],
                started=r["started"],
                minutes_played=r["minutes_played"],
                goals=r["goals"],
                yellow_card=r["yellow_card"],
                red_card=r["red_card"],
                created_at=_ts(r["created_at"]),
            )
        )
    written["match_performances"] = len(matches)

    traces = _load(dump, "exercise_heart_rate")
    for r in traces:
        store.put_hr_trace(
            rows.ExerciseHeartRate(
                session_start=_ts(r["session_start"]),
                date=_d(r["date"]),
                session_end=_ts(r["session_end"]),
                samples=r["samples"],
                zone_seconds=r["zone_seconds"],
                fetched_at=_ts(r["fetched_at"]),
            )
        )
    written["exercise_heart_rate"] = len(traces)

    skips = _load(dump, "skipped_activities")
    for r in skips:
        store.set_skipped(r["source"], r["ref_id"], True, created_at=_ts(r["created_at"]))
    written["skipped_activities"] = len(skips)

    reports = _load(dump, "ai_reports")
    for r in reports:
        store.put_report(
            rows.AiReport(
                id=r["id"],
                created_at=_ts(r["created_at"]),
                trigger=r["trigger"],
                model=r["model"],
                prompt_version=r["prompt_version"],
                summary_md=r["summary_md"],
                period_start=_d(r["period_start"]),
                period_end=_d(r["period_end"]),
                insights=r["insights"],
                tokens_used=r["tokens_used"],
            )
        )
    written["ai_reports"] = len(reports)

    drinks = [
        rows.DrinkLog(
            id=r["id"],
            logged_at=_ts(r["logged_at"]),
            counted_report_id=r["counted_report_id"],
            drank_on=_d(r["drank_on"]),
        )
        for r in _load(dump, "drink_logs")
    ]
    if drinks:
        store.put_drinks(drinks)
    written["drink_logs"] = len(drinks)

    messages = _load(dump, "conversation_messages")
    per_conversation: dict[int, int] = defaultdict(int)
    for r in messages:
        per_conversation[r["conversation_id"]] += 1
    conversations = _load(dump, "conversations")
    for r in conversations:
        store.put_conversation(
            rows.Conversation(
                id=r["id"],
                title=r["title"],
                created_at=_ts(r["created_at"]),
                updated_at=_ts(r["updated_at"]),
                include=r["include"],
                lookback_days=r["lookback_days"],
                session_ids=r["session_ids"],
                message_count=per_conversation[r["id"]],
            )
        )
    store.put_messages(
        rows.ConversationMessage(
            id=r["id"],
            conversation_id=r["conversation_id"],
            role=r["role"],
            content=r["content"],
            created_at=_ts(r["created_at"]),
        )
        for r in messages
    )
    written["conversations"] = len(conversations)
    written["conversation_messages"] = len(messages)

    usage = _load(dump, "gemini_usage")
    for r in usage:
        store.set_gemini_usage(_d(r["day"]), r["model"], r["requests"])
    written["gemini_usage"] = len(usage)

    tokens = _load(dump, "oauth_tokens")
    for r in tokens:
        # Still encrypted with the old TOKEN_ENCRYPTION_KEY, which moves
        # to Secret Manager with the sync in phase 3.
        store.put_oauth_token(
            rows.OAuthToken(
                provider=r["provider"],
                refresh_token_enc=r["refresh_token_enc"],
                access_token_enc=r["access_token_enc"],
                expiry=_ts(r["expiry"]),
                scopes=r["scopes"],
                updated_at=_ts(r["updated_at"]),
            )
        )
    written["oauth_tokens"] = len(tokens)

    for kind, table in (
        ("drinks", drinks),
        ("reports", reports),
        ("matches", matches),
        ("conversations", conversations),
        ("messages", messages),
    ):
        ids = [r.id if isinstance(r, rows.DrinkLog) else r["id"] for r in table]
        if ids:
            store.raise_counter(kind, max(ids))
    return written


def main() -> None:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument("dump", type=Path)
    parser.add_argument("--project", required=True)
    parser.add_argument(
        "--production", action="store_true", help="write to the real project, not the emulator"
    )
    args = parser.parse_args()

    emulator = os.environ.get("FIRESTORE_EMULATOR_HOST")
    if args.production:
        if emulator:
            sys.exit("--production with FIRESTORE_EMULATOR_HOST set: unset it to write to the real project")
    elif not emulator:
        sys.exit("FIRESTORE_EMULATOR_HOST is not set; pass --production to write to the real project")

    from google.cloud import firestore

    from api.integrations.google_health import local_tz

    store = FirestoreStore(firestore.Client(project=args.project), local_tz())
    target = f"project {args.project}" + ("" if args.production else f" on the emulator at {emulator}")
    print(f"Importing {args.dump} into {target}")
    for table, count in migrate(args.dump, store).items():
        print(f"{count:6d}  {table}")


if __name__ == "__main__":
    main()
