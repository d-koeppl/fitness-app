"""Tests for the beer counter (ADR-019).

The rule worth protecting here is the reset: the counter is cleared by the
*first* AI report of a local day and by nothing else, so a second report
the same evening cannot swallow a night that is still going on. Everything
below either checks that rule or the arithmetic it rests on.

The second rule, since ADR-023, is the wall between the two ways in: a beer
filled in for an earlier day lands on that day's history and never on the
counter, so remembering Saturday's round on Tuesday cannot inflate Tuesday's
stepper or be reported as Tuesday's evening.
"""

from __future__ import annotations

from datetime import UTC, date, datetime, time, timedelta
from zoneinfo import ZoneInfo

import pytest
from fastapi.testclient import TestClient

from api.analysis import gemini
from api.main import app
from api.services import drinks
from api.store.firestore import get_store
from tests.legacy_db import AiReport, DrinkLog


@pytest.fixture(autouse=True)
def vienna(monkeypatch):
    """Pin the local zone the day boundaries are read in, so a developer's
    own .env cannot move the day a 22:30 UTC drink lands on."""
    from api.config import settings

    monkeypatch.setattr(settings, "health_local_tz", "Europe/Vienna")
    monkeypatch.setattr(settings, "wake_fallback_tz", "Europe/Vienna")


@pytest.fixture
def client(db):
    app.dependency_overrides[get_store] = lambda: db
    yield TestClient(app)
    app.dependency_overrides.clear()


def _report(db, created_at: datetime) -> AiReport:
    report = AiReport(
        trigger="manual",
        model="test",
        prompt_version="test",
        summary_md="",
        insights={},
        created_at=created_at,
    )
    db.add(report)
    db.flush()
    return report


def _log(db, when: datetime) -> DrinkLog:
    """A drink at a chosen time. The service's own `log_drink` takes the
    database clock, which is right in production and useless in a test that
    needs two different days."""
    row = DrinkLog(logged_at=when)
    db.add(row)
    db.flush()
    return row


def _today() -> date:
    """The local day the service means by "today" â€” Vienna's, per the
    fixture above, which is the zone the day boundaries are read in."""
    return datetime.now(ZoneInfo("Europe/Vienna")).date()


def _log_on(db, day: date, hour: int = 20) -> DrinkLog:
    """A drink tapped in live at `hour` on a local day, for the tests that
    have to mix "logged at the time" with "filled in later" on the same
    day. Relative to the real today, because that is what `set_day` and
    `day_history` measure their windows against."""
    return _log(db, datetime.combine(day, time(hour), tzinfo=ZoneInfo("Europe/Vienna")))


# --- the counter -----------------------------------------------------------


def test_an_untouched_counter_is_zero_with_no_window(db):
    counter = drinks.pending(db)
    assert counter.count == 0
    assert counter.first_logged_at is None and counter.last_logged_at is None


def test_logging_counts_up_and_remembers_both_ends(db):
    drinks.log_drink(db)
    counter = drinks.log_drink(db)

    assert counter.count == 2
    assert counter.first_logged_at is not None
    assert counter.last_logged_at >= counter.first_logged_at


def test_minus_one_removes_the_most_recent_tap(db):
    _log(db, datetime(2026, 9, 6, 20, 0, tzinfo=UTC))
    last = _log(db, datetime(2026, 9, 6, 22, 0, tzinfo=UTC))

    counter = drinks.remove_last(db)

    assert counter.count == 1
    assert db.get(DrinkLog, last.id) is None


def test_minus_one_at_zero_is_a_no_op(db):
    assert drinks.remove_last(db).count == 0


def test_minus_one_cannot_reach_a_drink_a_report_already_counted(db):
    counted = _log(db, datetime(2026, 9, 5, 21, 0, tzinfo=UTC))
    report = _report(db, datetime(2026, 9, 6, 8, 0, tzinfo=UTC))
    drinks.close_out(db, report)

    counter = drinks.remove_last(db)

    assert counter.count == 0
    # Still there, still attached to the report that described that evening.
    assert db.get(DrinkLog, counted.id).counted_report_id == report.id


# --- the reset -------------------------------------------------------------


def test_closing_out_claims_every_pending_drink_and_zeroes_the_counter(db):
    _log(db, datetime(2026, 9, 6, 20, 0, tzinfo=UTC))
    _log(db, datetime(2026, 9, 6, 21, 0, tzinfo=UTC))
    report = _report(db, datetime(2026, 9, 7, 8, 0, tzinfo=UTC))

    assert drinks.close_out(db, report) == 2
    assert drinks.pending(db).count == 0


def test_drinks_logged_after_a_close_out_start_the_next_counter(db):
    _log(db, datetime(2026, 9, 6, 20, 0, tzinfo=UTC))
    report = _report(db, datetime(2026, 9, 7, 8, 0, tzinfo=UTC))
    drinks.close_out(db, report)

    _log(db, datetime(2026, 9, 7, 19, 0, tzinfo=UTC))

    assert drinks.pending(db).count == 1


def test_the_second_report_of_a_day_does_not_reset_the_counter(db):
    """The whole point of ADR-019's "first report only" rule, at the level
    run_analysis decides it: a report already exists today, so the evening
    that is still going on survives."""
    from api.services import reports as reports_service

    # Local midnight rather than "half an hour ago", which is yesterday if
    # the suite happens to run just after midnight.
    _report(db, reports_service.local_day_start())
    _log(db, datetime.now(UTC))

    # This is what run_analysis asks before it writes its row.
    assert reports_service.report_exists_today(db) is True
    assert drinks.pending(db).count == 1


def test_the_first_report_of_a_day_sees_no_earlier_one(db):
    from api.services import reports as reports_service

    _report(db, datetime.now(UTC) - timedelta(days=1, hours=6))

    assert reports_service.report_exists_today(db) is False


def test_typing_a_number_adds_the_difference(db):
    _log(db, datetime(2026, 9, 6, 20, 0, tzinfo=UTC))

    counter = drinks.set_count(db, 4)

    assert counter.count == 4
    # The row that was already there keeps its own time â€” only the three new
    # ones carry the moment the number was typed.
    assert counter.first_logged_at == datetime(2026, 9, 6, 20, 0, tzinfo=UTC)


def test_typing_a_smaller_number_takes_the_newest_off(db):
    first = _log(db, datetime(2026, 9, 6, 20, 0, tzinfo=UTC))
    newest = _log(db, datetime(2026, 9, 6, 22, 0, tzinfo=UTC))

    assert drinks.set_count(db, 1).count == 1
    assert db.get(DrinkLog, first.id) is not None
    assert db.get(DrinkLog, newest.id) is None


def test_typing_the_same_number_changes_nothing(db):
    row = _log(db, datetime(2026, 9, 6, 20, 0, tzinfo=UTC))

    assert drinks.set_count(db, 1).count == 1
    assert db.get(DrinkLog, row.id) is not None


def test_typing_zero_clears_the_counter_but_not_the_history(db):
    counted = _log(db, datetime(2026, 9, 5, 21, 0, tzinfo=UTC))
    report = _report(db, datetime(2026, 9, 6, 8, 0, tzinfo=UTC))
    drinks.close_out(db, report)
    _log(db, datetime(2026, 9, 6, 20, 0, tzinfo=UTC))

    assert drinks.set_count(db, 0).count == 0
    # The counter empties; the evening an earlier report described does not.
    assert db.get(DrinkLog, counted.id) is not None


def test_a_typed_number_cannot_reach_a_counted_drink(db):
    """Setting 3 with two drinks already claimed adds three new ones â€” it
    does not "top up" to three by un-counting what the report described."""
    _log(db, datetime(2026, 9, 5, 20, 0, tzinfo=UTC))
    _log(db, datetime(2026, 9, 5, 21, 0, tzinfo=UTC))
    report = _report(db, datetime(2026, 9, 6, 8, 0, tzinfo=UTC))
    drinks.close_out(db, report)

    assert drinks.set_count(db, 3).count == 3
    assert len(drinks.daily_counts(db, date(2026, 9, 1))) == 2  # two days, 2 + 3


# --- history ---------------------------------------------------------------


def test_daily_counts_groups_by_local_day_and_keeps_counted_drinks(db):
    # 21:00 and 23:00 Vienna on the 6th, then 00:30 Vienna on the 7th.
    _log(db, datetime(2026, 9, 6, 19, 0, tzinfo=UTC))
    _log(db, datetime(2026, 9, 6, 21, 0, tzinfo=UTC))
    _log(db, datetime(2026, 9, 6, 22, 30, tzinfo=UTC))
    report = _report(db, datetime(2026, 9, 7, 8, 0, tzinfo=UTC))
    drinks.close_out(db, report)

    history = drinks.daily_counts(db, date(2026, 9, 1))

    assert [(d.date, d.count) for d in history] == [
        (date(2026, 9, 6), 2),
        (date(2026, 9, 7), 1),
    ]


def test_daily_counts_starts_at_the_window(db):
    _log(db, datetime(2026, 9, 1, 18, 0, tzinfo=UTC))
    _log(db, datetime(2026, 9, 6, 18, 0, tzinfo=UTC))

    history = drinks.daily_counts(db, date(2026, 9, 5))

    assert [d.date for d in history] == [date(2026, 9, 6)]


# --- what the report and the coach are told --------------------------------


def test_the_context_leaves_alcohol_out_until_something_is_logged(db):
    assert gemini._serialize_alcohol(db, date(2026, 9, 7), 14) is None


def test_the_context_carries_the_counter_and_the_history(db):
    _log(db, datetime(2026, 9, 6, 19, 0, tzinfo=UTC))
    _log(db, datetime(2026, 9, 6, 21, 0, tzinfo=UTC))

    payload = gemini._serialize_alcohol(db, date(2026, 9, 7), 14)

    assert payload["since_last_report"]["count"] == 2
    assert payload["since_last_report"]["first_logged_at"] is not None
    assert [d["count"] for d in payload["daily_counts"]] == [2]
    # The size of a drink travels with the count — a bare "2" is not a dose.
    assert "0.5 L beer" in payload["unit"]


def test_a_zero_counter_still_reaches_the_model_once_there_is_history(db):
    """A dry night is worth reporting; a user who has never touched the
    button is not. Only the second case drops out (the test above)."""
    _log(db, datetime(2026, 9, 6, 19, 0, tzinfo=UTC))
    report = _report(db, datetime(2026, 9, 7, 8, 0, tzinfo=UTC))
    drinks.close_out(db, report)

    payload = gemini._serialize_alcohol(db, date(2026, 9, 7), 14)

    assert payload["since_last_report"]["count"] == 0
    assert [d["count"] for d in payload["daily_counts"]] == [1]


def test_the_report_sees_a_filled_in_day_in_the_history_and_a_quiet_counter(db):
    drinks.set_day(db, _today() - timedelta(days=3), 4)

    payload = gemini._serialize_alcohol(db, _today(), 14)

    assert payload["since_last_report"]["count"] == 0
    assert [d["count"] for d in payload["daily_counts"]] == [4]


# --- the endpoints ---------------------------------------------------------


def test_the_stepper_round_trips_through_the_api(client):
    assert client.get("/drinks").json()["count"] == 0

    first = client.post("/drinks")
    assert first.status_code == 201
    assert first.json()["count"] == 1
    assert first.json()["volume_l"] == drinks.DRINK_VOLUME_L

    assert client.post("/drinks").json()["count"] == 2
    assert client.delete("/drinks/last").json()["count"] == 1
    assert client.get("/drinks").json()["count"] == 1


def test_undoing_past_zero_answers_with_zero_rather_than_an_error(client):
    assert client.delete("/drinks/last").status_code == 200
    assert client.get("/drinks").json()["count"] == 0


def test_a_typed_count_round_trips_and_is_idempotent(client):
    assert client.put("/drinks", json={"count": 6}).json()["count"] == 6
    # Sent twice by a flaky connection: still six, where a repeated POST
    # would have been seven.
    assert client.put("/drinks", json={"count": 6}).json()["count"] == 6
    assert client.get("/drinks").json()["count"] == 6

    assert client.put("/drinks", json={"count": 2}).json()["count"] == 2


def test_a_slipped_finger_is_refused_rather_than_stored(client):
    assert client.put("/drinks", json={"count": 100}).status_code == 422
    assert client.put("/drinks", json={"count": -1}).status_code == 422
    assert client.get("/drinks").json()["count"] == 0


# --- earlier days (ADR-023) ------------------------------------------------


def test_filling_in_an_earlier_day_lands_on_that_day_not_on_the_counter(db):
    """The whole point: Saturday's forgotten round, entered on Tuesday, is
    Saturday's â€” the stepper does not move and the history does."""
    day = _today() - timedelta(days=3)

    tally = drinks.set_day(db, day, 3)

    assert (tally.date, tally.count, tally.reported) == (day, 3, 0)
    assert drinks.pending(db).count == 0
    assert (day, 3) in [(d.date, d.count) for d in drinks.daily_counts(db, day)]


def test_a_day_filled_in_afterwards_is_never_claimed_by_the_next_report(db):
    """A backfilled row is history from birth, so the first report of the
    day has nothing to claim â€” otherwise last week's beer would be reported
    as tonight's evening."""
    drinks.set_day(db, _today() - timedelta(days=3), 2)
    report = _report(db, datetime.now(UTC))

    assert drinks.close_out(db, report) == 0
    assert drinks.pending(db).count == 0
    # Still there, still on its own day.
    assert sum(d.count for d in drinks.daily_counts(db, _today() - timedelta(days=7))) == 2


def test_filling_in_the_same_day_twice_lands_on_the_same_number(db):
    day = _today() - timedelta(days=2)

    assert drinks.set_day(db, day, 4).count == 4
    # Sent twice by a flaky connection: still four, where a POST would have
    # been eight.
    assert drinks.set_day(db, day, 4).count == 4


def test_correcting_an_earlier_day_downwards_takes_the_newest_off(db):
    day = _today() - timedelta(days=2)
    drinks.set_day(db, day, 4)

    assert drinks.set_day(db, day, 1).count == 1
    assert [d.count for d in drinks.daily_counts(db, day)] == [1]


def test_an_earlier_day_can_be_raised_above_what_a_report_counted(db):
    """The common case: last night was reported as two beers because two
    were tapped in. It was five."""
    day = _today() - timedelta(days=1)
    _log_on(db, day)
    _log_on(db, day, hour=22)
    report = _report(db, datetime.now(UTC))
    drinks.close_out(db, report)

    tally = drinks.set_day(db, day, 5)

    assert (tally.count, tally.reported) == (5, 2)
    # The two the report described are untouched; three were added.
    assert drinks.pending(db).count == 0


def test_an_earlier_day_cannot_be_cut_below_what_a_report_counted(db):
    day = _today() - timedelta(days=1)
    _log_on(db, day)
    _log_on(db, day, hour=22)
    report = _report(db, datetime.now(UTC))
    drinks.close_out(db, report)

    with pytest.raises(ValueError, match="already counted 2"):
        drinks.set_day(db, day, 1)

    assert [d.count for d in drinks.daily_counts(db, day)] == [2]


def test_cutting_a_day_no_report_has_seen_yet_also_takes_it_off_the_counter(db):
    """Yesterday's taps are still on the stepper until the morning report
    claims them, so correcting yesterday down reaches them â€” and must. The
    alternative is a counter still showing beers the history no longer
    holds, which is the one state this module exists to prevent. It is why
    the client re-reads the counter after editing a day.
    """
    day = _today() - timedelta(days=1)
    _log_on(db, day)
    _log_on(db, day, hour=22)
    assert drinks.pending(db).count == 2

    assert drinks.set_day(db, day, 1).count == 1
    assert drinks.pending(db).count == 1


def test_correcting_a_day_takes_the_filled_in_beers_off_before_the_logged_ones(db):
    """A live tap is a stronger record than a number typed days later, so a
    correction downwards spends the backfilled rows first â€” they are the
    newest end, which is the end the counter's minus works from too."""
    day = _today() - timedelta(days=2)
    tapped = _log_on(db, day)
    drinks.set_day(db, day, 3)

    assert drinks.set_day(db, day, 1).count == 1
    assert db.get(DrinkLog, tapped.id) is not None


def test_todays_beers_are_the_counters_business(db):
    with pytest.raises(ValueError, match="today's beers"):
        drinks.set_day(db, _today(), 2)
    with pytest.raises(ValueError, match="today's beers"):
        drinks.set_day(db, _today() + timedelta(days=1), 2)


def test_any_day_in_the_past_can_be_filled_in_however_old(db):
    """No cut-off (ADR-024): the date arrives from a calendar picker, so a
    slipped year is not the mistake a bound was guarding against, and a
    holiday remembered in November is a real thing to record."""
    last_year = _today() - timedelta(days=400)
    ages_ago = date(2019, 7, 20)

    assert drinks.set_day(db, last_year, 2).count == 2
    assert drinks.set_day(db, ages_ago, 6).count == 6

    # Each lands on its own day, and neither is anywhere near the counter.
    assert drinks.day_tally(db, last_year).count == 2
    assert drinks.day_tally(db, ages_ago).count == 6
    assert drinks.pending(db).count == 0


def test_the_day_list_ends_today_newest_first_with_the_empty_ones(db):
    drinks.set_day(db, _today() - timedelta(days=2), 2)

    history = drinks.day_history(db, 3)

    assert [(d.date, d.count) for d in history] == [
        (_today(), 0),
        (_today() - timedelta(days=1), 0),
        (_today() - timedelta(days=2), 2),
    ]


def test_the_day_list_carries_todays_beers_but_marks_them_the_counters(db):
    """Today is on the chart like any other day and inert in the editor: the
    evening in progress has one number, and it is the stepper's."""
    drinks.log_drink(db)

    history = drinks.day_history(db, 5)

    assert (history[0].date, history[0].count, history[0].editable) == (_today(), 1, False)
    assert all(day.editable for day in history[1:])
    assert drinks.pending(db).count == 1


def test_one_day_can_be_read_on_its_own_however_old(db):
    day = date(2020, 2, 29)
    drinks.set_day(db, day, 3)

    tally = drinks.day_tally(db, day)

    assert (tally.date, tally.count, tally.editable) == (day, 3, True)
    # A day with nothing on it is an answer, not a 404.
    assert drinks.day_tally(db, date(2020, 3, 1)).count == 0


def test_the_day_list_says_how_many_of_a_day_a_report_already_counted(db):
    day = _today() - timedelta(days=1)
    _log_on(db, day)
    report = _report(db, datetime.now(UTC))
    drinks.close_out(db, report)
    drinks.set_day(db, day, 3)

    listed = next(d for d in drinks.day_history(db, 3) if d.date == day)

    assert (listed.count, listed.reported) == (3, 1)


def test_a_beer_filled_in_for_a_day_outside_the_window_stays_outside_it(db):
    """`logged_at` is today for every backfilled row, so a window that read
    only that column would drag a beer from three weeks ago into this
    week's history under the wrong date."""
    drinks.set_day(db, _today() - timedelta(days=20), 2)

    assert drinks.daily_counts(db, _today() - timedelta(days=7)) == []
    assert [d.count for d in drinks.daily_counts(db, _today() - timedelta(days=30))] == [2]


# --- the /days endpoints ---------------------------------------------------


def test_the_day_list_round_trips_through_the_api(client):
    days = client.get("/drinks/days").json()

    assert len(days) == drinks.HISTORY_DAYS
    assert days[0] == {"date": _today().isoformat(), "count": 0, "reported": 0, "editable": False}
    assert days[1] == {
        "date": (_today() - timedelta(days=1)).isoformat(),
        "count": 0,
        "reported": 0,
        "editable": True,
    }


def test_filling_in_a_day_through_the_api_leaves_the_counter_alone(client):
    day = (_today() - timedelta(days=3)).isoformat()

    put = client.put(f"/drinks/days/{day}", json={"count": 3})

    assert put.status_code == 200
    assert put.json() == {"date": day, "count": 3, "reported": 0, "editable": True}
    assert client.get("/drinks").json()["count"] == 0
    assert next(d for d in client.get("/drinks/days").json() if d["date"] == day)["count"] == 3
    # And the same day read on its own, which is what the date picker asks.
    assert client.get(f"/drinks/days/{day}").json()["count"] == 3


def test_filling_in_a_day_twice_is_idempotent_over_the_api(client):
    day = (_today() - timedelta(days=3)).isoformat()

    assert client.put(f"/drinks/days/{day}", json={"count": 2}).json()["count"] == 2
    assert client.put(f"/drinks/days/{day}", json={"count": 2}).json()["count"] == 2


def test_the_api_refuses_what_it_cannot_honestly_store(client):
    today = _today().isoformat()
    day = (_today() - timedelta(days=2)).isoformat()

    # Today is the counter's, not a day to fill in.
    assert client.put(f"/drinks/days/{today}", json={"count": 1}).status_code == 422
    # The same slipped-finger guard as the counter, and the same 422 for a
    # date that is not one.
    assert client.put(f"/drinks/days/{day}", json={"count": 100}).status_code == 422
    assert client.put("/drinks/days/not-a-date", json={"count": 1}).status_code == 422
    assert client.get("/drinks/days").json()[2]["count"] == 0


def test_the_api_takes_a_day_from_years_ago(client):
    """No cut-off (ADR-024). The chart's own window is bounded; what may be
    written is not."""
    assert client.put("/drinks/days/2019-07-20", json={"count": 6}).json()["count"] == 6
    assert client.get("/drinks/days/2019-07-20").json() == {
        "date": "2019-07-20",
        "count": 6,
        "reported": 0,
        "editable": True,
    }
    assert client.get("/drinks").json()["count"] == 0


def test_the_day_list_window_is_bounded(client):
    """One response's worth of history, not a limit on what can be written:
    the sheet's chart asks for a year, and anything past two is a request
    nobody's screen has a use for."""
    assert len(client.get("/drinks/days", params={"days": 3}).json()) == 3
    assert len(client.get("/drinks/days", params={"days": 366}).json()) == 366
    assert client.get("/drinks/days", params={"days": 0}).status_code == 422
    assert client.get("/drinks/days", params={"days": drinks.MAX_HISTORY_DAYS + 1}).status_code == 422
