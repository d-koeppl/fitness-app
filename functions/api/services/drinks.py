"""api/services/drinks.py — the beer counter (ADR-019).

The one number in this app the user types in themselves. Everything else
arrives from a watch, a calendar or a scrape; alcohol has no sensor, so it
is a tile on the Today tab — tap up, tap down, or type the number — and a
row per drink here.

Two rules the whole module exists to hold:

- **The count is the pending rows.** A drink is "pending" until an AI
  report claims it (`counted_report_id`). Nothing is ever subtracted from
  a stored total — minus one deletes the last tap, which is what makes a
  mis-tap undoable and keeps the history honest.
- **A drink remembered late is history, not a counter entry.** A row with
  `drank_on` set names the local day it is about and is never pending and
  never claimed (ADR-023): the counter stays "the evening in progress",
  while the forgotten beer lands on its own day in the history below —
  which is the part later analysis reads.
- **The reset is the *first* report of a local day.** Not every report:
  generating a second one at 22:00 must not zero an evening that is still
  going on, or the drinks after it would be reported tomorrow as if they
  were the whole night. `close_out` is therefore called with that decision
  already made — see api/analysis/gemini.py::run_analysis, which asks
  services/reports.py before it writes the new row.

Which day a report counts as the first *of* is decided in
services/reports.py, against `wake_fallback_tz` — the zone the end-of-day
fallback is scheduled in, because "the first report today" has to mean the
same thing to both. The per-day history below is keyed by
`health_local_tz` instead, like every other daily number the report shows.
"""

from __future__ import annotations

from collections import Counter
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta
from zoneinfo import ZoneInfo

from api.integrations.google_health import local_tz
from api.store.firestore import FirestoreStore
from api.store.rows import AiReport, DrinkLog

# What one tap is. A constant rather than a setting: the button says "0.5 L
# beer" on it, and a stored row means nothing without knowing what it was
# a row of. If a second size is ever tracked it belongs on the row, not
# here (and the rows written until then still mean this).
DRINK_VOLUME_L = 0.5
# 0.5 L of ~5 % ABV beer ≈ 19.7 g of ethanol. Rounded, and passed to Gemini
# rather than left implicit, so the model reasons about the dose instead of
# a bare count whose size it has to guess.
DRINK_ALCOHOL_GRAMS = 20

# How long a day list may be. A bound on the size of one response, not on
# how far back a beer may be filled in: any past day can be written
# (ADR-024), and this is only how much history one request will hand back.
# Two years matches the coach's deepest lookback, which is the furthest
# anything else here reaches.
MAX_HISTORY_DAYS = 730

# What a day list covers unless the caller says otherwise. The same
# fortnight the daily report reads (CONTEXT_HEALTH_DAYS_BACK); the chart in
# the Beer sheet asks for a year instead, because that is its widest period.
HISTORY_DAYS = 14


@dataclass(frozen=True)
class PendingDrinks:
    """What the stepper shows: the drinks since the last reset."""

    count: int
    first_logged_at: datetime | None
    last_logged_at: datetime | None


@dataclass(frozen=True)
class DayCount:
    """One local day's tally, for the report and the coach."""

    date: date
    count: int


@dataclass(frozen=True)
class DayTally:
    """One past local day, as the "earlier days" editor sees it (ADR-023).

    `count` is the whole day: taps logged at the time and drinks entered
    after the fact, together. `reported` is how many of those an AI report
    already counted — the floor a correction cannot go below, because a
    report describing four beers must not be left standing next to a
    history that holds two. It is the same restraint that keeps the
    stepper's minus off a counted drink, sent to the client so the editor
    can stop a request it knows will be refused.

    `editable` is false for one day only: today, whose beers belong to the
    counter. It is the server's answer rather than a date the client
    compares against its own clock, because the day boundary here is
    `health_local_tz` and the browser may be somewhere else entirely — the
    one mistake a feature about filing beers under the right day cannot
    afford (ADR-024).
    """

    date: date
    count: int
    reported: int
    editable: bool


def _day_of(row: DrinkLog, tz: ZoneInfo) -> date:
    """Which local day a row belongs to: the day it says it is about, or —
    for a row logged as it happened — the day its clock reading falls on.
    The single definition of that question; every grouping and window in
    this module goes through it."""
    return row.drank_on or row.logged_at.astimezone(tz).date()


def _oldest_first(rows: list[DrinkLog]) -> list[DrinkLog]:
    return sorted(rows, key=lambda row: (row.logged_at, row.id))


def _rows_since(store: FirestoreStore, since: date, tz: ZoneInfo) -> list[DrinkLog]:
    """Every row whose local day is `since` or later, oldest logged first.

    Two queries, because the two kinds of row carry their day differently
    (see `_day_of`). Windowing on `logged_at` alone would let a beer typed
    in tonight *for a day before the window* through, and then file it
    under a date the caller never asked about.
    """
    return _oldest_first(
        store.drinks_logged_between(datetime.combine(since, time.min, tzinfo=tz))
        + store.drinks_drank_between(since)
    )


def _rows_on(store: FirestoreStore, day: date, tz: ZoneInfo) -> list[DrinkLog]:
    """One local day's rows, oldest logged first. `_rows_since` closed at
    both ends — local midnight to local midnight, so a 23:30 beer is that
    day's and a 00:30 one belongs to the next, which is what the per-day
    history has always said."""
    start = datetime.combine(day, time.min, tzinfo=tz)
    return _oldest_first(
        store.drinks_logged_between(start, start + timedelta(days=1)) + store.drinks_drank_between(day, day)
    )


def _pending_rows(store: FirestoreStore) -> list[DrinkLog]:
    """The counter's rows, oldest first — so the ends are the ends and the
    last one is what a minus tap removes.

    Both halves of "pending": no report has claimed it, *and* it was logged
    as it happened. A drink entered after the fact was never on the stepper
    (ADR-023), so there is nothing there to take back, to overwrite, or for
    a report to claim.
    """
    return store.pending_drinks()


def pending(store: FirestoreStore) -> PendingDrinks:
    """The current counter — the pending rows, first and last included."""
    rows = _pending_rows(store)
    if not rows:
        return PendingDrinks(count=0, first_logged_at=None, last_logged_at=None)
    return PendingDrinks(
        count=len(rows), first_logged_at=rows[0].logged_at, last_logged_at=rows[-1].logged_at
    )


def log_drink(store: FirestoreStore) -> PendingDrinks:
    """Plus one. `logged_at` is the function's clock, the same one the
    report writer stamps `created_at` with, so a drink can never sort
    itself onto the wrong side of the report that claimed it."""
    store.add_drinks(1)
    return pending(store)


def remove_last(store: FirestoreStore) -> PendingDrinks:
    """Minus one: delete the most recent *pending* tap.

    Only pending rows — a drink an earlier report already counted is part
    of that report's evening and taking it back would leave the report
    describing a number the history no longer holds.

    A no-op when the counter is at zero rather than an error. The stepper
    disables its minus there anyway, and the count that comes back is the
    whole answer either way.
    """
    rows = _pending_rows(store)
    if rows:
        store.delete_drinks([rows[-1].id])
    return pending(store)


def set_count(store: FirestoreStore, count: int) -> PendingDrinks:
    """Make the counter read `count` — the number typed into the tile.

    Reconciles rather than rewrites: the difference is added at the database
    clock, or deleted off the newest end. A drink an earlier report already
    counted is never touched, and the times on the rows that stay are the
    times they were actually logged at.

    Several rows added at once share a timestamp, which is honest — they were
    entered in one go, and nothing here claims to know when each was drunk.
    `id` breaks the tie wherever order matters.

    This is the counter, so it is about the evening in progress: the
    difference lands on rows with no `drank_on`, and a day the user is
    filling in after the fact is `set_day`'s business instead.
    """
    rows = _pending_rows(store)
    if count > len(rows):
        store.add_drinks(count - len(rows))
    else:
        store.delete_drinks([row.id for row in rows[count:]])
    return pending(store)


def close_out(store: FirestoreStore, report: AiReport) -> int:
    """Store `report` and claim every pending drink for it — the reset.

    Called only for the first report of a local day (ADR-019); the caller
    owns that decision, because it has to be taken *before* the new report
    exists. Returns how many drinks were claimed, which is the number that
    report was written about.

    One Firestore batch, as it was one transaction in Postgres: a report
    that fails to save must not have reset the counter.
    """
    rows = _pending_rows(store)
    store.put_report(report, claim_drink_ids=[row.id for row in rows])
    return len(rows)


def daily_counts(store: FirestoreStore, since: date) -> list[DayCount]:
    """Drinks per local day from `since` onwards, oldest first, days with
    none omitted.

    Windowed in SQL, grouped in Python: the day is the *user's* local one,
    and a `GROUP BY` would have to carry the timezone conversion into every
    caller's query to agree with it. This is tens of rows for one person.
    Counted rows are included — the history is the point here, not the
    counter. So are the drinks entered after the fact, on the day they are
    about rather than the day they were typed (ADR-023): filing a forgotten
    round under the evening it happened in is the entire reason it can be
    entered at all.
    """
    tz = local_tz()
    tally: Counter[date] = Counter(_day_of(row, tz) for row in _rows_since(store, since, tz))
    return [DayCount(date=day, count=tally[day]) for day in sorted(tally)]


def _tally(day: date, rows: list[DrinkLog], today: date) -> DayTally:
    return DayTally(
        date=day,
        count=len(rows),
        reported=sum(1 for row in rows if row.counted_report_id is not None),
        editable=day < today,
    )


def day_history(store: FirestoreStore, days: int = HISTORY_DAYS) -> list[DayTally]:
    """The last `days` local days ending today, newest first, empty days
    kept.

    Empty days are kept, which is the opposite of `daily_counts`: a day with
    nothing on it is exactly the day a forgotten beer has to be added to, so
    it needs a row to tap — and on a chart a dry day is a real zero, not a
    gap (ADR-024).

    Today is in the list, marked `editable=False`. It is there because the
    chart plots it like any other day, and inert because that evening is the
    counter's — one night with two numbers on it is how a beer gets logged
    twice.
    """
    if days < 1:
        return []
    tz = local_tz()
    today = datetime.now(tz).date()
    wanted = [today - timedelta(days=offset) for offset in range(days)]
    grouped: dict[date, list[DrinkLog]] = {}
    for row in _rows_since(store, wanted[-1], tz):
        grouped.setdefault(_day_of(row, tz), []).append(row)
    return [_tally(day, grouped.get(day, []), today) for day in wanted]


def day_tally(store: FirestoreStore, day: date) -> DayTally:
    """One local day, however far back — what the date picker reads before
    it offers a number to change (ADR-024).

    A day with nothing on it answers zero rather than 404: "no beers that
    day" is an answer, and it is the one the picker needs in order to open
    on the right number.
    """
    tz = local_tz()
    return _tally(day, _rows_on(store, day, tz), datetime.now(tz).date())


def set_day(store: FirestoreStore, day: date, count: int) -> DayTally:
    """Make a past local day hold `count` beers — the round remembered
    three days late (ADR-023).

    A count rather than a delta, for the same reason `PUT /drinks` is: it
    says what the day should read, so a request replayed by a flaky
    connection cannot add a beer, and a correction ("it was five, not
    two") comes in through the same door as a first entry.

    Reconciles, and only with the rows it is allowed to touch. The
    difference is added as rows stamped with `day` — off the counter from
    the moment they are written, so tonight's stepper does not move and
    tomorrow's report will not claim them as its evening — or deleted from
    the newest end of what that day still has pending. Drinks an earlier
    report counted are never deleted; asking for fewer than those raises
    `ValueError` rather than quietly landing on a number nobody asked for.

    Today and later are the only dates refused: today's beers belong on the
    stepper, one tap away, and tomorrow has not happened. **Any** past day
    is allowed, however old (ADR-024) — the date comes from a calendar
    picker rather than a typed number, so a slipped year is no longer the
    likely mistake a cut-off was guarding against, and a holiday remembered
    in November is a real thing to want to record.
    """
    tz = local_tz()
    today = datetime.now(tz).date()
    if day >= today:
        raise ValueError("Only a day before today can be filled in — today's beers go on the counter")

    rows = _rows_on(store, day, tz)
    reported = sum(1 for row in rows if row.counted_report_id is not None)
    if count < reported:
        raise ValueError(
            f"A report already counted {reported} beer(s) on that day, so it cannot go below that"
        )

    if count > len(rows):
        # `logged_at` stays the clock — the moment this was typed, which is
        # the only time here anyone actually knows. `drank_on` carries the
        # evening it is about.
        store.add_drinks(count - len(rows), drank_on=day)
    else:
        # The newest end first, and only what no report has claimed: the
        # same end, and the same restraint, as the stepper's minus.
        removable = [row for row in reversed(rows) if row.counted_report_id is None]
        store.delete_drinks([row.id for row in removable[: len(rows) - count]])
    return _tally(day, _rows_on(store, day, tz), today)
