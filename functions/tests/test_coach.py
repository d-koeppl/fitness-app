"""Tests for api/analysis/coach.py — the server-side prompt assembly.

What matters here is that the include toggles actually gate what reaches
Gemini. When the browser built the prompt this was unenforceable, and an
endpoint that ignored the toggles would have looked identical from outside.
"""

from __future__ import annotations

from dataclasses import replace

import pytest

from api.analysis import coach
from api.analysis.training_load import TrainingStatus
from api.services.session_context import AttachedSessions


@pytest.fixture
def settings_window(monkeypatch):
    """Pin the history window so these tests describe the logic, not whatever
    the deployed defaults happen to be."""
    monkeypatch.setattr(coach.settings, "coach_history_messages", 6)
    monkeypatch.setattr(coach.settings, "coach_history_max_chars", 60_000)


CONTEXT = {
    "today": "2026-08-19",
    "recent_daily_health": [{"date": "2026-08-19", "steps": 2824, "resting_hr": 54}],
    "latest_measurements": {"weight_kg": {"value": 79.2, "date": "2026-08-17", "days_ago": 2}},
    "recent_exercises": [
        {"date": "2026-08-19", "type": "RUNNING", "duration_minutes": 41.0, "active_zone_minutes": 55.0}
    ],
    "upcoming_events": [{"title": "Training", "start": "2026-08-20T19:00:00+02:00", "all_day": False}],
    "recent_matches": [{"date": "2026-08-08", "opponent": "Treffling", "minutes_played": 90}],
    "training_series": [
        {"date": "2026-08-07", "fitness": 55.0, "fatigue": 60.0, "form": -5.0, "load": 30},
        {"date": "2026-08-08", "fitness": 55.4, "fatigue": 72.0, "form": -16.6, "load": 80},
    ],
    "alcohol": {
        "unit": "one 0.5 L beer (~20 g of alcohol) per count",
        "since_last_report": {
            "count": 3,
            "first_logged_at": "2026-08-18T20:10:00+02:00",
            "last_logged_at": "2026-08-18T23:40:00+02:00",
        },
        "daily_counts": [{"date": "2026-08-18", "count": 3}],
    },
}

READY_STATUS = TrainingStatus(
    status="maintaining",
    headline="Load and fitness are holding steady.",
    fitness=57.2,
    fatigue=92.8,
    form=-35.6,
    form_pct=-62.1,
    ramp_pct=15.0,
    recovery=95,
    readiness=68,
)


# One pinned workout, as api/services/session_context.py serializes it —
# trimmed to the fields these tests reason about. The real shape is checked
# against the emulator in tests/test_session_context.py; what matters here
# is only that it reaches the prompt.
ATTACHED = {
    "session_id": "2026-08-19#0",
    "date": "2026-08-19",
    "type": "RUNNING",
    "duration_minutes": 41.0,
    "heart_rate": {
        "status": "stored",
        "sample_count": 812,
        "samples_included": 812,
        "zones": [{"zone": "cardio", "lower_bpm": 137, "upper_bpm": 171, "seconds": 1980.0}],
        "samples": [[0, 96], [3, 118], [6, 147]],
    },
}


@pytest.fixture(autouse=True)
def stub_data(monkeypatch):
    monkeypatch.setattr(coach, "build_context", lambda _db, lookback_days=None: CONTEXT)
    monkeypatch.setattr(coach, "get_training_status", lambda _db: READY_STATUS)
    # Nothing pinned unless a test says so — the assembly itself needs a
    # database and is tested against one elsewhere.
    monkeypatch.setattr(
        coach, "attached_sessions", lambda _db, ids: AttachedSessions(sessions=[], missing=[])
    )


def prompt(**flags) -> str:
    return coach.build_system_prompt(None, coach.CoachInclude(**flags))


def pin(monkeypatch, sessions: list[dict], missing: list[str] | None = None):
    """Pretend these workouts are attached to the chat."""
    monkeypatch.setattr(
        coach,
        "attached_sessions",
        lambda _db, ids: AttachedSessions(sessions=sessions, missing=missing or []),
    )


def test_everything_included_by_default():
    text = prompt()
    assert "RUNNING" in text
    assert "Treffling" in text
    assert "Training" in text
    assert "resting_hr" in text


def test_the_last_weigh_in_rides_along_with_the_health_section():
    """The daily rows are null on the days nothing was weighed, and the coach
    used to answer "no recent weight entries" because of it (ADR-018)."""
    text = prompt()
    assert "79.2" in text
    assert "2026-08-17" in text
    # Switched off with the rest of the health data, not on its own.
    assert "79.2" not in prompt(health=False)


def test_each_section_can_be_switched_off():
    assert "RUNNING" not in prompt(exercises=False)
    assert "Treffling" not in prompt(matches=False)
    # The only place the event title appears is the calendar section.
    assert "2026-08-20T19:00" not in prompt(events=False)
    assert "0.5 L beer" not in prompt(alcohol=False)


def test_the_beer_log_is_its_own_toggle_and_carries_what_a_count_is_worth():
    """A bare "3" tells the model nothing about the dose, so the unit
    travels with the count (ADR-019)."""
    text = prompt()
    assert "0.5 L beer" in text
    assert '"count": 3' in text
    # Not gated by the health toggle: it is the one thing here the user
    # logged themselves, and they can ask about it on its own.
    assert "0.5 L beer" in prompt(health=False)


def test_health_toggle_also_gates_the_training_status():
    text = prompt(health=False)
    assert "resting_hr" not in text
    assert "maintaining" not in text
    assert "Fitness (42-day avg)" not in text


def test_health_toggle_also_gates_the_daily_fitness_form_series():
    assert "Daily Fitness / Fatigue / Form history" in prompt()
    assert '"form": -16.6' in prompt()
    assert "Daily Fitness / Fatigue / Form history" not in prompt(health=False)


def test_workouts_are_their_own_toggle_not_part_of_health():
    """Two different questions — "how is my body doing" and "what did I
    actually do" — so switching one off must not take the other with it."""
    assert "RUNNING" in prompt(health=False)
    assert "resting_hr" in prompt(exercises=False)


def test_both_recovery_scores_are_labelled_by_the_window_they_cover():
    """Two 0-100 numbers a few lines apart read as a contradiction unless
    the prompt says one is last night and the other the last three days."""
    text = prompt()
    assert "Recovery: 95/100" in text
    assert "Readiness: 68/100" in text
    assert "last night alone" in text


def test_an_unscored_readiness_says_unknown_rather_than_zero(monkeypatch):
    monkeypatch.setattr(
        coach, "get_training_status", lambda _db: replace(READY_STATUS, recovery=None, readiness=None)
    )
    text = prompt()
    assert "Readiness: unknown/100" in text
    assert "Readiness: 0/100" not in text


def test_training_status_is_described_in_active_zone_minutes():
    """The old client-side prompt still called it a step-count model with
    arbitrary units, months after the switch to AZM."""
    text = prompt()
    assert "Active Zone Minutes" in text
    assert "step count" not in text
    assert "arbitrary" not in text


def test_insufficient_training_data_is_left_out_rather_than_reported_as_zero(monkeypatch):
    monkeypatch.setattr(
        coach,
        "get_training_status",
        lambda _db: TrainingStatus(
            status="insufficient_data",
            headline="Need about 14 days of history.",
            fitness=0.0,
            fatigue=0.0,
            form=0.0,
            form_pct=0.0,
            ramp_pct=0.0,
            recovery=None,
        ),
    )
    assert "Fitness (42-day avg)" not in prompt()


def test_everything_off_says_so_explicitly():
    text = prompt(
        health=False, exercises=False, matches=False, events=False, report=False, alcohol=False
    )
    assert coach.NO_DATA in text
    assert coach.SYSTEM_PREAMBLE in text


def test_the_preamble_and_date_are_always_present():
    text = prompt(
        health=False, exercises=False, matches=False, events=False, report=False, alcohol=False
    )
    assert text.startswith(coach.SYSTEM_PREAMBLE)
    assert "2026-08-19" in text


def test_empty_sections_are_skipped_without_an_empty_heading(monkeypatch):
    monkeypatch.setattr(
        coach,
        "build_context",
        lambda _db, lookback_days=None: {**CONTEXT, "recent_matches": [], "upcoming_events": []},
    )
    text = prompt()
    assert "Match performance" not in text
    assert "Upcoming calendar events" not in text


def test_lookback_days_reaches_build_context_and_the_workout_label(monkeypatch):
    seen = {}
    monkeypatch.setattr(
        coach,
        "build_context",
        lambda _db, lookback_days=None: seen.update(lookback=lookback_days) or CONTEXT,
    )
    text = coach.build_system_prompt(None, coach.CoachInclude(), 365)

    assert seen["lookback"] == 365
    assert "last 365 days" in text


def test_answer_passes_the_assembled_prompt_and_messages_through(monkeypatch):
    seen = {}
    monkeypatch.setattr(
        coach,
        "chat_completion",
        lambda _store, system, messages: seen.update(system=system, messages=messages) or "ok",
    )
    messages = [{"role": "user", "content": "how am I doing?"}]
    reply = coach.answer(None, coach.CoachInclude(), messages)

    assert reply == "ok"
    assert seen["messages"] == messages
    assert seen["system"].startswith(coach.SYSTEM_PREAMBLE)


# --- history window ---------------------------------------------------------
#
# Pure, so it is tested without the emulator: what a stored conversation costs a
# request is decided here (ADR-017), and getting it wrong is invisible until
# a long chat starts failing.


def _turns(n: int) -> list[dict]:
    """n alternating turns, starting on the user."""
    return [
        {"role": "user" if i % 2 == 0 else "assistant", "content": f"m{i}"} for i in range(n)
    ]


def test_trim_history_keeps_a_short_conversation_whole(settings_window):
    messages = _turns(4)
    assert coach.trim_history(messages) == messages


def test_trim_history_keeps_only_the_last_messages(settings_window):
    window = coach.trim_history(_turns(20))
    assert len(window) == 6
    assert [m["content"] for m in window] == ["m14", "m15", "m16", "m17", "m18", "m19"]


def test_trim_history_never_opens_on_an_assistant_turn(settings_window, monkeypatch):
    """A window that starts mid-exchange reads to Gemini as a conversation
    opening with the answer to a question it was never asked."""
    monkeypatch.setattr(coach.settings, "coach_history_messages", 5)
    window = coach.trim_history(_turns(20))
    assert window[0]["role"] == "user"
    # The odd one out is dropped, not kept: 5 back from an even-length
    # alternating list lands on an assistant turn.
    assert len(window) == 4


def test_trim_history_drops_whole_exchanges_over_the_character_budget(settings_window, monkeypatch):
    monkeypatch.setattr(coach.settings, "coach_history_max_chars", 25)
    messages = [
        {"role": "user", "content": "a" * 10},
        {"role": "assistant", "content": "b" * 10},
        {"role": "user", "content": "c" * 10},
        {"role": "assistant", "content": "d" * 10},
    ]
    window = coach.trim_history(messages)
    assert [m["content"] for m in window] == ["c" * 10, "d" * 10]
    assert window[0]["role"] == "user"


def test_trim_history_still_sends_a_single_oversized_message(settings_window, monkeypatch):
    """It is the question being asked. Trimming it to nothing would be worse
    than sending it over budget."""
    monkeypatch.setattr(coach.settings, "coach_history_max_chars", 5)
    messages = [{"role": "user", "content": "x" * 500}]
    assert coach.trim_history(messages) == messages


# --- workouts attached to the chat (ADR-021) --------------------------------


def test_no_attachments_adds_no_section():
    """The common case. An empty heading would cost tokens to say nothing,
    and would invite the model to talk about a session nobody pointed at."""
    text = coach.build_system_prompt(None, coach.CoachInclude(), None, [])
    assert coach.ATTACHED_HEADING not in text


def test_an_attached_workout_reaches_the_prompt_with_its_trace(monkeypatch):
    pin(monkeypatch, [ATTACHED])
    text = coach.build_system_prompt(None, coach.CoachInclude(), None, ["2026-08-19#0"])

    assert coach.ATTACHED_HEADING in text
    assert '"session_id": "2026-08-19#0"' in text
    # The readings themselves, not just their average — the whole point.
    # Compared with the whitespace squeezed out: json.dumps(indent=2) puts
    # each number of a pair on its own line.
    flat = " ".join(text.split())
    assert '"samples": [ [ 0, 96 ], [ 3, 118 ]' in flat
    assert '"seconds": 1980.0' in text


def test_the_heading_explains_the_trace_and_the_status_field(monkeypatch):
    """The trace is the only raw series in the prompt, so the prompt has to
    say what a pair is — and that "not synced" is about us, not the
    session."""
    pin(monkeypatch, [ATTACHED])
    text = coach.build_system_prompt(None, coach.CoachInclude(), None, ["2026-08-19#0"])

    assert "[seconds since the session started, bpm] pairs" in text
    assert "not_synced" in text


def test_an_attachment_is_not_gated_by_the_workouts_toggle(monkeypatch):
    """Pointing at one session and asking about it, then being told "you
    haven't included your workouts", would be absurd. Same reasoning as the
    beer log and the health toggle (ADR-019)."""
    pin(monkeypatch, [ATTACHED])
    text = coach.build_system_prompt(
        None, coach.CoachInclude(exercises=False), None, ["2026-08-19#0"]
    )

    # The fortnight summary is gone...
    assert "Individual tracked workouts" not in text
    # ...and the workout they actually asked about is still there.
    assert '"session_id": "2026-08-19#0"' in text


def test_an_attachment_that_could_not_be_loaded_is_said_out_loud(monkeypatch):
    """The chip is still on screen in the composer, so a coach that simply
    never mentions that workout reads as one that ignored the question."""
    pin(monkeypatch, [], missing=["2026-08-19#4"])
    text = coach.build_system_prompt(None, coach.CoachInclude(), None, ["2026-08-19#4"])

    assert "could not be loaded" in text
    assert "2026-08-19#4" in text
    # No empty data heading over nothing.
    assert coach.ATTACHED_HEADING not in text


def test_the_attached_section_sits_with_the_workout_summary_it_zooms_into(monkeypatch):
    """Order matters in a prompt this long: the detail belongs next to the
    list it is the zoomed-in version of, not after the calendar."""
    pin(monkeypatch, [ATTACHED])
    text = coach.build_system_prompt(None, coach.CoachInclude(), None, ["2026-08-19#0"])

    assert text.index("Individual tracked workouts") < text.index(coach.ATTACHED_HEADING)
    assert text.index(coach.ATTACHED_HEADING) < text.index("Match performance")


def test_answer_forwards_the_attachments(monkeypatch):
    seen = {}
    pin(monkeypatch, [ATTACHED])
    monkeypatch.setattr(
        coach, "chat_completion", lambda _store, system, messages: seen.update(system=system) or "ok"
    )

    coach.answer(
        None, coach.CoachInclude(), [{"role": "user", "content": "how was it?"}], None,
        ["2026-08-19#0"],
    )
    assert '"session_id": "2026-08-19#0"' in seen["system"]


# --- charts in replies (ADR-035) --------------------------------------------


def test_the_coach_is_asked_for_chart_blocks_not_mermaid():
    """The app draws a fenced ```chart block with fl_chart; there is no
    Mermaid renderer in it, so a Mermaid diagram would arrive as source."""
    text = prompt()
    assert "```chart" in text
    assert '"series"' in text
    assert "mermaid" not in text.lower()


def test_the_league_table_rides_with_the_matches(monkeypatch):
    league = {
        "league": "2. Nordwest",
        "table_day": "2026-09-29",
        "next_fixtures": [{"opponent": "Sarleinsbach", "opponent_standing": {"strength": "stronger"}}],
    }
    monkeypatch.setattr(coach, "build_context", lambda _db, lookback_days=None: {**CONTEXT, "league": league})
    text = prompt()
    assert coach.LEAGUE_HEADING in text
    assert "Sarleinsbach" in text
    assert "Sarleinsbach" not in prompt(matches=False)
    # No table scraped yet: no section, and no empty heading.
    monkeypatch.setattr(coach, "build_context", lambda _db, lookback_days=None: {**CONTEXT, "league": None})
    assert coach.LEAGUE_HEADING not in prompt()
