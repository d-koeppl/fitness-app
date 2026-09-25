"""api/analysis/training_load.py — Fitness / Fatigue / Form from daily load.

Banister's impulse-response model. An exponentially weighted average of
daily load with a long time constant is "Fitness" (CTL), the same with a
short one is "Fatigue" (ATL), and their difference is "Form" (TSB):

    CTL_today = CTL_yesterday + (load_today - CTL_yesterday) * alpha
    alpha     = 1 - exp(-1 / tau)      tau = 42 (CTL), 7 (ATL)
    Form      = CTL - ATL

Two things this gets right that the first implementation did not, both
recorded in ADR-011:

- **alpha is the exact `1 - exp(-1/tau)`**, not the `1/tau` shorthand. That
  approximation is 1.20% off at tau=42 and 7.31% off at tau=7, and the
  short one is Fatigue.
- **The model runs over the full history, seeded at zero.** It used to be
  seeded from the mean of whatever slice was requested, which let the
  requested history length change the answer — measured live on
  2026-08-21, the same day scored Fitness 41.6 over 120 days and 40.5 over
  366. `services/training.py` now feeds every day it has and trims only
  what is displayed.

"42-day rolling average" is the usual shorthand for CTL in sports software,
but it is only shorthand: the weighting decays smoothly instead of cutting
off, so a hard session fades rather than dropping out of a window on day 43
and putting a step in Form. See `_ewma`.

WHAT THE LOAD NUMBER ACTUALLY IS:

Daily load is the day's total Active Zone Minutes (AZM) — Fitbit/Google's
own HR-zone-weighted cardio metric (1 point/min in the moderate zone, 2
points/min in vigorous+peak), summed across every exercise session the
watch tracked that day (see integrations/google_health.py). Unlike the
step-count proxy this replaced, AZM is a real heart-rate-based measure of
cardio strain and a standardized one (it's the same unit the WHO's ~150
min/week moderate-activity guideline is expressed in), so a Fitness value
of ~21/day roughly means "meeting WHO guidelines on average."

Fitbit's own proprietary "Cardio Load" score (the one shown in the Fitbit
app) is NOT available through the Google Health API — confirmed by
probing ~20 plausible data-type ids live (all 400 INVALID_ARGUMENT) and
checking the exercise data point's fields directly. AZM is the closest
real substitute the API exposes.

A scheduled session the watch did not record falls back to a flat
estimate from the schedule: logged ÖFB match minutes, or a calendar
"Training" event (these run a fixed 90 minutes on the pitch, per the
user, even though the calendar block itself is padded to 3 hours — see
routers/training.py). This way an untracked session still registers
*some* load instead of reading as a rest day.

**Whether the watch recorded it is decided per session, not per day**, and
the estimate is *added to* the day's tracked total rather than replacing
it. A scheduled session counts as recorded when a tracked session starts
inside its window — from COVER_BEFORE_MINUTES before the scheduled start
to COVER_AFTER_MINUTES after it — or when a tracked session was already
running at the scheduled start, i.e. its interval spans it (see `covers`,
and ADR-022 for the match warm-up case that motivated the second rule).
Nothing matching either means nothing recorded it, whatever else the day
held.

This replaces a day-level rule, and the day-level rule was wrong in the
ordinary case: a morning walk or an afternoon swim is a *different*
session, and under the old rule either of them silently cancelled the
estimate for an untracked evening training — the day then scored 3 AZM
for the walk and nothing for the 90 minutes on the pitch. See ADR-015.

Double-counting is what the window exists to prevent, and it is the
failure to watch for: a session that is both worn through and on the
schedule must be counted once, as the AZM the watch measured. That is why
coverage is decided on session *times* rather than on activity type — a
name can be anything, but a session that began near kick-off, or was
already running at it, is the same event.

Matches and training use *different* fallback rates, and each rate is
not a fixed constant but the mean AZM/minute of that type's most recent
RATE_WINDOW (5) *recorded* sessions — see `_observed_rate()`. Recorded
sessions, not recorded days: since a day can now hold both a tracked walk
and a tracked training, dividing a whole day's AZM by the training's
minutes would charge the walk to the training's rate. This recalibrates
automatically as more sessions get tracked instead of going stale.
Confirmed to matter, not just a hunch: 5 tracked training sessions
(2026-08-04 through 2026-08-18, one contaminated tennis-instead-of-
training day on 2026-08-03 excluded) average ~1.13 AZM/min, while the
one tracked match so far (2026-08-08 vs Treffling, 224 AZM of pure
SOCCER over 90 minutes played) comes out to ~2.49 AZM/min — competitive
play runs noticeably hotter than practice, as you'd expect. Until a
type has *any* tracked days, its rate falls back to a hardcoded bootstrap
default (the numbers above, frozen at the time this was written).

A scheduled session that was *missed* — ill, or no time — never reaches
this module as a session at all: services/training.py drops its minutes
before the day is built, so a skipped match arrives here as the rest day
it actually was, and its minutes are also kept out of the observed rates
above (a match that was not played says nothing about AZM per minute).
See ADR-014.

Form is read on the standard absolute TSB bands (see the FORM_* constants),
not as a percentage of Fitness. ADR-009 assumed the ±25 bands "assume CTL
values in the hundreds and do not transfer here" — measured rather than
assumed, this user's 42-day mean load is around 55 AZM/day, the same range
the bands were written for, so they do transfer. `form_pct` is still
reported as a secondary readout.
"""

from __future__ import annotations

import math
from collections.abc import Sequence
from dataclasses import asdict, dataclass, field
from datetime import date, datetime, timedelta

# Impulse-response time constants (tau), in days — the standard 42/7 split.
# These are decay constants, not window lengths: see _ewma.
CTL_DAYS = 42
ATL_DAYS = 7
# Window for the HRV / resting-HR baselines the recovery score compares against.
BASELINE_DAYS = 28
# "Right now" is a 3-day mean — HRV is far too noisy to read one night of it.
# Used for the steadier trend score (TrainingStatus.recovery, the Fitness
# tab). See READINESS_WINDOW below for the reactive day-to-day one.
CURRENT_WINDOW = 3
# Readiness ("how did I recover last night") deliberately does NOT use
# CURRENT_WINDOW: a 3-day mean stays elevated for two extra days after one
# outlier night. Confirmed live on 2026-08-21: a 110.7ms HRV reading from
# two nights before was still propping the 3-day score to 99 on an
# otherwise unremarkable day (that night's own HRV was ~73ms, roughly at
# baseline) — Google Health's own Tagesform Index scored the same day 69,
# reacting to the latest night specifically rather than smoothing.
READINESS_WINDOW = 1
# How many days of history we need before the numbers mean anything.
MIN_HISTORY_DAYS = 14

# Untracked-day fallback rates are normally computed live from recent
# tracked days (see _observed_rate) — these are only the bootstrap
# defaults used until a type has any tracked days at all. See module
# docstring for how they were originally calibrated.
DEFAULT_TRAINING_FALLBACK_LOAD_PER_MINUTE = 1.13
DEFAULT_MATCH_FALLBACK_LOAD_PER_MINUTE = 2.49
# How many of the most recent tracked days of a type (match or training)
# to average for that type's live fallback rate.
RATE_WINDOW = 5
SLEEP_TARGET_MIN = 480.0

# How close a tracked session has to start to a scheduled one before it
# counts as *being* that session, so no estimate is added on top of it.
#
# Asymmetric on purpose, and the asymmetry is the point. A watch is started
# on arrival, which is early — the calendar block itself is padded half an
# hour at the front for exactly that reason (see settings.calendar_training_
# minutes) — but it is never started long before. Afterwards the spread is
# much wider: the session runs 90 minutes, and a watch started at the warm-up
# and one started at kick-off are two hours apart by the end of it.
#
# Chosen with the user, who knows their own routine, rather than fitted to
# anything: 30 minutes before, 2 hours after the scheduled start.
COVER_BEFORE_MINUTES = 30
COVER_AFTER_MINUTES = 120


# The two kinds of session the schedule knows about. Same spellings
# services/skips.py files a skip under — they are one vocabulary.
MATCH = "match"
TRAINING = "training"


def covers(
    scheduled_start: datetime,
    session_start: datetime,
    session_end: datetime | None = None,
) -> bool:
    """Whether a tracked session is the scheduled session that was due at
    `scheduled_start`.

    Pure, and deliberately living here with the rest of the model's
    constants rather than in the service that applies it: which sessions
    count as recorded decides what load exists, so it is a modelling rule,
    not an assembly detail.

    Two ways a tracked session counts as that event:

    1. **It starts in the window** — from COVER_BEFORE_MINUTES before the
       scheduled start to COVER_AFTER_MINUTES after it. This is the original
       rule (ADR-015): a watch goes on at arrival, which is shortly before,
       and can be started anywhere up to two hours into a 90-minute session.
    2. **It was already running at the scheduled start** — the session's
       interval contains `scheduled_start`. A session worn through kick-off
       and still going *is* that match whatever time the watch was started,
       and the window alone misses it when the watch went on early for a
       long warm-up: measured 2026-09-06, a match tracked as SOCCER 15:22–
       17:52 against a 16:00 kick-off, the watch started 8 minutes before
       the 30-minute window opened and the match was double-counted. See
       ADR-022.

    `scheduled_start` and `session_start` must be timezone-aware. The caller
    has the timestamps from Google (RFC-3339 with an offset) and from
    Postgres (`timestamptz`), so they always are; a naive one is a parsing
    accident and raises here rather than comparing wrongly. `session_end` is
    a best-effort extra signal — ignored when absent or naive rather than
    raising, since the window check stands on its own.
    """
    if (
        scheduled_start - timedelta(minutes=COVER_BEFORE_MINUTES)
        <= session_start
        <= scheduled_start + timedelta(minutes=COVER_AFTER_MINUTES)
    ):
        return True
    if session_end is not None and session_end.tzinfo is not None:
        return session_start <= scheduled_start <= session_end
    return False


@dataclass(frozen=True)
class ScheduledSession:
    """One match or training the schedule says happened, and what the
    watch recorded of it.

    `covered` is the whole question: false means nothing the watch tracked
    lines up with this session, so its load has to be estimated from
    `minutes`. `tracked_azm` is the AZM of the sessions that did line up —
    used only to keep the fallback rate calibrated, and null when the
    covering session recorded no AZM of its own (a real case: the
    2026-08-23 swim recorded none).

    Both are decided upstream, in services/training.py, because deciding
    them needs the day's tracked session times and this module has no I/O.
    """

    kind: str
    minutes: int
    covered: bool = False
    tracked_azm: float | None = None


@dataclass(frozen=True)
class DayInput:
    day: date
    active_zone_minutes: float | None = None
    resting_hr: int | None = None
    hrv_ms: float | None = None
    sleep_minutes: int | None = None
    # Every match and training the schedule puts on this day, whether or
    # not the watch recorded them. A tuple so DayInput stays hashable and
    # frozen all the way down.
    scheduled: tuple[ScheduledSession, ...] = ()


@dataclass
class DayPoint:
    date: str
    load: float
    fitness: float
    fatigue: float


@dataclass
class ScorePoint:
    """Recovery and readiness as of one day.

    Deliberately a separate series from DayPoint rather than two more fields
    on it. The two are measured through different days: load stops at
    yesterday while today is still filling up, but last night's HRV, resting
    HR and sleep are already complete, so a score exists for today when a
    load does not. Keeping them apart lets each series end where its data
    actually ends instead of forcing one of them to lie or go null.
    """

    date: str
    recovery: int | None
    readiness: int | None


@dataclass
class TrainingStatus:
    status: str
    headline: str
    fitness: float
    fatigue: float
    form: float
    # Kept as a secondary readout only. Form is classified on its raw value
    # now (see the FORM_* bands), because that is what the TSB scale is
    # defined on.
    form_pct: float
    ramp_pct: float
    recovery: int | None
    recovery_parts: dict[str, float] = field(default_factory=dict)
    readiness: int | None = None
    readiness_parts: dict[str, float] = field(default_factory=dict)
    days_of_history: int = 0
    series: list[DayPoint] = field(default_factory=list)
    scores: list[ScorePoint] = field(default_factory=list)
    notes: list[str] = field(default_factory=list)

    def to_dict(self) -> dict:
        return asdict(self)


def daily_load(
    active_zone_minutes: float | None,
    scheduled: Sequence[ScheduledSession] = (),
    match_rate: float = DEFAULT_MATCH_FALLBACK_LOAD_PER_MINUTE,
    training_rate: float = DEFAULT_TRAINING_FALLBACK_LOAD_PER_MINUTE,
) -> float:
    """Training load in Active Zone Minutes for one day. See module docstring.

    What the watch measured, **plus** an estimate for each scheduled
    session it did not record. Added, not chosen between: a morning walk
    and an untracked evening training are two sessions, and the day cost
    both. A covered session contributes nothing here because its AZM is
    already inside `active_zone_minutes` — that is what stops the estimate
    being charged twice.

    `match_rate` / `training_rate` are normally the live `_observed_rate()`
    values computed once per `compute_training_status()` call — the
    defaults here only matter when calling this directly.
    """
    load = active_zone_minutes if active_zone_minutes is not None else 0.0
    for item in scheduled:
        if item.covered:
            continue
        rate = match_rate if item.kind == MATCH else training_rate
        load += max(item.minutes, 0) * rate
    return round(load, 2)


def _observed_rate(days: list[DayInput], kind: str, default: float, window: int = RATE_WINDOW) -> float:
    """Mean AZM/minute over the most recent `window` recorded sessions of
    one kind (MATCH or TRAINING).

    Only sessions the watch actually covered can say anything about a rate,
    and only the AZM of the covering session can — reading the whole day's
    AZM, as this used to, charges a morning walk to the evening training's
    rate now that both can be counted on one day. Falls back to `default`
    until at least one such session exists.
    """
    recorded = [
        (d.day, item.minutes, item.tracked_azm)
        for d in days
        for item in d.scheduled
        if item.kind == kind and item.covered and item.tracked_azm is not None and item.minutes > 0
    ]
    if not recorded:
        return default
    recorded.sort(key=lambda t: t[0], reverse=True)
    ratios = [azm / minutes for _, minutes, azm in recorded[:window]]
    return sum(ratios) / len(ratios) if ratios else default


def observed_rates(days: list[DayInput]) -> tuple[float, float]:
    """(match_rate, training_rate) for `days`, in AZM per scheduled minute.

    The pair `daily_load` needs, exposed because the dashboard shows the
    estimate for an untracked match or training *next to* the tracked
    sessions (see api/services/exercises.py) and has to quote the same rate
    the model will count — a second, independently-derived rate would be a
    number on the card that disagrees with the load in the chart.
    """
    return (
        _observed_rate(days, MATCH, DEFAULT_MATCH_FALLBACK_LOAD_PER_MINUTE),
        _observed_rate(days, TRAINING, DEFAULT_TRAINING_FALLBACK_LOAD_PER_MINUTE),
    )


def _ewma(values: list[float], tau: int) -> list[float]:
    """Banister impulse-response EWMA — the model the professionals use.

        CTL_today = CTL_yesterday + (load_today - CTL_yesterday) * alpha
        alpha     = 1 - exp(-1 / tau)

    Two details that both matter and were both wrong before.

    **alpha is the exact `1 - exp(-1/tau)`, not the `1/tau` shorthand.** The
    two are close but not equal, and the gap grows as tau shrinks: 1.20% for
    the 42-day Fitness constant, **7.31%** for the 7-day Fatigue one. Fatigue
    is the noisier of the two and feeds straight into Form, so a 7% bias
    there is not a rounding detail.

    **The seed is zero, and the series is the whole history.** The previous
    seed was the mean of whatever series it was handed, which let the
    *requested history length* change the answer — measured live on
    2026-08-21, the same day scored Fitness 41.6 over a 120-day request and
    40.5 over a 366-day one. That is fixed upstream in
    services/training.py, which now always feeds every day it has and trims
    only what gets *displayed*. CTL is a state variable that has been
    evolving since the first tracked day; it must not depend on how much of
    the chart someone is looking at.

    Seeding at zero is what the recurrence above does on its own, and with
    full history it costs nothing: after n days only `(1-alpha)**n` of the
    seed survives, which at 261 days is 0.2%.

    "42-day rolling average" is the usual shorthand for this in sports
    software, but it is shorthand — the weighting decays smoothly rather
    than cutting off, so a hard session fades instead of dropping out of the
    window on day 43 and jolting Form.
    """
    alpha = 1.0 - math.exp(-1.0 / tau)
    current = 0.0
    out: list[float] = []
    for v in values:
        current += (v - current) * alpha
        out.append(current)
    return out


def _window_mean(values: list[float | None], window: int, skip_last: int = 0) -> float | None:
    """Mean of the non-null values in a trailing window, optionally skipping
    the most recent `skip_last` days (so a baseline isn't compared to itself)."""
    pool = values[: len(values) - skip_last] if skip_last else values
    picked = [v for v in pool[-window:] if v is not None]
    if not picked:
        return None
    return sum(picked) / len(picked)


def _recovery_score(
    days: list[DayInput], window: int = CURRENT_WINDOW
) -> tuple[int | None, dict[str, float]]:
    """0–100 recovery index from HRV, resting HR and sleep vs own baseline.

    Separate from Fatigue on purpose: fatigue is what training *did to you*,
    recovery is how well your body is currently absorbing it. Components
    that have no data drop out and the remaining weights are renormalized.

    `window` controls how many trailing days count as "now" — CURRENT_WINDOW
    (3) for the steadier trend score, READINESS_WINDOW (1) for a
    day-reactive one. The baseline always looks back BASELINE_DAYS ending
    just before `window`, so the two calls compare against slightly
    different (but heavily overlapping) baselines — intentional, each
    score's baseline excludes exactly the days it's being compared against.

    The HRV/resting-HR bands were originally ±25%/±5%, calibrated for a
    hypothetically low-variance user — confirmed live on 2026-08-21 that
    this user's actual HRV ranges ~29-113ms (a 4x spread) and routinely
    blows past a ±25% band on an ordinary night, pinning the score at 100
    almost every day regardless of how the day actually compares to others.
    Widened to bands that keep scores inside the 0-100 range most days
    instead of saturating at the ends.
    """
    hrv_series: list[float | None] = [d.hrv_ms for d in days]
    rhr_series: list[float | None] = [float(d.resting_hr) if d.resting_hr else None for d in days]
    sleep_series: list[float | None] = [float(d.sleep_minutes) if d.sleep_minutes else None for d in days]

    parts: dict[str, float] = {}
    weights: dict[str, float] = {}

    hrv_now = _window_mean(hrv_series, window)
    hrv_base = _window_mean(hrv_series, BASELINE_DAYS, skip_last=window)
    if hrv_now is not None and hrv_base:
        # +40% over baseline reads as fully recovered, −40% as fully taxed.
        parts["hrv"] = max(0.0, min(100.0, 50 + 125 * (hrv_now - hrv_base) / hrv_base))
        weights["hrv"] = 0.5

    rhr_now = _window_mean(rhr_series, window)
    rhr_base = _window_mean(rhr_series, BASELINE_DAYS, skip_last=window)
    if rhr_now is not None and rhr_base:
        # Resting HR still moves in a narrower band than HRV: −10% is
        # excellent, +10% poor.
        parts["resting_hr"] = max(0.0, min(100.0, 50 - 500 * (rhr_now - rhr_base) / rhr_base))
        weights["resting_hr"] = 0.3

    sleep_now = _window_mean(sleep_series, window)
    if sleep_now is not None:
        parts["sleep"] = max(0.0, min(100.0, sleep_now / SLEEP_TARGET_MIN * 100))
        weights["sleep"] = 0.2

    if not parts:
        return None, {}

    total_weight = sum(weights.values())
    score = sum(parts[k] * weights[k] for k in parts) / total_weight
    return round(score), {k: round(v, 1) for k, v in parts.items()}


def _score_series(days: list[DayInput]) -> list[ScorePoint]:
    """Recovery and readiness as of each day, for the detail view's chart.

    Every day is scored against only the days up to and including it — the
    same call the headline number makes, walked forward — so a point on the
    chart is what the tile would have read that morning rather than a
    hindsight recalculation against data that had not happened yet.

    A day is left unscored until MIN_HISTORY_DAYS of history sit behind it.
    Before that the HRV and resting-HR baselines are built from a handful of
    days, and the score swings on noise; worse, on day one only the sleep
    component survives (it is the one that needs no baseline) and the result
    would plot as a confident line measuring something different from the
    rest of the series. A gap is the honest shape for "not enough history
    to compare against yet".
    """
    out: list[ScorePoint] = []
    for i, day in enumerate(days):
        if i + 1 < MIN_HISTORY_DAYS:
            out.append(ScorePoint(date=day.day.isoformat(), recovery=None, readiness=None))
            continue
        window = days[: i + 1]
        recovery, _ = _recovery_score(window, window=CURRENT_WINDOW)
        readiness, _ = _recovery_score(window, window=READINESS_WINDOW)
        out.append(ScorePoint(date=day.day.isoformat(), recovery=recovery, readiness=readiness))
    return out


# Training Stress Balance bands, in raw load units (Fitness − Fatigue).
#
# These are the standard TSB bands, and they are absolute rather than a
# percentage of Fitness. The percentage form this replaced existed because
# the ±25 bands "assume CTL values in the hundreds and do not transfer"
# (ADR-009) — but that was assumed, not measured. Measured on 2026-08-21,
# this user's 42-day mean load sits around 55 AZM/day, squarely in the same
# range as the TSS-based CTL the bands were written for, so they do transfer.
# See ADR-011.
FORM_PEAKED = 25.0
FORM_FRESH = 10.0
FORM_PRODUCTIVE = -10.0
FORM_OVERREACHING = -30.0


def _classify(form: float, ramp_pct: float, recovery: int | None, fitness: float) -> tuple[str, str]:
    """Map the numbers onto a Garmin-style label. Order matters — the first
    matching rule wins, from most to least urgent.

    `form` is raw Fitness − Fatigue, not a percentage.
    """
    rec = 100 if recovery is None else recovery

    if form < FORM_OVERREACHING and rec < 45:
        return "overreaching", "Heavy load on top of poor recovery — back off."
    if form < FORM_OVERREACHING:
        return "overreaching", "Fatigue is far ahead of fitness — plan a lighter week."
    if rec < 40:
        return "strained", "Your recovery markers are down; keep the load easy."
    if form < FORM_PRODUCTIVE:
        return "productive", "A productive block — you're banking fatigue to build fitness."
    if form > FORM_PEAKED and ramp_pct < -2:
        return "recovery", "Very rested — fitness is easing off as you taper."
    if ramp_pct < -8:
        return "detraining", "Load has dropped off long enough that fitness is fading."
    if form > FORM_FRESH:
        return "peaking", "Fresh and loaded — a good window to perform."
    return "maintaining", "Load and fitness are holding steady."


def compute_training_status(days: list[DayInput], partial_last_day: bool = False) -> TrainingStatus:
    """`days` must be sorted oldest → newest, one entry per calendar day.

    Set `partial_last_day` when the final entry is today and therefore still
    filling up: a morning's step count would otherwise drag Fatigue down and
    fake a recovery. Load is then measured through yesterday, while recovery
    still uses today's overnight HRV / resting HR / sleep, which are complete.
    """
    days = sorted(days, key=lambda d: d.day)
    notes: list[str] = []

    if len(days) < MIN_HISTORY_DAYS:
        return TrainingStatus(
            status="insufficient_data",
            headline=f"Need about {MIN_HISTORY_DAYS} days of history — {len(days)} so far.",
            fitness=0.0,
            fatigue=0.0,
            form=0.0,
            form_pct=0.0,
            ramp_pct=0.0,
            recovery=None,
            days_of_history=len(days),
            notes=notes,
        )

    if len(days) < CTL_DAYS * 2:
        notes.append(
            f"Fitness uses a {CTL_DAYS}-day average and only {len(days)} days of history exist — "
            "the level is seeded from your own average, so read the trend rather than the absolute number."
        )

    # Today is still filling up; measure load through yesterday.
    load_days = days[:-1] if partial_last_day and len(days) > 1 else days
    if partial_last_day and len(days) > 1:
        notes.append(
            f"Today ({days[-1].day.isoformat()}) is still in progress — "
            "load is measured through yesterday."
        )

    match_rate, training_rate = observed_rates(load_days)
    loads = [
        daily_load(d.active_zone_minutes, d.scheduled, match_rate, training_rate) for d in load_days
    ]
    ctl = _ewma(loads, CTL_DAYS)
    atl = _ewma(loads, ATL_DAYS)

    fitness = ctl[-1]
    fatigue = atl[-1]
    form = fitness - fatigue
    form_pct = (form / fitness * 100) if fitness > 0 else 0.0

    # Weekly ramp: how much Fitness moved over the last 7 days, in percent.
    prior = ctl[-8] if len(ctl) >= 8 else ctl[0]
    ramp_pct = ((fitness - prior) / prior * 100) if prior > 0 else 0.0

    recovery, recovery_parts = _recovery_score(days, window=CURRENT_WINDOW)
    readiness, readiness_parts = _recovery_score(days, window=READINESS_WINDOW)
    if recovery is None:
        notes.append("No HRV, resting-HR or sleep data — recovery could not be scored.")

    status, headline = _classify(form, ramp_pct, recovery, fitness)

    untracked = sum(
        1 for d in load_days if d.active_zone_minutes is None and not d.scheduled
    )
    if untracked:
        notes.append(
            f"{untracked} of {len(load_days)} days have no tracked exercise and no logged match or "
            "scheduled training — counted as rest."
        )

    # Worth saying out loud: this is the load that exists only because the
    # schedule says so. It is the number that moves when a session is
    # marked skipped, so the tile should not be the only place it shows.
    estimated = sum(1 for d in load_days for item in d.scheduled if not item.covered)
    if estimated:
        notes.append(
            f"{estimated} scheduled session(s) in this period were not recorded by the watch — "
            "their load is estimated from their minutes."
        )

    return TrainingStatus(
        status=status,
        headline=headline,
        fitness=round(fitness, 1),
        fatigue=round(fatigue, 1),
        form=round(form, 1),
        form_pct=round(form_pct, 1),
        ramp_pct=round(ramp_pct, 1),
        recovery=recovery,
        recovery_parts=recovery_parts,
        readiness=readiness,
        readiness_parts=readiness_parts,
        days_of_history=len(days),
        series=[
            DayPoint(
                date=d.day.isoformat(),
                load=loads[i],
                fitness=round(ctl[i], 1),
                fatigue=round(atl[i], 1),
            )
            for i, d in enumerate(load_days)
        ],
        # Over every day, not just load_days: today has no final load but it
        # does have last night's numbers. See ScorePoint.
        scores=_score_series(days),
        notes=notes,
    )
