"""Tests for the shared Gemini day budget (ADR-013).

One bucket holds every request the process makes — report, New report,
coach message — because that is how Google counts them. The cases worth
pinning are the ones an earlier, chat-only counter got wrong: a report run
has to move the chat's remaining count, the reserve has to be a floor the
chat cannot cross, and a reply that fell through to the fallback model has
to cost the two requests it actually made.

The day boundary matters as much as the numbers. Google resets
requests-per-day at midnight Pacific; a counter keyed to any other midnight
rolls over mid-quota-day and lets two of its own days share one of Google's.

Ported from fitness-dashboard; the counts live in one Firestore document
per quota day, so the tests that spend run against the emulator.
"""

from __future__ import annotations

from datetime import UTC, date, datetime, timedelta
from zoneinfo import ZoneInfo

import pytest

from api.config import settings
from api.services import gemini_usage


@pytest.fixture(autouse=True)
def small_budget(monkeypatch):
    """Two models of three requests, reserving one — a six-request day with a
    chat ceiling of five, so a test can exhaust it in a few lines."""
    monkeypatch.setattr(settings, "gemini_model", "primary")
    monkeypatch.setattr(settings, "gemini_fallback_model", "fallback")
    monkeypatch.setattr(settings, "gemini_requests_per_day", 3)
    monkeypatch.setattr(settings, "gemini_report_reserve", 1)
    monkeypatch.setattr(settings, "coach_daily_message_limit", None)


def spend(store, model: str = "primary", times: int = 1) -> None:
    for _ in range(times):
        gemini_usage.record(store, model)


# --- the ceilings -----------------------------------------------------------


def test_the_total_is_every_configured_models_allowance():
    assert gemini_usage.total_limit() == 6


def test_the_chat_stops_short_of_the_total_by_the_reserve():
    assert gemini_usage.chat_limit() == 5


def test_dropping_the_fallback_model_drops_its_allowance_too(monkeypatch):
    monkeypatch.setattr(settings, "gemini_fallback_model", "")
    assert gemini_usage.total_limit() == 3
    assert gemini_usage.chat_limit() == 2


def test_a_fallback_equal_to_the_primary_is_not_counted_twice(monkeypatch):
    monkeypatch.setattr(settings, "gemini_fallback_model", "primary")
    assert gemini_usage.total_limit() == 3


def test_an_explicit_limit_overrides_the_chats_share(monkeypatch):
    monkeypatch.setattr(settings, "coach_daily_message_limit", 2)
    assert gemini_usage.chat_limit() == 2
    assert gemini_usage.total_limit() == 6


# --- one bucket -------------------------------------------------------------


def test_a_report_run_spends_the_same_bucket_the_chat_draws_on(store):
    """The whole point of merging them: a chat-only counter said "5 left"
    while the report was quietly spending the same allowance."""
    before = gemini_usage.snapshot(store).chat_remaining
    spend(store, "primary")
    assert gemini_usage.snapshot(store).chat_remaining == before - 1


def test_requests_are_counted_against_the_model_that_served_them(store):
    spend(store, "primary", times=2)
    spend(store, "fallback")

    per_model = {m.model: m.used for m in gemini_usage.snapshot(store).models}

    assert per_model == {"primary": 2, "fallback": 1}
    assert gemini_usage.snapshot(store).used == 3


def test_a_model_no_longer_configured_still_counts_toward_the_total(store, monkeypatch):
    """Google counted what it served this morning, whatever .env says now."""
    spend(store, "retired-model", times=2)
    usage = gemini_usage.snapshot(store)

    assert usage.used == 2
    assert "retired-model" not in {m.model for m in usage.models}


# --- the gates --------------------------------------------------------------


def test_the_chat_is_refused_at_its_ceiling_not_at_the_total(store):
    spend(store, "primary", times=5)  # chat ceiling, one short of the total

    with pytest.raises(gemini_usage.GeminiQuotaExceeded):
        gemini_usage.require_chat_budget(store)

    # The reserve is still there, and the report may have it.
    gemini_usage.require_report_budget(store)


def test_the_report_may_spend_the_reserve_the_chat_could_not(store):
    spend(store, "primary", times=5)
    gemini_usage.require_report_budget(store)  # the sixth is the report's

    spend(store, "fallback")
    with pytest.raises(gemini_usage.GeminiQuotaExceeded):
        gemini_usage.require_report_budget(store)


def test_a_zero_chat_limit_switches_the_chat_off_but_not_the_report(store, monkeypatch):
    monkeypatch.setattr(settings, "coach_daily_message_limit", 0)

    with pytest.raises(gemini_usage.GeminiQuotaExceeded):
        gemini_usage.require_chat_budget(store)
    gemini_usage.require_report_budget(store)


def test_the_budget_is_per_day_not_per_conversation(store, monkeypatch):
    """A per-conversation cap would protect nothing: reloading the tab would
    hand back a fresh allowance while Google's daily count kept climbing."""
    monkeypatch.setattr(gemini_usage, "quota_day", lambda: date(2026, 8, 25))
    spend(store, "primary", times=5)
    with pytest.raises(gemini_usage.GeminiQuotaExceeded):
        gemini_usage.require_chat_budget(store)

    monkeypatch.setattr(gemini_usage, "quota_day", lambda: date(2026, 8, 26))
    assert gemini_usage.snapshot(store).used == 0
    gemini_usage.require_chat_budget(store)


# --- the day boundary -------------------------------------------------------


def clock_pinned_to(instant: datetime) -> type[datetime]:
    """A stand-in for `datetime` whose `now(tz)` is always `instant`.

    The zone tests below have to name the instant they are asking about:
    which calendar dates two zones are on depends on the time of day, so
    reading the wall clock makes the answer change through the day.
    """

    class Pinned(datetime):
        @classmethod
        def now(cls, tz=None):  # type: ignore[override]
            return instant.astimezone(tz) if tz is not None else instant.replace(tzinfo=None)

    return Pinned


@pytest.mark.parametrize(
    ("instant", "expected_ahead", "expected_behind"),
    [
        # 10:00-11:00 UTC is the one hour a day when Kiritimati has already
        # rolled into tomorrow and Niue has not yet left yesterday, so the two
        # dates are *two* days apart. This case is first because an earlier
        # version of this test read the wall clock and asserted a difference of
        # exactly one day, which made it fail for that hour every day — CI
        # caught it on 2026-09-15 at 10:41 UTC.
        (datetime(2026, 9, 15, 10, 41, tzinfo=UTC), date(2026, 9, 16), date(2026, 9, 14)),
        # Any other hour, and they are one day apart.
        (datetime(2026, 9, 15, 12, 0, tzinfo=UTC), date(2026, 9, 16), date(2026, 9, 15)),
    ],
)
def test_the_day_key_follows_the_quota_timezone_not_the_users(
    monkeypatch, instant, expected_ahead, expected_behind
):
    """Two zones 25 hours apart are never on the same date, so this fails if
    the day is read from anything but gemini_quota_tz."""
    monkeypatch.setattr(gemini_usage, "datetime", clock_pinned_to(instant))

    monkeypatch.setattr(settings, "gemini_quota_tz", "Pacific/Kiritimati")  # UTC+14
    furthest_ahead = gemini_usage.quota_day()
    monkeypatch.setattr(settings, "gemini_quota_tz", "Pacific/Niue")  # UTC-11
    furthest_behind = gemini_usage.quota_day()

    assert (furthest_ahead, furthest_behind) == (expected_ahead, expected_behind)
    # The property the whole test exists for, and the one a quota_day() reading
    # anything but gemini_quota_tz would break: the zones are never on the same
    # date, whatever the hour.
    assert furthest_ahead > furthest_behind


def test_the_default_quota_day_is_googles_pacific_one():
    assert settings.gemini_quota_tz == "America/Los_Angeles"
    assert gemini_usage.quota_day() == datetime.now(ZoneInfo("America/Los_Angeles")).date()


def test_the_reset_is_the_next_midnight_in_that_zone():
    reset = gemini_usage.next_reset()
    local = reset.astimezone(gemini_usage.quota_tz())

    assert (local.hour, local.minute, local.second) == (0, 0, 0)
    assert local.date() == gemini_usage.quota_day() + timedelta(days=1)
    # Sent as an instant, so the browser can render it in its own clock time
    # rather than trusting a fixed hour that DST moves twice a year.
    assert reset.tzinfo is not None
    assert datetime.now(UTC) < reset <= datetime.now(UTC) + timedelta(days=1)
