"""api/services/exercises.py — the list of sessions behind a day's load.

The parsing lives one module down, in services/sessions.py; this one is
the two ways the dashboard asks for sessions — the newest N for the
Fitness tab, and a date window for the AI context — plus the half of the
list that no watch recorded.

**Not every session in the list was tracked.** A match played without the
watch, or a training session the watch slept through, still moves the
training load: the model estimates it from the schedule instead (ADR-009,
and the rates in analysis/training_load.py). Those estimates used to be
invisible — the load appeared in the chart with nothing in the list to
explain it, which reads as a bug in the chart. They are listed here too,
marked `source="match"` or `"training"` with the estimate in
`estimated_load` rather than in `active_zone_minutes`, because an estimate
and a measurement are not the same claim and the card says which one it
is.

Neither the rate behind the estimate nor the decision to show it is made
here: both come from `services/training.py.scheduled_sessions`, on the
same pass that feeds the model. A second derivation would be a second
chance to print a number the Fitness chart does not contain.

Listed only while the estimate is actually being counted — that is, while
no tracked session covers it. Coverage is a time window around the
scheduled start, not a property of the day (ADR-015), so a morning walk
leaves the evening training listed as an estimate, while a session that
started at kick-off replaces it. The list therefore never shows a
contribution that is not in the total, and never hides one that is.

`skipped` is the user saying the session did not happen (ill, no time).
The row stays listed, so it can be un-skipped from where it is seen, but
its minutes are already gone from the model — see services/skips.py and
ADR-014.

**A session that was a match carries the match.** The ÖFB log and the
watch describe the same ninety minutes from two sides — result, minutes
played and goals from one, heart rate and distance from the other — and
the schedule pass already decides which tracked session covered which
kick-off. `match_session_ids` turns that decision into a link both ways:
the session lists its match, and GET /matches names the session to open.
"""

from __future__ import annotations

from dataclasses import asdict, dataclass
from datetime import date as date_type
from itertools import islice

from api.analysis.training_load import MATCH
from api.integrations.google_health import EXERCISE_DATA_TYPE
from api.services.league import Standing
from api.services.sessions import ExerciseSession, sessions_for_day
from api.services.training import EstimatedActivity, Schedule, schedule
from api.store.firestore import FirestoreStore
from api.store.rows import DailyHealth, MatchPerformance

DEFAULT_LIMIT = 20


@dataclass
class LinkedMatch(MatchPerformance):
    """An ÖFB row plus the session that was that match, if there is one:
    the tracked workout that covered kick-off, the estimated row for a
    match the watch missed, or None — a match on the bench with no watch,
    or one older than the first tracked day."""

    session_id: str | None = None
    # Filled in only by GET /matches (services/matches.py).
    opponent_standing: Standing | None = None


def _estimated_id(kind: str, ref_id: str) -> str:
    return f"{kind}#{ref_id}"


def match_session_ids(plan: Schedule) -> dict[str, str]:
    """oefb_game_id -> the id of the session that match was.

    Read off the same pass that decides coverage, so a match links to a
    tracked session exactly when that session is why it has no estimate,
    and to its estimated row exactly when it is listed as one.
    """
    estimated = {
        e.activity.ref_id for e in plan.estimated if e.activity.kind == MATCH
    }
    links: dict[str, str] = {}
    for activity in plan.activities:
        if activity.kind != MATCH:
            continue
        if activity.tracked_session_id is not None:
            links[activity.ref_id] = activity.tracked_session_id
        elif activity.ref_id in estimated:
            links[activity.ref_id] = _estimated_id(MATCH, activity.ref_id)
    return links


def linked_match(match: MatchPerformance, links: dict[str, str]) -> LinkedMatch:
    fields = {k: v for k, v in asdict(match).items() if k not in ("session_id", "opponent_standing")}
    return LinkedMatch(**fields, session_id=links.get(match.oefb_game_id))


def _attach_matches(sessions: list[ExerciseSession], plan: Schedule) -> list[ExerciseSession]:
    """Give every session that was a match its ÖFB row, in place."""
    links = match_session_ids(plan)
    by_session = {
        links[a.ref_id]: a.match
        for a in plan.activities
        if a.kind == MATCH and a.match is not None and a.ref_id in links
    }
    for session in sessions:
        match = by_session.get(session.id)
        if match is not None:
            session.match = linked_match(match, links)
    return sessions


def _estimated_rows(estimated: list[EstimatedActivity]) -> list[ExerciseSession]:
    """The given matches and trainings the watch did not record, as rows
    for the same list the tracked sessions go in.

    A mapping, not a calculation. Which sessions these are, and what each
    one is worth, is decided in `services/training.py` on the very pass
    that feeds the model — so a card cannot quote a number the Fitness
    chart does not contain. All that happens here is giving them the shape
    the dashboard renders.
    """
    return [
        ExerciseSession(
            id=_estimated_id(item.activity.kind, item.activity.ref_id),
            date=item.activity.day,
            start_ts=item.activity.start_ts,
            # Not the scheduled block's end: a training block is padded to
            # three hours door-to-door while the model counts a fixed 90
            # minutes on the pitch, and showing both would be two answers
            # to "how long was it".
            end_ts=None,
            exercise_type=None,
            duration_minutes=float(item.activity.minutes),
            active_zone_minutes=None,
            average_heart_rate=None,
            source=item.activity.kind,
            ref_id=item.activity.ref_id,
            title=item.activity.title,
            estimated_load=item.estimated_load,
            skipped=item.activity.skipped,
        )
        for item in estimated
    ]


def _order_key(session: ExerciseSession) -> tuple[date_type, float]:
    """Sorted descending: newest day first, latest session first within a
    day. One with no start time — a match report gives only a date — sorts
    last on its day rather than winning it by accident."""
    return (session.date, session.start_ts.timestamp() if session.start_ts else float("-inf"))


def _newest_first(rows: list[DailyHealth]) -> list[ExerciseSession]:
    """Flatten day rows (already newest-first) into sessions, newest first.

    `sessions_for_day` orders a day's sessions by start time, which is the
    right order *within* a day and the wrong one across a descending list of
    days — hence the reversal.
    """
    sessions: list[ExerciseSession] = []
    for row in rows:
        sessions.extend(reversed(sessions_for_day(row.date, row.raw.get(EXERCISE_DATA_TYPE))))
    return sessions


def _has_exercise(row: DailyHealth) -> bool:
    return EXERCISE_DATA_TYPE in (row.raw or {})


def list_exercise_sessions(store: FirestoreStore, limit: int = DEFAULT_LIMIT) -> list[ExerciseSession]:
    """The most recent sessions behind the training load, newest first.

    Tracked workouts, merged with the untracked matches and trainings the
    model is estimating load for (`_estimated_rows`). Both sides are
    fetched `limit` deep and the merge trims, so the list is the newest
    `limit` sessions there were, whichever source they came from.

    The tracked side walks the months back and keeps only days whose raw
    payload holds sessions, so an unworn fortnight does not eat the budget;
    it stops reading months as soon as it has enough.
    """
    if limit <= 0:
        return []

    # Every matching row holds at least one session, so `limit` rows is
    # always enough to fill `limit` sessions.
    rows = list(islice((row for row in store.health_days_desc() if _has_exercise(row)), limit))
    plan = schedule(store)

    sessions = sorted(
        _newest_first(rows) + _estimated_rows(plan.estimated[:limit]),
        key=_order_key,
        reverse=True,
    )[:limit]
    return _attach_matches(sessions, plan)


def sessions_since(store: FirestoreStore, start: date_type) -> list[ExerciseSession]:
    """Every tracked session from `start` onwards, newest first.

    A date window rather than a count, because the AI context is a window
    over time: "the last 20 sessions" would silently reach back a month for
    someone training twice a week and cover four days for someone training
    twice a day, and the model is being told how many days it is looking at.

    Tracked only, unlike `list_exercise_sessions`: the caller is the AI
    context, which is already handed the match log, the calendar and the
    training status separately. An estimated session there would be the
    same schedule told twice, in a prompt that pays by the token.
    """
    rows = [row for row in reversed(store.health_days(first=start)) if _has_exercise(row)]
    return _newest_first(rows)


def _as_day(candidate: str) -> date_type | None:
    """The date an id's prefix names, or None when it names something else
    (`match`, `training`, or nothing at all)."""
    try:
        return date_type.fromisoformat(candidate)
    except ValueError:
        return None


def find_sessions(store: FirestoreStore, session_ids: list[str]) -> dict[str, ExerciseSession]:
    """The sessions the given ids name, keyed by id. Ids that name nothing
    are simply absent — the caller decides whether that is an error.

    The lookup a *pinned* session needs (ADR-021), where `list_exercise_sessions`
    only answers "the newest N": a workout attached to a coach chat in March
    must still resolve in June, long past the end of any list the dashboard
    renders.

    Two id shapes, because the list holds two kinds of row. `<date>#<index>`
    is a tracked session and is read out of that one day's stored payload —
    the day is in the id, so this costs one row per distinct day however many
    ids are asked for. `match#<ref>` / `training#<ref>` is a session no watch
    recorded, whose row is built by `services/training.schedule` on the same pass
    that feeds the model; those are matched by scanning that pass rather than
    rebuilt here, for the reason `_estimated_rows` gives — a second
    derivation is a second chance to disagree with the Fitness chart.

    The two are told apart by the *prefix*, not the suffix: a match's ref is
    the ÖFB game id, which is all digits, so "the part after the # is a
    number" matches `match#99182` just as well as `2026-08-20#0`. Only a
    prefix that parses as a date makes it a tracked id.

    Deliberately not trimmed to the recent window either side: an old id is
    resolved if the data behind it is still there, and reported missing if it
    is not.
    """
    tracked_days: set[date_type] = set()
    wants_scheduled = False
    for session_id in session_ids:
        prefix, _, suffix = session_id.partition("#")
        day = _as_day(prefix)
        if day is not None and suffix.isdigit():
            tracked_days.add(day)
        else:
            # Anything else, malformed ids included. A scan that finds
            # nothing costs one query and reports the id missing, which is
            # the same answer by a slower route.
            wants_scheduled = True

    found: dict[str, ExerciseSession] = {}
    # Needed either way: the scheduled rows come from it, and it is what
    # says which tracked session was a match.
    plan = schedule(store)

    for day in sorted(tracked_days):
        row = store.health_day(day)
        if row is not None:
            for session in sessions_for_day(row.date, (row.raw or {}).get(EXERCISE_DATA_TYPE)):
                found[session.id] = session

    if wants_scheduled:
        # Every estimate, not the newest few the list takes: a lookup by name,
        # and the newest N is exactly the wrong window for it.
        for session in _estimated_rows(plan.estimated):
            found[session.id] = session

    _attach_matches(list(found.values()), plan)
    return {session_id: found[session_id] for session_id in session_ids if session_id in found}


def find_session(store: FirestoreStore, session_id: str) -> ExerciseSession | None:
    """One session by id — what a tap on a match in the ÖFB log opens."""
    return find_sessions(store, [session_id]).get(session_id)
