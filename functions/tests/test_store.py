"""The Firestore store against the emulator: the behaviour every service
relies on, pinned once here (ADR-031)."""

from __future__ import annotations

from datetime import UTC, date, datetime, timedelta

from api.store.rows import (
    AiReport,
    CalendarEvent,
    Conversation,
    ConversationMessage,
    DailyHealth,
    ExerciseHeartRate,
    Fixture,
    LeagueRow,
    LeagueTable,
    MatchPerformance,
    OAuthToken,
)

T0 = datetime(2026, 9, 1, 17, 30, 12, 345678, tzinfo=UTC)


def _event(event_id: str, start: datetime | None, title: str = "Training") -> CalendarEvent:
    return CalendarEvent(
        id=event_id, calendar_id="primary", title=title, start_ts=start, raw={"id": event_id}
    )


# --- health -------------------------------------------------------------------


def test_health_round_trip_keeps_nulls_and_nested_arrays(store):
    raw = {"exercise": [{"interval": {"startTime": "x"}}], "pairs": [[1, 2], [3, 4]]}
    store.put_health_days([DailyHealth(date=date(2026, 9, 3), steps=1000, hrv_ms=41.5, raw=raw)])

    row = store.health_day(date(2026, 9, 3))
    assert row.steps == 1000
    assert row.hrv_ms == 41.5
    assert row.active_zone_minutes is None  # not 0: "no session tracked" (ADR-009)
    assert row.raw == raw
    assert store.health_day(date(2026, 9, 4)) is None


def test_whole_number_floats_stay_floats(store):
    """The migration's JSON export wrote 79.0 as 79. The coach's prompt is
    text, so `"weight_kg": 79` there against `79.0` on the old stack was a
    real difference (found by tools/migrate/snapshot_coach_prompt.py)."""
    store.put_health_days([DailyHealth(date=date(2026, 9, 3), weight_kg=79, hrv_ms=102, steps=5)])
    row = store.health_day(date(2026, 9, 3))
    assert (repr(row.weight_kg), repr(row.hrv_ms), repr(row.steps)) == ("79.0", "102.0", "5")


def test_whole_number_floats_stored_as_ints_read_back_as_floats(store):
    """Production was imported before the fix above, so the read side
    coerces too: re-importing is not what makes the numbers right."""
    store._db.collection("health_months").document("2026-09").set(
        {"days": {"2026-09-03": {"weight_kg": 79, "vo2max": 51, "raw": "{}"}}}
    )
    row = store.health_day(date(2026, 9, 3))
    assert (repr(row.weight_kg), repr(row.vo2max)) == ("79.0", "51.0")


def test_rewriting_a_day_clears_a_field_that_went_null(store):
    store.put_health_days([DailyHealth(date=date(2026, 9, 3), weight_kg=80.0, steps=5)])
    store.put_health_days([DailyHealth(date=date(2026, 9, 3), steps=6)])
    row = store.health_day(date(2026, 9, 3))
    assert (row.weight_kg, row.steps) == (None, 6)


def test_health_days_span_months_in_order_with_either_bound_open(store):
    days = [date(2026, 7, 31), date(2026, 8, 1), date(2026, 8, 31), date(2026, 9, 1), date(2027, 1, 2)]
    store.put_health_days([DailyHealth(date=d, steps=i) for i, d in enumerate(days)])

    assert [r.date for r in store.health_days()] == days
    assert [r.date for r in store.health_days(date(2026, 8, 1), date(2026, 9, 1))] == days[1:4]
    assert [r.date for r in store.health_days(first=date(2026, 8, 31))] == days[2:]
    assert [r.date for r in store.health_days(last=date(2026, 8, 1))] == days[:2]


def test_health_days_desc_walks_back_from_a_day(store):
    days = [date(2026, 6, 30), date(2026, 8, 2), date(2026, 8, 5)]
    store.put_health_days([DailyHealth(date=d) for d in days])
    assert [r.date for r in store.health_days_desc()] == list(reversed(days))
    assert [r.date for r in store.health_days_desc(before=date(2026, 8, 4))] == [days[1], days[0]]


# --- calendar -------------------------------------------------------------------


def test_calendar_range_is_half_open_and_sorted(store):
    store.put_calendar_events(
        [
            _event("b", T0 + timedelta(days=1)),
            _event("a", T0),
            _event("c", T0 + timedelta(days=40)),
            _event("undated", None, "Birthday"),
        ]
    )
    got = store.calendar_events(T0, T0 + timedelta(days=40))
    assert [e.id for e in got] == ["a", "b"]
    assert [e.id for e in store.calendar_events()] == ["a", "b", "c"]
    assert [e.id for e in store.calendar_events(include_undated=True)][-1] == "undated"


def test_an_event_moved_to_another_month_leaves_its_old_bucket(store):
    store.put_calendar_events([_event("x", T0)])
    store.put_calendar_events([_event("x", T0 + timedelta(days=45))])

    assert store.calendar_events(T0 - timedelta(days=1), T0 + timedelta(days=1)) == []
    assert store.calendar_event("x").start_ts == T0 + timedelta(days=45)
    assert len(store.calendar_events()) == 1


def test_calendar_events_from_crosses_months_and_honours_the_limit(store):
    store.put_calendar_events([_event(f"e{i}", T0 + timedelta(days=12 * i)) for i in range(5)])
    got = store.calendar_events_from(T0 + timedelta(days=1), limit=3)
    assert [e.id for e in got] == ["e1", "e2", "e3"]


def test_deleted_events_are_gone_from_bucket_and_index(store):
    store.put_calendar_events([_event("x", T0), _event("y", T0)])
    store.delete_calendar_events(["x"])
    assert [e.id for e in store.calendar_events()] == ["y"]
    assert store.calendar_event("x") is None


def test_timestamps_keep_their_microseconds(store):
    store.put_calendar_events([_event("x", T0)])
    assert store.calendar_event("x").start_ts == T0


# --- matches, traces, skips ----------------------------------------------------------


def test_matches_between_and_by_game_id(store):
    for i, day in enumerate([date(2026, 8, 30), date(2026, 9, 6), date(2026, 9, 13)]):
        store.put_match(
            MatchPerformance(id=i + 1, oefb_game_id=f"g{i}", match_date=day, opponent="X", home_away="home")
        )
    assert [m.oefb_game_id for m in store.matches_between(date(2026, 9, 1), date(2026, 9, 13))] == [
        "g1",
        "g2",
    ]
    assert store.match("g0").match_date == date(2026, 8, 30)
    assert store.match("missing") is None
    assert len(store.matches()) == 3


def test_league_tables_by_day(store):
    for day, points in [(date(2026, 9, 12), 8), (date(2026, 9, 19), 11), (date(2026, 9, 26), 11)]:
        store.put_league_table(
            LeagueTable(
                day=day,
                league="2. Nordwest",
                rows=[LeagueRow(rank=8, team="Eidenberg/Geng", is_us=True, rank_change=-2, points=points)],
            )
        )

    latest = store.league_table()
    assert latest.day == date(2026, 9, 26)
    assert latest.league == "2. Nordwest"
    assert latest.rows == [LeagueRow(rank=8, team="Eidenberg/Geng", is_us=True, rank_change=-2, points=11)]
    assert latest.fetched_at is not None
    assert store.league_table(date(2026, 9, 19)).day == date(2026, 9, 19)
    assert store.league_table(date(2026, 9, 18)).day == date(2026, 9, 12)
    assert store.league_table(date(2026, 9, 11)) is None
    assert [t.day for t in store.league_tables()] == [date(2026, 9, 12), date(2026, 9, 19), date(2026, 9, 26)]


def test_fixtures_are_replaced_whole(store):
    assert store.fixtures() == []
    store.put_fixtures(
        [
            Fixture(oefb_game_id="1", kickoff=T0, opponent="Urfahr", home_away="home", art="Liga"),
            Fixture(oefb_game_id="2", kickoff=None, opponent="Kleinzell", home_away="away"),
        ]
    )
    store.put_fixtures([Fixture(oefb_game_id="2", kickoff=T0, opponent="Kleinzell", home_away="away")])
    assert store.fixtures() == [Fixture(oefb_game_id="2", kickoff=T0, opponent="Kleinzell", home_away="away")]


def test_heart_rate_trace_round_trip(store):
    trace = ExerciseHeartRate(
        session_start=T0,
        date=date(2026, 9, 1),
        session_end=T0 + timedelta(hours=1),
        samples=[[0, 90], [5, 101], [10, 120]],
        zone_seconds={"CARDIO": 300},
    )
    store.put_hr_trace(trace)
    got = store.hr_trace(T0)
    assert got.samples == trace.samples
    assert got.zone_seconds == {"CARDIO": 300}
    assert store.hr_trace(T0 + timedelta(seconds=1)) is None
    assert [t.session_start for t in store.hr_traces_since(date(2026, 9, 1))] == [T0]
    assert store.hr_traces_since(date(2026, 9, 2)) == []


def test_skips_are_idempotent_both_ways(store):
    store.set_skipped("training", "evt/1", True)
    store.set_skipped("training", "evt/1", True)
    assert [(s.source, s.ref_id) for s in store.skipped()] == [("training", "evt/1")]
    store.set_skipped("training", "evt/1", False)
    store.set_skipped("training", "evt/1", False)
    assert store.skipped() == []


# --- reports and drinks ------------------------------------------------------------


def _report(report_id: int, created_at: datetime) -> AiReport:
    return AiReport(
        id=report_id, created_at=created_at, trigger="manual", model="m", prompt_version="v", summary_md="s"
    )


def test_latest_report_and_created_since(store):
    assert store.latest_report() is None
    store.put_report(_report(1, T0))
    store.put_report(_report(2, T0 + timedelta(hours=2)))
    assert store.latest_report().id == 2
    assert store.report_created_since(T0 + timedelta(hours=2))
    assert not store.report_created_since(T0 + timedelta(hours=3))


def test_pending_drinks_are_unclaimed_and_logged_live(store):
    store.add_drinks(2, logged_at=T0)
    store.add_drinks(1, drank_on=date(2026, 8, 20), logged_at=T0)
    ids = [d.id for d in store.pending_drinks()]
    assert len(ids) == 2

    # Claimed in the batch that writes the report that counted it.
    store.put_report(_report(7, T0), claim_drink_ids=ids[:1])
    assert [d.id for d in store.pending_drinks()] == ids[1:]
    assert store.latest_report().id == 7


def test_drink_ids_are_fresh_and_increasing(store):
    store.add_drinks(2, logged_at=T0)
    store.add_drinks(1, logged_at=T0)
    ids = [d.id for d in store.pending_drinks()]
    assert ids == sorted(set(ids)) and len(ids) == 3


def test_drink_windows_split_live_rows_from_late_ones(store):
    store.add_drinks(1, logged_at=T0)
    store.add_drinks(1, drank_on=date(2026, 8, 20), logged_at=T0)

    live = store.drinks_logged_between(T0 - timedelta(hours=1), T0 + timedelta(hours=1))
    assert len(live) == 1 and live[0].drank_on is None
    late = store.drinks_drank_between(date(2026, 8, 20), date(2026, 8, 20))
    assert len(late) == 1 and late[0].drank_on == date(2026, 8, 20)
    assert store.drinks_drank_between(date(2026, 8, 21)) == []

    store.delete_drinks([late[0].id])
    assert store.drinks_drank_between(date(2026, 8, 1)) == []


# --- usage, chats, tokens -------------------------------------------------------------


def test_gemini_usage_counts_per_model(store):
    day = date(2026, 9, 1)
    store.count_gemini_request(day, "gemini-flash-latest")
    store.count_gemini_request(day, "gemini-flash-latest")
    store.count_gemini_request(day, "gemini-2.5-flash")
    assert store.gemini_usage(day) == {"gemini-flash-latest": 2, "gemini-2.5-flash": 1}
    assert store.gemini_usage(day + timedelta(days=1)) == {}


def test_conversations_list_newest_first_and_delete_with_messages(store):
    for conv_id, updated in [(1, T0), (2, T0 + timedelta(hours=1))]:
        store.put_conversation(Conversation(id=conv_id, created_at=T0, updated_at=updated, message_count=2))
    store.put_messages(
        [
            ConversationMessage(id=2, conversation_id=1, role="assistant", content="hi", created_at=T0),
            ConversationMessage(id=1, conversation_id=1, role="user", content="hello", created_at=T0),
        ]
    )
    assert [c.id for c in store.conversations(limit=10)] == [2, 1]
    assert [m.content for m in store.messages(1)] == ["hello", "hi"]

    assert store.delete_conversation(1) is True
    assert store.conversation(1) is None
    assert store.messages(1) == []
    assert store.delete_conversation(1) is False


def test_oauth_token_round_trip(store):
    store.put_oauth_token(OAuthToken(provider="google_health", refresh_token_enc="r", expiry=T0, scopes="s"))
    got = store.oauth_token("google_health")
    assert (got.refresh_token_enc, got.expiry, got.scopes) == ("r", T0, "s")
    assert store.oauth_token("google_calendar") is None
