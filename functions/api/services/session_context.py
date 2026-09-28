"""api/services/session_context.py — one workout, in full, for the coach.

ADR-021. The coach's `recent_exercises` section (api/analysis/gemini.py) is
a summary line per session: type, duration, Active Zone Minutes, average
heart rate and the metrics bag. That is the right shape for "what have I
been doing lately" over a fortnight, and the wrong one for "how did I pace
*this* session" — a question that needs the readings, not their average.

So a chat can pin sessions, and a pinned session is serialized here with
everything there is: every named field, the whole open metrics bag, and the
heart rate trace at analysis resolution rather than chart resolution
(ADR-020 stores every sample; the detail sheet only ever asked for the ~400
a phone can draw).

Two things are deliberately explicit in the payload rather than left for
the model to infer:

- **How much of the trace it is holding.** `sample_count` is what is
  stored and `samples_included` what was sent, and when the two differ
  `sampling` says the thinning kept each bucket's extremes. A model told
  "here is the heart rate" and handed a tenth of it would reason about
  peaks that were never in front of it.
- **Why a trace is missing.** Nothing recorded, not synced yet, and "this
  session is an estimate, no watch was involved" are three different
  answers, and only the last one means the question was wrong. They come
  through as `heart_rate.status` — see `_HR_STATUS`.

The numbers themselves are not computed here. The session comes from
`services/exercises.find_sessions` and the trace from
`services/heart_rate.session_heart_rate`, which are the same two functions
behind the list row and the detail sheet — so what the coach is told about
a session cannot drift from what the user is looking at while they ask.
"""

from __future__ import annotations

from dataclasses import dataclass

from api.config import settings
from api.integrations.google_health import local_tz
from api.services.exercises import find_sessions
from api.services.heart_rate import SessionHeartRate, session_heart_rate
from api.services.sessions import TRACKED, ExerciseSession
from api.store.firestore import FirestoreStore
from api.store.rows import MatchPerformance

# What `heart_rate.status` can say, and what each one means to a reader who
# only has the payload:
#   stored       — readings are here, in `samples`.
#   no_readings  — the sync reached this session and the watch had recorded
#                  no heart rate for it. A real answer about the session.
#   not_synced   — the sync has not reached it yet (ADR-020 works newest
#                  first, a bounded number per run). A statement about us,
#                  not about the session, and it may be here tomorrow.
#   untracked    — a match or a training block no watch recorded at all, so
#                  its load is the model's estimate and there was never a
#                  trace to fetch.
STORED = "stored"
NO_READINGS = "no_readings"
NOT_SYNCED = "not_synced"
UNTRACKED = "untracked"

_HR_STATUS_NOTE = {
    NO_READINGS: "The watch recorded no heart rate for this session.",
    NOT_SYNCED: (
        "Not fetched yet — traces are synced newest first, a few sessions per "
        "run, so this one may simply not have arrived. Do not read it as a "
        "session without heart rate."
    ),
    UNTRACKED: (
        "No watch recorded this session, so there is no trace and never was "
        "one; `estimated_load` is the model's estimate from the scheduled "
        "minutes, not a measurement."
    ),
}


@dataclass(frozen=True)
class AttachedSessions:
    """What `attached_sessions` found, and what it did not.

    `missing` is kept rather than swallowed because the two callers want it
    for opposite reasons: a chat *adding* an attachment wants a bad id
    rejected, and a chat *replaying* stored ids wants to carry on and say so
    in the prompt. Both readings need the same list.
    """

    sessions: list[dict]
    missing: list[str]


def _iso_local(stamp) -> str | None:
    """A timestamp in the user's own clock, like every other time in the
    context. The store hands these back in UTC, and a model given "17:00" for
    a 19:00 session simply repeats the wrong hour back (see
    api/analysis/gemini.py::_serialize_events, which learnt this first)."""
    return stamp.astimezone(local_tz()).isoformat() if stamp else None


def _serialize_heart_rate(trace: SessionHeartRate | None, tracked: bool) -> dict:
    """The trace as the model gets it, or the reason there isn't one."""
    if not tracked:
        return {"status": UNTRACKED, "note": _HR_STATUS_NOTE[UNTRACKED]}
    if trace is None or not trace.samples:
        status = NO_READINGS if trace is not None and trace.fetched_at else NOT_SYNCED
        return {"status": status, "note": _HR_STATUS_NOTE[status]}

    payload = {
        "status": STORED,
        "samples_legend": "[seconds since the session started, beats per minute]",
        "sample_count": trace.sample_count,
        "samples_included": len(trace.samples),
        "min_bpm": trace.min_bpm,
        "max_bpm": trace.max_bpm,
        "average_bpm": trace.average_bpm,
        "resting_hr": trace.resting_hr,
        "max_hr": trace.max_hr,
    }
    if len(trace.samples) < trace.sample_count:
        payload["sampling"] = (
            f"thinned from {trace.sample_count} stored readings, keeping the highest "
            "and lowest of each bucket — every peak and trough survives, so the "
            "range is exact and only the flat stretches are coarser"
        )
    else:
        payload["sampling"] = "every reading the watch took"

    if trace.zones:
        payload["zone_source"] = trace.zone_source
        payload["zones_note"] = (
            "Seconds in each zone as Google Health reports them."
            if trace.zone_source == "google"
            else "Seconds in each zone, counted from the readings below against the derived boundaries."
        )
        payload["zones"] = [
            {
                "zone": zone.zone,
                "lower_bpm": zone.lower_bpm,
                "upper_bpm": zone.upper_bpm,
                "seconds": zone.seconds,
            }
            for zone in trace.zones
        ]
    else:
        # Said out loud for the same reason the detail sheet says it: no max
        # HR configured means no honest boundaries, which is different from
        # a session that happened to stay in one zone.
        payload["zones_note"] = (
            "No zone boundaries — they need a maximum heart rate, which is the "
            "highest one recorded in any workout (or HEALTH_MAX_HR_BPM), and none "
            "is recorded yet. The readings below are unaffected."
        )

    # Last, so the fields that say how to read it come before the ~3000
    # numbers being read.
    payload["samples"] = [list(sample) for sample in trace.samples]
    return payload


def _serialize(session: ExerciseSession, trace: SessionHeartRate | None) -> dict:
    tracked = session.source == TRACKED
    return {
        "session_id": session.id,
        "date": session.date.isoformat(),
        "start": _iso_local(session.start_ts),
        "end": _iso_local(session.end_ts),
        "type": session.exercise_type,
        "title": session.title,
        "source": session.source,
        "duration_minutes": session.duration_minutes,
        "active_zone_minutes": session.active_zone_minutes,
        "average_heart_rate": session.average_heart_rate,
        "estimated_load": session.estimated_load,
        "skipped": session.skipped,
        # Google's own field names, units and all — the same pass-through
        # the summary sections use (ADR-012).
        "metrics": session.metrics,
        # The ÖFB report's side of the same game, when the session was one:
        # a model asked how a match went should not have to guess which
        # match, or the score, from a heart rate trace.
        "match": _serialize_match(session.match),
        "heart_rate": _serialize_heart_rate(trace, tracked),
    }


def _serialize_match(match: MatchPerformance | None) -> dict | None:
    if match is None:
        return None
    return {
        "opponent": match.opponent,
        "home_away": match.home_away,
        "result": match.result,
        "started": match.started,
        "minutes_played": match.minutes_played,
        "goals": match.goals,
        "yellow_card": match.yellow_card,
        "red_card": match.red_card,
    }


def attached_sessions(store: FirestoreStore, session_ids: list[str]) -> AttachedSessions:
    """Full detail for the sessions a chat has pinned, in the order asked for.

    Capped at `COACH_MAX_ATTACHED_SESSIONS`: each one carries a whole trace,
    so the cap is what keeps the request a request. Ids past the cap are
    reported as missing rather than dropped silently — being told "only the
    first ten were sent" is the difference between a bounded feature and a
    silently wrong answer.
    """
    if not session_ids:
        return AttachedSessions(sessions=[], missing=[])

    keep = session_ids[: settings.coach_max_attached_sessions]
    over_cap = session_ids[settings.coach_max_attached_sessions :]

    found = find_sessions(store, keep)
    sessions = [
        _serialize(
            session,
            session_heart_rate(store, session_id, settings.coach_session_hr_max_samples)
            if session.source == TRACKED
            else None,
        )
        for session_id, session in found.items()
    ]
    missing = [session_id for session_id in keep if session_id not in found] + over_cap
    return AttachedSessions(sessions=sessions, missing=missing)
