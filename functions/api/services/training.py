"""api/services/training.py — assemble DayInputs for the training model.

Turns four tables (daily_health, the OEFB match log, calendar "Training"
events and skipped_activities) into the one-row-per-calendar-day shape
api/analysis/training_load.py expects. Days with no daily_health row are
materialized as rest days so a gap in the sync does not silently shorten
the averaging window.

**Deciding what the watch actually recorded happens here**, because it is
the one place that has both halves: the schedule — a training block, or a
match whose kick-off is read off the calendar's own fixture event — and
the individual tracked sessions parsed back out of `daily_health.raw`
(services/sessions.py). A scheduled session counts as recorded when a
tracked session starts inside its window or was already running at its
scheduled start — `analysis/training_load.covers` owns that rule, since
which sessions count decides what load exists. Anything the watch did not
cover keeps its estimate, so a morning walk no longer cancels the evening
training the way a day-level rule did (ADR-015, ADR-022).

skipped_activities subtracts: a match or training the user marked as
missed is dropped here rather than downstream, so the pure model never
sees minutes for a session that did not happen — not in the day's load,
and not in the observed AZM-per-minute rates it calibrates the fallback
with (services/skips.py, ADR-014).

Kept out of the router because the coach (api/analysis/coach.py) needs the
same numbers as the /training/status endpoint.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date, datetime, timedelta

from api.analysis.training_load import (
    MATCH,
    TRAINING,
    DayInput,
    ScheduledSession,
    TrainingStatus,
    compute_training_status,
    covers,
    observed_rates,
)
from api.config import settings
from api.integrations.google_health import EXERCISE_DATA_TYPE, local_tz
from api.services.sessions import ExerciseSession, placed_start, sessions_for_day
from api.services.skips import skipped_refs
from api.store.firestore import FirestoreStore
from api.store.like import ilike
from api.store.rows import CalendarEvent, DailyHealth, MatchPerformance

# How many days of the per-day series to *return*. Not a model window — the
# maths always runs over everything (see build_day_inputs). A year is what
# the dashboard's metric detail view plots at its longest setting.
DEFAULT_HISTORY_DAYS = 366


@dataclass(frozen=True)
class ScheduledActivity:
    """One match or training, with the coverage decision already made.

    The service-level counterpart of `training_load.ScheduledSession`: the
    model only needs kind, minutes and whether the watch recorded it, while
    the dashboard also needs to know *which* match it was and how to name
    it. Assembling both in one pass is what keeps the estimate on the card
    equal to the load in the chart.
    """

    kind: str
    # The natural key a skip is filed under — see services/skips.py.
    ref_id: str
    title: str
    day: date
    # For a training, the calendar block's start. For a match, the kick-off
    # off the calendar too — see `_match_kickoffs` — and None when that day
    # carries no fixture event to read it from.
    start_ts: datetime | None
    minutes: int
    covered: bool
    tracked_azm: float | None
    skipped: bool
    # The tracked session that *is* this one, when the watch recorded it —
    # the longest of the covering sessions. Display only: it links a match
    # in the ÖFB log to the workout behind it, and nothing the model counts
    # reads it. See `_tracked_session`.
    tracked_session_id: str | None = None
    # The ÖFB row, for a match: what the session detail shows beside the
    # watch's numbers. None for a training.
    match: MatchPerformance | None = None


@dataclass(frozen=True)
class EstimatedActivity:
    """A scheduled session nothing recorded, and the load it is worth.

    What `services/exercises.py` lists. `estimated_load` is filled in here
    rather than there because the rate belongs to the model, and a second
    derivation of it would be a second chance to print a number the Fitness
    chart does not contain. Skipped ones are included: the model has
    stopped counting them, but the dashboard still lists them so the skip
    can be undone, and `estimated_load` says what was forgone.
    """

    activity: ScheduledActivity
    estimated_load: float


def _day_sessions(row: DailyHealth | None) -> list[ExerciseSession]:
    if row is None:
        return []
    return sessions_for_day(row.date, row.raw.get(EXERCISE_DATA_TYPE))


def _coverage(
    start_ts: datetime | None,
    day_row: DailyHealth | None,
    day_sessions: list[ExerciseSession],
) -> tuple[bool, float | None]:
    """`(covered, tracked_azm)` for one scheduled session.

    Covered means the watch recorded this session, so the day's own Active
    Zone Minutes already carry it and no estimate may be added on top.
    `tracked_azm` is what those covering sessions scored, and is only ever
    used to keep the fallback rate calibrated — null when the covering
    session recorded no AZM at all (the 2026-08-23 swim did not).

    Three cases, in order:

    1. **A tracked session starts in the window, or was already running at
       the scheduled start.** That is the rule (ADR-015, extended by
       ADR-022 to the session that spans kick-off): it is the same event,
       whatever it was labelled.
    2. **Nothing is in the window, but the day holds a session that cannot
       be placed** — no usable `interval`, so no start time to compare
       against. Treated as covering the day, which is what the old
       day-level rule did: it might have been this very session, and adding
       a second helping of load on top of one already measured is the worse
       of the two mistakes.
    3. **A scheduled session with no time of its own** — a match whose day
       carries no "Spiel:" calendar event, or more than one. Nothing to
       window against, so it falls back to the day-level rule, which is
       exactly how everything behaved before ADR-015.
    """
    if start_ts is None:
        day_azm = day_row.active_zone_minutes if day_row else None
        return day_azm is not None, day_azm

    covering = [
        session
        for session in day_sessions
        if (start := placed_start(session)) is not None
        and covers(start_ts, start, session.end_ts)
    ]
    if covering:
        scores = [s.active_zone_minutes for s in covering if s.active_zone_minutes is not None]
        return True, sum(scores) if scores else None

    if any(placed_start(session) is None for session in day_sessions):
        return True, None

    return False, None


def _tracked_session(
    start_ts: datetime | None,
    covered: bool,
    day_sessions: list[ExerciseSession],
) -> str | None:
    """Which tracked session a scheduled one *was*, for display.

    Follows `_coverage` case by case, but answers a different question —
    not "is there load to estimate" but "which workout do I open" — and so
    is stricter where coverage is generous:

    1. Sessions in the window, or running at the scheduled start: the
       longest of them. A short warm-up tracked on its own and the match
       tracked after it both cover kick-off; the match is the long one.
    2. Unplaceable sessions covering the day: only when there is exactly
       one. Two could be anything.
    3. No scheduled time at all: the day-level rule covers a match with a
       morning walk, which is right for the load and wrong for "open the
       match". So only a single session recorded *as football* is taken.
    """
    if not covered:
        return None

    if start_ts is not None:
        covering = [
            session
            for session in day_sessions
            if (start := placed_start(session)) is not None
            and covers(start_ts, start, session.end_ts)
        ]
        if covering:
            return max(covering, key=lambda s: s.duration_minutes or 0.0).id
        unplaced = [session for session in day_sessions if placed_start(session) is None]
        return unplaced[0].id if len(unplaced) == 1 else None

    football = [session for session in day_sessions if is_football(session.exercise_type)]
    return football[0].id if len(football) == 1 else None


def is_football(exercise_type: str | None) -> bool:
    """Whether Google Health recorded the session as association football —
    "SOCCER" as confirmed live, "FOOTBALL" in case a later API spells it
    the other way."""
    return exercise_type is not None and any(
        word in exercise_type.upper() for word in ("SOCCER", "FOOTBALL")
    )


def _match_kickoffs(events: list[CalendarEvent], tz) -> dict[date, datetime]:
    """Kick-off time per match day, read off the calendar.

    The ÖFB match log records a *date* — the report carries the kick-off
    instant but the scrape only ever kept the day, and re-scraping the
    archive to recover it would be a lot of ceremony for something already
    sitting in the user's own calendar: every fixture is there as
    "Spiel: <home> - <away>", with its time (settings.calendar_match_title).

    Keyed by day, and only where the day holds exactly **one** such event.
    Two fixtures on one day cannot be told apart by date alone — the club
    names in the calendar title and in the ÖFB log do not agree closely
    enough to match on ("St. Martin 1b" vs "St. Martin i.M 1b",
    "Oberneukirchen 1b" vs "Oberneukirchen") — and a wrong kick-off is
    worse than none: none falls back to comparing whole days, which is
    merely coarse, while a wrong one would credit or cancel the wrong
    session.
    """
    by_day: dict[date, list[datetime]] = {}
    for event in events:
        if ilike(event.title, settings.calendar_match_title):
            by_day.setdefault(event.start_ts.astimezone(tz).date(), []).append(event.start_ts)
    return {day: starts[0] for day, starts in by_day.items() if len(starts) == 1}


def _read_activities(
    store: FirestoreStore, by_date: dict[date, DailyHealth], first_day: date, last_day: date
) -> list[ScheduledActivity]:
    """Every match and training between `first_day` and `last_day`, with
    coverage resolved against the tracked sessions of its own day.

    Bounded to the model's own span: a match older than the first health
    row falls on no day the model runs over, so an estimate for it would be
    load nothing can show.
    """
    skipped = skipped_refs(store)
    tz = local_tz()
    # Every dated event, in start order — what both the kick-off lookup and
    # the training scan below read, fetched once. Kick-offs come from the
    # whole calendar, not the model's span, as they did in Postgres.
    calendar = store.calendar_events()
    # Parsed lazily and once per day: only days that hold something
    # scheduled need their raw payload walked at all.
    parsed: dict[date, list[ExerciseSession]] = {}

    def sessions_on(day: date) -> list[ExerciseSession]:
        if day not in parsed:
            parsed[day] = _day_sessions(by_date.get(day))
        return parsed[day]

    activities: list[ScheduledActivity] = []
    kickoffs = _match_kickoffs(calendar, tz)

    for match in store.matches_between(first_day, last_day):
        day = match.match_date
        kickoff = kickoffs.get(day)
        covered, tracked_azm = _coverage(kickoff, by_date.get(day), sessions_on(day))
        activities.append(
            ScheduledActivity(
                kind=MATCH,
                tracked_session_id=_tracked_session(kickoff, covered, sessions_on(day)),
                match=match,
                # The opponent as the ÖFB log spells it, not as the calendar
                # event titles it: the log is the row this is actually about,
                # and the calendar is only being read for the clock.
                ref_id=match.oefb_game_id,
                title=f"{'vs' if match.home_away == 'home' else '@'} {match.opponent}",
                day=day,
                start_ts=kickoff,
                minutes=max(match.minutes_played, 0),
                covered=covered,
                tracked_azm=tracked_azm,
                skipped=(MATCH, match.oefb_game_id) in skipped,
            )
        )

    for event in calendar:
        if not ilike(event.title, settings.calendar_training_title):
            continue
        day = event.start_ts.astimezone(tz).date()
        if not first_day <= day <= last_day:
            continue
        covered, tracked_azm = _coverage(event.start_ts, by_date.get(day), sessions_on(day))
        activities.append(
            ScheduledActivity(
                kind=TRAINING,
                ref_id=event.id,
                title=event.title or "Training",
                day=day,
                start_ts=event.start_ts,
                minutes=settings.calendar_training_minutes,
                covered=covered,
                tracked_azm=tracked_azm,
                skipped=(TRAINING, event.id) in skipped,
            )
        )

    return activities


def _assemble(store: FirestoreStore) -> tuple[list[DayInput], bool, list[ScheduledActivity]]:
    """The one pass everything else reads: the day inputs, whether the last
    day is still filling up, and the schedule behind them."""
    today = date.today()

    health_rows = store.health_days()
    if not health_rows:
        return [], False, []

    by_date = {row.date: row for row in health_rows}
    start = health_rows[0].date
    end = max(health_rows[-1].date, today)

    activities = _read_activities(store, by_date, start, end)
    by_day: dict[date, list[ScheduledActivity]] = {}
    for activity in activities:
        # A skipped session is not on the day at all as far as the model is
        # concerned — see the module docstring.
        if not activity.skipped:
            by_day.setdefault(activity.day, []).append(activity)

    inputs: list[DayInput] = []
    cursor = start
    while cursor <= end:
        row = by_date.get(cursor)
        inputs.append(
            DayInput(
                day=cursor,
                active_zone_minutes=row.active_zone_minutes if row else None,
                resting_hr=row.resting_hr if row else None,
                hrv_ms=row.hrv_ms if row else None,
                sleep_minutes=row.sleep_minutes if row else None,
                scheduled=tuple(
                    ScheduledSession(
                        kind=a.kind,
                        minutes=a.minutes,
                        covered=a.covered,
                        tracked_azm=a.tracked_azm,
                    )
                    for a in by_day.get(cursor, ())
                ),
            )
        )
        cursor += timedelta(days=1)

    return inputs, end == today, activities


def build_day_inputs(store: FirestoreStore) -> tuple[list[DayInput], bool]:
    """Every day of history, oldest→newest, plus whether the last is partial.

    Deliberately takes no window. Fitness and Fatigue are state variables
    that have been evolving since the first tracked day, so they must not
    depend on how much of the chart someone happens to be looking at — and
    they did: measured live on 2026-08-21, the same day scored Fitness 41.6
    when 120 days were requested and 40.5 when 366 were, because the EWMA
    was seeded from the mean of whatever slice it got. The display window is
    applied afterwards, in get_training_status, and only to the series.
    """
    inputs, partial_last_day, _ = _assemble(store)
    return inputs, partial_last_day


def load_days(inputs: list[DayInput], partial_last_day: bool) -> list[DayInput]:
    """The days the model measures load over — the same trim
    `compute_training_status` makes internally, which is today dropped
    while it is still filling up."""
    return inputs[:-1] if partial_last_day and len(inputs) > 1 else inputs


@dataclass(frozen=True)
class Schedule:
    """Both halves of the one pass: every scheduled activity, and the ones
    among them the watch did not record, with what each is worth."""

    activities: list[ScheduledActivity]
    estimated: list[EstimatedActivity]


def schedule(store: FirestoreStore) -> Schedule:
    """Every scheduled session, plus the ones the watch did not record,
    newest first.

    The listing side of the same pass the model runs on, so the estimate
    shown on a card is the load the chart carries for that day — down to
    the rate, which comes from `observed_rates` over the same trimmed days
    `compute_training_status` uses. `activities` is there for the callers
    that link a match to its session, so they need not run the pass again.

    Future days are excluded because the model does not reach them; today
    is not, so a training this evening can be marked skipped before it is
    missed rather than the morning after.
    """
    inputs, partial_last_day, activities = _assemble(store)
    if not inputs:
        return Schedule(activities=[], estimated=[])

    match_rate, training_rate = observed_rates(load_days(inputs, partial_last_day))
    rates = {MATCH: match_rate, TRAINING: training_rate}

    estimated = [
        EstimatedActivity(
            activity=activity,
            estimated_load=round(activity.minutes * rates[activity.kind], 2),
        )
        # A match spent on the bench adds no minutes and so no load; listing
        # it would be an entry that explains nothing.
        for activity in activities
        if not activity.covered and activity.minutes > 0
    ]
    estimated.sort(key=lambda e: (e.activity.day, e.activity.start_ts is not None), reverse=True)
    return Schedule(activities=activities, estimated=estimated)


def scheduled_sessions(store: FirestoreStore) -> list[EstimatedActivity]:
    """Every scheduled session the watch did not record, newest first —
    `schedule(store).estimated`."""
    return schedule(store).estimated


def get_training_status(store: FirestoreStore, days: int = DEFAULT_HISTORY_DAYS) -> TrainingStatus:
    """`days` trims what is *plotted*, never what is computed.

    Every number on the status is worked out over the full history above;
    this only shortens the two per-day series so the response does not carry
    years of points the dashboard will not draw. Changing `days` therefore
    cannot change Fitness, Fatigue, Form or the scores — which is the whole
    point, and is pinned by a test.
    """
    inputs, partial_last_day = build_day_inputs(store)
    if not inputs:
        return compute_training_status([])

    status = compute_training_status(inputs, partial_last_day=partial_last_day)
    status.series = status.series[-days:]
    status.scores = status.scores[-days:]
    return status
