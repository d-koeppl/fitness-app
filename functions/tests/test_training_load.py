"""Tests for api/analysis/training_load.py.

This is the one module in the repo where a subtle change stays invisible in
the UI until the numbers have been wrong for a week, so the rules it
encodes are pinned here: how the EWMA is seeded, when the schedule
fallback applies and to which session, that matches and training use
separately-observed rates, and the order the status labels are decided in.
"""

from __future__ import annotations

import math
from datetime import UTC, date, datetime, timedelta

import pytest

from api.analysis.training_load import (
    ATL_DAYS,
    COVER_AFTER_MINUTES,
    COVER_BEFORE_MINUTES,
    CTL_DAYS,
    DEFAULT_MATCH_FALLBACK_LOAD_PER_MINUTE,
    DEFAULT_TRAINING_FALLBACK_LOAD_PER_MINUTE,
    MATCH,
    MIN_HISTORY_DAYS,
    RATE_WINDOW,
    TRAINING,
    DayInput,
    ScheduledSession,
    _classify,
    _ewma,
    _observed_rate,
    _recovery_score,
    _score_series,
    _window_mean,
    compute_training_status,
    covers,
    daily_load,
)

START = date(2026, 1, 1)
KICKOFF = datetime(2026, 1, 1, 17, 0, tzinfo=UTC)


def days(n: int, **kwargs) -> list[DayInput]:
    """n consecutive days, all carrying the same values."""
    return [DayInput(day=START + timedelta(days=i), **kwargs) for i in range(n)]


def match(minutes=90, covered=False, tracked_azm=None) -> ScheduledSession:
    return ScheduledSession(kind=MATCH, minutes=minutes, covered=covered, tracked_azm=tracked_azm)


def training(minutes=90, covered=False, tracked_azm=None) -> ScheduledSession:
    return ScheduledSession(kind=TRAINING, minutes=minutes, covered=covered, tracked_azm=tracked_azm)


# --- daily_load -------------------------------------------------------------


def test_a_covered_session_adds_nothing_on_top_of_what_was_tracked():
    """The double-count guard. A session the watch recorded is already
    inside the day's AZM, so its scheduled minutes must contribute zero."""
    assert daily_load(224.0, [match(covered=True), training(covered=True)]) == 224.0


def test_an_uncovered_session_is_added_to_the_tracked_total():
    """The rule this replaced took the day's AZM and stopped. A morning
    walk and an untracked evening training are two sessions, and the day
    cost both — see ADR-015."""
    walk = 3.0
    load = daily_load(walk, [training()])

    assert load == pytest.approx(walk + 90 * DEFAULT_TRAINING_FALLBACK_LOAD_PER_MINUTE, abs=0.01)


def test_zero_tracked_azm_is_still_a_reading():
    """0 is a reading, not a missing value — and with nothing scheduled it
    stays 0 rather than falling through to an estimate."""
    assert daily_load(0.0, [match(covered=True)]) == 0.0


def test_an_untracked_day_falls_back_per_type():
    assert daily_load(None, [match()]) == pytest.approx(
        90 * DEFAULT_MATCH_FALLBACK_LOAD_PER_MINUTE, abs=0.01
    )
    assert daily_load(None, [training()]) == pytest.approx(
        90 * DEFAULT_TRAINING_FALLBACK_LOAD_PER_MINUTE, abs=0.01
    )


def test_two_uncovered_sessions_on_one_day_both_count():
    assert daily_load(None, [match(), training()]) == pytest.approx(
        90 * DEFAULT_MATCH_FALLBACK_LOAD_PER_MINUTE + 90 * DEFAULT_TRAINING_FALLBACK_LOAD_PER_MINUTE,
        abs=0.01,
    )


def test_match_rate_is_higher_than_training_rate():
    """Competitive play runs hotter than practice - the whole reason the
    fallback rate is split by type."""
    assert DEFAULT_MATCH_FALLBACK_LOAD_PER_MINUTE > DEFAULT_TRAINING_FALLBACK_LOAD_PER_MINUTE


def test_untracked_rest_day_is_zero():
    assert daily_load(None) == 0.0


def test_negative_minutes_cannot_create_load():
    assert daily_load(None, [match(minutes=-90), training(minutes=-90)]) == 0.0


# --- covers -----------------------------------------------------------------


def test_a_session_starting_at_the_scheduled_time_is_that_session():
    assert covers(KICKOFF, KICKOFF) is True


@pytest.mark.parametrize("minutes_early", [1, COVER_BEFORE_MINUTES])
def test_a_session_started_early_still_counts(minutes_early):
    """The watch goes on at arrival, which is before kick-off."""
    assert covers(KICKOFF, KICKOFF - timedelta(minutes=minutes_early)) is True


@pytest.mark.parametrize("minutes_late", [1, COVER_AFTER_MINUTES])
def test_a_session_started_during_the_session_still_counts(minutes_late):
    assert covers(KICKOFF, KICKOFF + timedelta(minutes=minutes_late)) is True


def test_a_session_running_through_kickoff_counts_even_if_it_started_early():
    """ADR-022: a watch started for a long warm-up begins before the
    window, but a session worn through kick-off and still going is the
    match. 45 min before opens outside COVER_BEFORE_MINUTES (30)."""
    start = KICKOFF - timedelta(minutes=45)
    end = KICKOFF + timedelta(minutes=105)
    assert covers(KICKOFF, start) is False
    assert covers(KICKOFF, start, end) is True


def test_the_span_rule_needs_the_scheduled_start_inside_the_interval():
    """A session that ended before kick-off is still a different session,
    even with an end time to check."""
    start = KICKOFF - timedelta(hours=3)
    end = KICKOFF - timedelta(minutes=45)
    assert covers(KICKOFF, start, end) is False


def test_a_naive_end_is_ignored_not_raised():
    """The end is a best-effort extra signal; a naive one falls back to the
    window check rather than blowing up the comparison."""
    start = KICKOFF - timedelta(minutes=45)
    naive_end = datetime(2026, 1, 1, 19, 0)
    assert covers(KICKOFF, start, naive_end) is False


def test_a_morning_walk_is_not_the_evening_training():
    """The case that motivated the whole rule (ADR-015)."""
    assert covers(KICKOFF, KICKOFF - timedelta(hours=9)) is False
    # ...and an end time does not rescue it: a 07:00-07:30 walk does not
    # span a 17:00 kick-off.
    assert covers(KICKOFF, KICKOFF - timedelta(hours=9), KICKOFF - timedelta(hours=8.5)) is False


def test_a_session_long_after_the_final_whistle_is_a_different_session():
    assert covers(KICKOFF, KICKOFF + timedelta(minutes=COVER_AFTER_MINUTES + 1)) is False


def test_the_window_is_wider_after_than_before():
    """Deliberate: a watch is started shortly before, but can be started at
    any point of a 90-minute session."""
    assert COVER_AFTER_MINUTES > COVER_BEFORE_MINUTES


# --- _observed_rate ---------------------------------------------------------


def test_observed_rate_defaults_until_a_recorded_session_exists():
    untracked = [DayInput(day=START, scheduled=(match(),))]
    assert _observed_rate(untracked, MATCH, 2.49) == 2.49


def test_observed_rate_averages_recorded_sessions_of_that_kind_only():
    data = [
        DayInput(day=START, scheduled=(match(90, covered=True, tracked_azm=180.0),)),  # 2.0
        DayInput(  # other kind
            day=START + timedelta(days=1),
            scheduled=(training(90, covered=True, tracked_azm=90.0),),
        ),
        DayInput(
            day=START + timedelta(days=2),
            scheduled=(match(60, covered=True, tracked_azm=180.0),),  # 3.0
        ),
    ]
    assert _observed_rate(data, MATCH, 99.0) == pytest.approx(2.5)


def test_observed_rate_reads_the_covering_session_not_the_whole_day():
    """The reason this stopped dividing the day's AZM by the session's
    minutes: a day can now hold a tracked walk *and* a tracked match, and
    charging the walk to the match's rate inflates every later estimate."""
    day = DayInput(
        day=START,
        active_zone_minutes=280.0,  # 224 match + 56 of walking
        scheduled=(match(90, covered=True, tracked_azm=224.0),),
    )
    assert _observed_rate([day], MATCH, 99.0) == pytest.approx(224 / 90)


def test_a_covering_session_with_no_azm_says_nothing_about_the_rate():
    """Real case: the 2026-08-23 swim recorded no Active Zone Minutes at
    all. It covers, so no estimate is added, but it cannot calibrate."""
    day = DayInput(day=START, scheduled=(match(90, covered=True, tracked_azm=None),))
    assert _observed_rate([day], MATCH, 2.49) == 2.49


def test_observed_rate_uses_only_the_most_recent_window():
    old = [
        DayInput(
            day=START + timedelta(days=i),
            scheduled=(match(90, covered=True, tracked_azm=900.0),),  # rate 10.0
        )
        for i in range(RATE_WINDOW)
    ]
    recent = [
        DayInput(
            day=START + timedelta(days=100 + i),
            scheduled=(match(90, covered=True, tracked_azm=90.0),),  # rate 1.0
        )
        for i in range(RATE_WINDOW)
    ]
    assert _observed_rate(old + recent, MATCH, 99.0) == pytest.approx(1.0)


# --- _ewma ------------------------------------------------------------------


def test_ewma_matches_the_banister_recurrence():
    """CTL_today = CTL_yesterday + (load_today - CTL_yesterday) * alpha,
    with alpha = 1 - exp(-1/tau). Computed here by hand, independently."""
    alpha = 1 - math.exp(-1 / CTL_DAYS)
    loads = [10.0, 0.0, 250.0, 30.0]
    expected, cur = [], 0.0
    for v in loads:
        cur += (v - cur) * alpha
        expected.append(cur)
    assert _ewma(loads, CTL_DAYS) == pytest.approx(expected)


def test_ewma_uses_the_exact_alpha_not_the_one_over_tau_shorthand():
    """1/tau is 1.2% off for the 42-day constant and 7.3% off for the 7-day
    one — the second is big enough to bias Fatigue, and Form with it."""
    loads = [100.0] * 30
    exact = _ewma(loads, ATL_DAYS)[-1]

    approx, cur = None, 0.0
    for v in loads:
        cur += (v - cur) * (1 / ATL_DAYS)
        approx = cur

    assert exact != pytest.approx(approx, rel=1e-4)
    assert exact < approx  # the exact alpha is the smaller one


def test_ewma_starts_from_zero_and_converges_on_a_steady_load():
    values = [50.0] * 400
    out = _ewma(values, CTL_DAYS)
    assert out[0] < 2.0
    assert out[-1] == pytest.approx(50.0, abs=0.1)


def test_ewma_decays_rather_than_cutting_off():
    """The property a rolling mean cannot offer: a hard day fades instead of
    dropping out of the window on day tau+1 and jolting Form."""
    spike = [500.0] + [0.0] * (CTL_DAYS + 2)
    out = _ewma(spike, CTL_DAYS)
    day42, day43 = out[CTL_DAYS], out[CTL_DAYS + 1]
    assert day43 < day42  # still falling
    assert day43 > day42 * 0.9  # smoothly, not off a cliff
    assert day43 > 0  # and never all the way to nothing


def test_ewma_short_tau_reacts_faster_than_long_tau():
    values = [0.0] * 20 + [100.0] * 5
    assert _ewma(values, ATL_DAYS)[-1] > _ewma(values, CTL_DAYS)[-1]


def test_ewma_of_empty_series():
    assert _ewma([], CTL_DAYS) == []


# --- _window_mean -----------------------------------------------------------


def test_window_mean_ignores_nulls_and_honours_skip_last():
    values = [1.0, None, 3.0, 100.0]
    assert _window_mean(values, window=3, skip_last=1) == pytest.approx(2.0)
    assert _window_mean([None, None], window=2) is None


# --- _recovery_score --------------------------------------------------------


def test_recovery_is_none_without_any_inputs():
    score, parts = _recovery_score(days(30))
    assert score is None
    assert parts == {}


def test_recovery_rises_when_hrv_is_above_its_own_baseline():
    baseline = [
        DayInput(day=START + timedelta(days=i), hrv_ms=50.0, resting_hr=55, sleep_minutes=480)
        for i in range(28)
    ]
    raised = [
        DayInput(day=START + timedelta(days=28 + i), hrv_ms=70.0, resting_hr=55, sleep_minutes=480)
        for i in range(3)
    ]
    lowered = [
        DayInput(day=START + timedelta(days=28 + i), hrv_ms=30.0, resting_hr=55, sleep_minutes=480)
        for i in range(3)
    ]
    better, _ = _recovery_score(baseline + raised)
    worse, _ = _recovery_score(baseline + lowered)
    assert better > worse


def test_recovery_weights_renormalize_when_a_component_is_missing():
    """Sleep alone at target reads as a full sleep score, not as 20 out of
    100 because the other two components are absent."""
    sleep_only = [DayInput(day=START + timedelta(days=i), sleep_minutes=480) for i in range(30)]
    score, parts = _recovery_score(sleep_only)
    assert set(parts) == {"sleep"}
    assert score == 100


# --- _classify --------------------------------------------------------------


def test_classify_rule_order_puts_the_most_urgent_first():
    """Deep negative form *and* poor recovery reports the combined reason,
    not the form-only one that follows it."""
    status, headline = _classify(form=-40, ramp_pct=0, recovery=30, fitness=50)
    assert status == "overreaching"
    assert "recovery" in headline.lower()


@pytest.mark.parametrize(
    "form, ramp_pct, recovery, expected",
    [
        # The standard TSB bands, in raw load units.
        (-40, 0, 80, "overreaching"),  # below -30
        (-20, 0, 80, "productive"),  # -10 to -30
        (0, 0, 80, "maintaining"),  # -10 to +10
        (20, 0, 80, "peaking"),  # +10 to +25
        (30, -5, 80, "recovery"),  # above +25 and easing off
        (0, 0, 30, "strained"),  # recovery overrides a neutral form
        (0, -20, 80, "detraining"),
    ],
)
def test_classify_covers_each_band(form, ramp_pct, recovery, expected):
    assert _classify(form, ramp_pct, recovery, fitness=50)[0] == expected


def test_classify_reads_form_in_raw_units_not_percent():
    """-20 is a productive block on the TSB scale. Read as a percentage of
    fitness it would have been a shrug, which is the bug this replaced."""
    assert _classify(form=-20, ramp_pct=0, recovery=80, fitness=50)[0] == "productive"


def test_missing_recovery_does_not_trigger_the_low_recovery_rules():
    assert _classify(form=0, ramp_pct=0, recovery=None, fitness=50)[0] == "maintaining"


# --- compute_training_status ------------------------------------------------


def test_short_history_reports_insufficient_data():
    result = compute_training_status(days(MIN_HISTORY_DAYS - 1))
    assert result.status == "insufficient_data"
    assert result.days_of_history == MIN_HISTORY_DAYS - 1
    assert result.series == []


def test_empty_input_is_insufficient_data():
    assert compute_training_status([]).status == "insufficient_data"


def test_partial_last_day_is_excluded_from_load():
    """Today's half-filled numbers would drag Fatigue down and fake a
    recovery, so load is measured through yesterday."""
    data = days(30, active_zone_minutes=60.0)
    full = compute_training_status(data)
    partial = compute_training_status(data, partial_last_day=True)
    assert len(partial.series) == len(full.series) - 1
    assert any("still in progress" in note for note in partial.notes)


def test_input_order_does_not_matter():
    data = days(30, active_zone_minutes=60.0)
    assert compute_training_status(list(reversed(data))).to_dict() == compute_training_status(data).to_dict()


def test_steady_load_gives_zero_form_and_flat_ramp():
    """Once converged. A zero-seeded 42-day EWMA needs several time
    constants to get there — see the ramp-up test below."""
    result = compute_training_status(days(400, active_zone_minutes=30.0))
    assert result.fitness == pytest.approx(30.0, abs=0.1)
    assert result.fatigue == pytest.approx(30.0, abs=0.1)
    assert result.form == pytest.approx(0.0, abs=0.1)
    assert result.ramp_pct == pytest.approx(0.0, abs=0.1)


def test_fitness_ramps_up_from_zero_rather_than_starting_at_the_average():
    """The trade for a number that does not depend on how much history was
    requested. On a flat load, Fitness is still climbing after 90 days —
    30 * (1 - exp(-90/42)) = 26.5 — while the 7-day Fatigue is long since
    there, so early Form reads negative on a steady diet.

    This is why the seeding used to be the series mean, and why that was
    the wrong fix: it bought a fast start by letting the requested window
    into the answer.
    """
    result = compute_training_status(days(90, active_zone_minutes=30.0))
    assert result.fitness == pytest.approx(26.5, abs=0.1)
    assert result.fatigue == pytest.approx(30.0, abs=0.1)
    assert result.form < 0


def test_a_hard_block_pushes_fatigue_above_fitness():
    data = days(60, active_zone_minutes=20.0) + [
        DayInput(day=START + timedelta(days=60 + i), active_zone_minutes=200.0) for i in range(10)
    ]
    result = compute_training_status(data)
    assert result.fatigue > result.fitness
    assert result.form < 0


def test_untracked_days_are_counted_in_a_note():
    result = compute_training_status(days(30))  # no AZM, no match, no training
    assert any("no tracked exercise" in note for note in result.notes)


def test_short_history_warns_that_the_level_is_seeded():
    result = compute_training_status(days(30, active_zone_minutes=10.0))
    assert any("seeded from your own average" in note for note in result.notes)


def test_series_lines_up_with_the_days_it_describes():
    data = days(30, active_zone_minutes=15.0)
    result = compute_training_status(data)
    assert [p.date for p in result.series] == [d.day.isoformat() for d in data]


def test_to_dict_is_json_shaped():
    result = compute_training_status(days(30, active_zone_minutes=15.0)).to_dict()
    assert isinstance(result["series"][0], dict)
    assert set(result["series"][0]) == {"date", "load", "fitness", "fatigue"}
    assert set(result["scores"][0]) == {"date", "recovery", "readiness"}


# --- _score_series ----------------------------------------------------------


def varied(n: int) -> list[DayInput]:
    """n days whose HRV and resting HR move, so the scores are not constant."""
    return [
        DayInput(
            day=START + timedelta(days=i),
            active_zone_minutes=20.0,
            hrv_ms=60.0 + (i % 7) * 5,
            resting_hr=52 + (i % 5),
            sleep_minutes=420 + (i % 3) * 30,
        )
        for i in range(n)
    ]


def test_score_series_has_one_point_per_day():
    data = varied(40)
    scores = _score_series(data)
    assert [p.date for p in scores] == [d.day.isoformat() for d in data]


def test_score_series_leaves_the_first_days_unscored():
    """Before MIN_HISTORY_DAYS there is no baseline to compare against, and
    only the sleep component — the one needing no baseline — would survive."""
    scores = _score_series(varied(40))
    assert all(p.recovery is None and p.readiness is None for p in scores[: MIN_HISTORY_DAYS - 1])
    assert scores[MIN_HISTORY_DAYS - 1].recovery is not None


def test_each_point_matches_scoring_that_day_as_the_last_one():
    """A point is what the tile would have read that morning, not a
    recalculation against data that had not happened yet."""
    data = varied(40)
    scores = _score_series(data)
    for i in (20, 30, 39):
        assert scores[i].recovery == _recovery_score(data[: i + 1])[0]


def test_a_point_does_not_move_when_later_days_arrive():
    data = varied(40)
    assert _score_series(data)[:30] == _score_series(data[:30])


def test_scores_stay_inside_the_range_they_claim():
    for point in _score_series(varied(60)):
        for value in (point.recovery, point.readiness):
            assert value is None or 0 <= value <= 100


def test_scores_cover_today_even_when_its_load_does_not():
    """Load stops at yesterday while today fills up, but last night's HRV,
    resting HR and sleep are already in — so the score series is one longer."""
    data = varied(40)
    result = compute_training_status(data, partial_last_day=True)
    assert len(result.scores) == len(result.series) + 1
    assert result.scores[-1].date == data[-1].day.isoformat()
    assert result.scores[-1].readiness == result.readiness


def test_readiness_reacts_to_one_night_more_sharply_than_recovery():
    """The whole reason the two exist: readiness reads last night, recovery
    smooths three, so a single bad night moves readiness further."""
    data = varied(40)
    crash = data[:-1] + [
        DayInput(
            day=data[-1].day,
            active_zone_minutes=20.0,
            hrv_ms=20.0,
            resting_hr=70,
            sleep_minutes=240,
        )
    ]
    before = _score_series(data)[-1]
    after = _score_series(crash)[-1]
    assert after.readiness < before.readiness
    assert (before.readiness - after.readiness) > (before.recovery - after.recovery)
