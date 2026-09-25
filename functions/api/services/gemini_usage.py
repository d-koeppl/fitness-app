"""api/services/gemini_usage.py — one bucket for everything we send Gemini.

The daily report, the dashboard's New report button and every coach
message are all `generateContent` calls against one free-tier key, so they
are all counted here.

The day's allowance is per model, because that is how Google counts it: two
configured models are two budgets of GEMINI_REQUESTS_PER_DAY, and the
fallback exists precisely to spend the second one.

Two ceilings sit on the one bucket:

- the chat stops GEMINI_REPORT_RESERVE short of the total, so the report
  always has somewhere to go;
- the report stops at the total, because past that Google would refuse it
  anyway — better to fail here, fast, with a sentence that says why.

`record` is the only writer and is called from the one place a request
actually leaves the process (api/analysis/gemini.py). Everything else here
reads. The count is one Firestore document per quota day, `requests.<model>`
incremented in place (ADR-031), so two instances counting at once cannot
lose a request.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import UTC, date, datetime, time, timedelta
from zoneinfo import ZoneInfo

from api.config import settings
from api.integrations import gemini_models
from api.store.firestore import FirestoreStore


class GeminiQuotaExceeded(RuntimeError):
    """The day's budget is spent. Raised instead of making the request."""


@dataclass(frozen=True)
class ModelUsage:
    model: str
    used: int
    limit: int


@dataclass(frozen=True)
class Usage:
    """What the coach tab renders, and what the ceilings are checked against."""

    used: int
    limit: int
    chat_remaining: int
    resets_at: datetime
    models: list[ModelUsage]


# --- the quota day ----------------------------------------------------------


def quota_tz() -> ZoneInfo:
    return ZoneInfo(settings.gemini_quota_tz)


def quota_day() -> date:
    """The day Google's requests-per-day counter is on right now.

    Pacific, not local: a counter keyed to the user's midnight would roll
    over mid-quota-day, and the second half of one local evening plus the
    first half of the next could both spend the same allowance.
    """
    return datetime.now(quota_tz()).date()


def next_reset() -> datetime:
    """When the current quota day ends, in UTC.

    Handed to the client rather than a fixed hour because midnight Pacific
    lands on a different local clock time either side of a DST change — on
    both sides of the Atlantic, on different dates.
    """
    tomorrow = quota_day() + timedelta(days=1)
    return datetime.combine(tomorrow, time.min, tzinfo=quota_tz()).astimezone(UTC)


# --- the ceilings -----------------------------------------------------------


def total_limit() -> int:
    """Every configured model's allowance. The report may spend all of it."""
    return len(gemini_models.candidates()) * settings.gemini_requests_per_day


def chat_limit() -> int:
    """What the coach chat may take of the total, holding back the reserve."""
    if settings.coach_daily_message_limit is not None:
        return settings.coach_daily_message_limit
    return max(total_limit() - settings.gemini_report_reserve, 0)


# --- reading ----------------------------------------------------------------


def snapshot(store: FirestoreStore) -> Usage:
    spent = store.gemini_usage(quota_day())
    per_model = settings.gemini_requests_per_day
    models = [
        ModelUsage(model=name, used=spent.get(name, 0), limit=per_model)
        for name in gemini_models.candidates()
    ]
    # Models no longer configured may still hold counts from earlier today,
    # and Google counted those — so they belong in the total even though
    # nothing will spend against them again.
    used = sum(spent.values())
    return Usage(
        used=used,
        limit=total_limit(),
        chat_remaining=max(chat_limit() - used, 0),
        resets_at=next_reset(),
        models=models,
    )


# --- the gates --------------------------------------------------------------
#
# Read-then-act rather than a transaction. One user, and the failure it
# allows — two requests at the same instant going one over — costs one
# request out of a reserve that exists to absorb exactly that.


def require_chat_budget(store: FirestoreStore) -> None:
    limit = chat_limit()
    if limit <= 0:
        raise GeminiQuotaExceeded("The coach chat is switched off (COACH_DAILY_MESSAGE_LIMIT is 0).")
    used = sum(store.gemini_usage(quota_day()).values())
    if used >= limit:
        raise GeminiQuotaExceeded(
            f"That's {limit} of today's {total_limit()} Gemini requests used — "
            "the rest is held for the daily report."
        )


def require_report_budget(store: FirestoreStore) -> None:
    limit = total_limit()
    if sum(store.gemini_usage(quota_day()).values()) >= limit:
        raise GeminiQuotaExceeded(
            f"All {limit} of today's Gemini requests are spent across "
            f"{len(gemini_models.candidates())} model(s); Google would refuse this too."
        )


# --- writing ----------------------------------------------------------------


def record(store: FirestoreStore, model: str) -> None:
    """Count one request against `model` for today.

    Written straight away, whatever the caller does next: a request that
    failed still reached Google and still counted there.
    """
    store.count_gemini_request(quota_day(), model)
