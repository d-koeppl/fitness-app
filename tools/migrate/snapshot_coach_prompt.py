"""Build the coach's context on the old or the new stack, and write it down.

    # the old stack (fitness-dashboard), against a restored copy of production
    DATABASE_URL=postgresql+psycopg2://... python snapshot_coach_prompt.py old OLD_REPO OUT.json

    # the new stack, against the migrated data on the Firestore emulator
    FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 \
        python snapshot_coach_prompt.py new FUNCTIONS_DIR OUT.json --project demo-fitness-migration

Phase 7's test: a chat with a pinned session gets the same context the old
stack builds. So for a spread of cases — every include switch off in turn,
each History choice, workouts pinned (tracked with and without a trace, a
match no watch recorded, one that no longer exists, several at once) —
this records the system prompt `api/analysis/coach.py` builds, and for
every stored conversation the window of history `trim_history` would send
with its next turn. compare_snapshots.py diffs the two files.

The preamble is recorded on its own, because it differs on purpose: the
new one asks for ```chart blocks where the old asked for Mermaid (ADR-035).
Everything after it has to match exactly, with one normalisation: the JSON
in each section is re-serialised with its keys sorted. Postgres JSONB
returns an object's keys shortest first, Firestore's JSON text keeps them
alphabetical, and the order of keys in an object is not information.
Values are untouched — `79` and `79.0` still differ.

Nothing here calls Gemini, and nothing is written. Run the two within the
same minute: "today" and the calendar window move.
"""

from __future__ import annotations

import json
import sys
from collections import Counter
from pathlib import Path

INCLUDE_KEYS = ("health", "exercises", "matches", "events", "report", "alcohol")
LOOKBACKS = (14, 30, 90, 182, 365, 730)
MISSING_ID = "2001-01-01#0"


def _cases(sessions: list[dict], traced: set[str]) -> dict[str, tuple[dict, int | None, list[str]]]:
    """name -> (include flags, lookback as the service passes it, session ids)."""
    everything = dict.fromkeys(INCLUDE_KEYS, True)
    cases: dict[str, tuple[dict, int | None, list[str]]] = {"default": (everything, None, [])}
    for key in INCLUDE_KEYS:
        cases[f"without-{key}"] = ({**everything, key: False}, None, [])
    cases["nothing"] = (dict.fromkeys(INCLUDE_KEYS, False), None, [])
    # 14 reaches the assembler as None (services/conversations.py).
    for days in LOOKBACKS[1:]:
        cases[f"lookback-{days}"] = (everything, days, [])

    tracked = [s["id"] for s in sessions if s.get("source") == "tracked"]
    with_trace = [i for i in tracked if i in traced]
    without_trace = [i for i in tracked if i not in traced]
    untracked = [s["id"] for s in sessions if s.get("source") != "tracked"]
    if with_trace:
        cases["pinned-traced"] = (everything, None, with_trace[:1])
        # A pinned workout is not gated on the workouts switch.
        cases["pinned-traced-without-exercises"] = ({**everything, "exercises": False}, None, with_trace[:1])
        cases["pinned-traced-730"] = (everything, 730, with_trace[:1])
    if without_trace:
        cases["pinned-untraced"] = (everything, None, without_trace[:1])
    if untracked:
        cases["pinned-untracked"] = (everything, None, untracked[:1])
    cases["pinned-missing"] = (everything, None, [MISSING_ID])
    cases["pinned-several"] = (everything, None, (with_trace[:3] + untracked[:1] + [MISSING_ID]))
    return cases


def _canonical(context: str) -> str:
    """Each section's JSON with sorted keys; see the module docstring."""
    sections = []
    for section in context.split("\n\n"):
        lines = section.split("\n")
        start = next((i for i, line in enumerate(lines) if line[:1] in "[{"), None)
        if start is not None:
            try:
                parsed = json.loads("\n".join(lines[start:]))
            except ValueError:
                pass
            else:
                section = "\n".join([*lines[:start], json.dumps(parsed, indent=2, sort_keys=True)])
        sections.append(section)
    return "\n\n".join(sections)


def _old(repo: Path):
    sys.path.insert(0, str(repo))
    from api.analysis import coach
    from api.db import SessionLocal
    from api.services import conversations
    from api.services.exercises import list_exercise_sessions

    db = SessionLocal()

    def build(include: dict, lookback: int | None, ids: list[str]) -> str:
        return coach.build_system_prompt(db, coach.CoachInclude(**include), lookback, ids)

    def histories() -> dict[str, list[dict]]:
        return {
            str(conv.id): coach.trim_history(
                [{"role": m.role, "content": m.content} for m in conversations.messages_for(db, conv.id)]
            )
            for conv, _count in conversations.list_conversations(db, limit=1000)
        }

    def traced_ids() -> set[str]:
        from api.services.heart_rate import session_heart_rate

        return {
            s.id
            for s in list_exercise_sessions(db, limit=1000)
            if s.source == "tracked" and (hr := session_heart_rate(db, s.id)) is not None and hr.samples
        }

    sessions = [{"id": s.id, "source": s.source} for s in list_exercise_sessions(db, limit=1000)]
    return coach, build, histories, sessions, traced_ids()


def _new(functions_dir: Path, project: str):
    sys.path.insert(0, str(functions_dir))
    from google.cloud import firestore

    from api.analysis import coach
    from api.integrations.google_health import local_tz
    from api.services import conversations
    from api.services.exercises import list_exercise_sessions
    from api.services.heart_rate import session_heart_rate
    from api.store.firestore import FirestoreStore

    store = FirestoreStore(firestore.Client(project=project), local_tz())

    def build(include: dict, lookback: int | None, ids: list[str]) -> str:
        return coach.build_system_prompt(store, coach.CoachInclude(**include), lookback, ids)

    def histories() -> dict[str, list[dict]]:
        return {
            str(conv.id): coach.trim_history(
                [{"role": m.role, "content": m.content} for m in conversations.messages_for(store, conv.id)]
            )
            for conv in conversations.list_conversations(store, limit=1000)
        }

    listed = list_exercise_sessions(store, limit=1000)
    traced = {
        s.id
        for s in listed
        if s.source == "tracked" and (hr := session_heart_rate(store, s.id)) is not None and hr.samples
    }
    sessions = [{"id": s.id, "source": s.source} for s in listed]
    return coach, build, histories, sessions, traced


def main() -> None:
    side, root, out, *rest = sys.argv[1:]
    if side == "old":
        coach, build, histories, sessions, traced = _old(Path(root))
    elif side == "new":
        coach, build, histories, sessions, traced = _new(Path(root), rest[rest.index("--project") + 1])
    else:
        sys.exit("side must be 'old' or 'new'")

    answers: dict[str, dict] = {}
    for name, (include, lookback, ids) in _cases(sessions, traced).items():
        prompt = build(include, lookback, ids)
        if not prompt.startswith(coach.SYSTEM_PREAMBLE):
            sys.exit(f"{name}: the prompt does not start with the preamble")
        answers[f"prompt/{name}"] = {
            "status": 200,
            "body": {"ids": ids, "context": _canonical(prompt[len(coach.SYSTEM_PREAMBLE) :])},
        }
    for conv_id, window in histories().items():
        answers[f"history/{conv_id}"] = {"status": 200, "body": window}

    Path(out).write_text(json.dumps(answers, indent=1, sort_keys=True, ensure_ascii=False), encoding="utf-8")
    kinds = Counter(key.split("/")[0] for key in answers)
    pinned = sum(1 for key in answers if key.startswith("prompt/pinned"))
    print(f"{side}: {dict(kinds)} ({pinned} with pinned workouts) -> {out}")


if __name__ == "__main__":
    main()
