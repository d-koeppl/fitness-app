"""Tests for the per-session heart rate feature (ADR-020).

Three layers, and they fail for different reasons, so they are kept apart:

- `api/analysis/heart_rate.py` — the maths. Zone boundaries, time in zone,
  thinning. Pure, so these are the cheap tests and the ones that would
  catch a silently wrong chart.
- `api/integrations/google_health.py` — the parsing. The response shapes
  here are written from the published reference, *not* confirmed live (see
  that module's docstring), so what these pin down is the fail-soft
  behaviour: a rejected filter falls back to paging, junk is skipped.
- `api/services/heart_rate.py` — which time-in-zone answer wins, and that a
  half-written row cannot break a page load.
- `api/ingest/heart_rate.py` — which sessions a run picks up, which is
  what decides both the request count and whether a trace ever arrives.
"""

from __future__ import annotations

from datetime import UTC, datetime

import pytest
import requests

from api.analysis import heart_rate as hr
from api.config import settings
from api.integrations import google_health as gh
from api.services import heart_rate as service

# --- zone boundaries --------------------------------------------------------


def test_zone_bands_follow_the_karvonen_fractions():
    """Reserve 135 from a resting 56 and a max of 191 — the reading behind
    the zones in the Google Health app screenshot this was built from:
    moderate at 40%, vigorous at 60%, peak at 85% of reserve."""
    bands = hr.zone_bands(max_hr=191, resting_hr=56)

    assert [(b.zone, b.lower_bpm, b.upper_bpm) for b in bands] == [
        (hr.LIGHT, None, 110),
        (hr.FAT_BURN, 110, 137),
        (hr.CARDIO, 137, 171),
        (hr.PEAK, 171, None),
    ]


@pytest.mark.parametrize(
    "max_hr, resting_hr",
    [(None, 56), (191, None), (0, 56), (56, 56), (50, 56)],
    ids=["no max", "no resting", "zero max", "no reserve", "inverted"],
)
def test_zones_without_a_usable_reserve_are_no_zones_at_all(max_hr, resting_hr):
    """Empty, not a guess: an uncoloured trace is honest, and a coloured one
    drawn against invented boundaries is not."""
    assert hr.zone_bands(max_hr, resting_hr) == []


def test_bands_stay_strictly_ascending_on_a_tiny_reserve():
    """Rounding can land two floors on the same bpm, which would leave a
    band no reading can fall into."""
    bands = hr.zone_bands(max_hr=62, resting_hr=60)
    lowers = [b.lower_bpm for b in bands if b.lower_bpm is not None]

    assert lowers == sorted(set(lowers))
    assert len(lowers) == 3


def test_zone_for_puts_a_boundary_reading_in_the_higher_zone():
    """"At least 85% of reserve" is peak, not the top of vigorous."""
    bands = hr.zone_bands(max_hr=191, resting_hr=56)

    assert hr.zone_for(60, bands) == hr.LIGHT
    assert hr.zone_for(110, bands) == hr.FAT_BURN
    assert hr.zone_for(136, bands) == hr.FAT_BURN
    assert hr.zone_for(137, bands) == hr.CARDIO
    assert hr.zone_for(171, bands) == hr.PEAK
    assert hr.zone_for(210, bands) == hr.PEAK


def test_zone_for_without_bands_is_no_zone():
    assert hr.zone_for(150, []) is None


# --- time in zone -----------------------------------------------------------


BANDS = hr.zone_bands(max_hr=191, resting_hr=56)


def test_time_in_zones_credits_each_sample_with_the_gap_that_follows_it():
    """Sampled every 10 s: two readings in fat burn are 20 s, not 2 counts.
    The last sample earns nothing — nothing says how long it lasted."""
    samples = [(0, 120), (10, 125), (20, 140), (30, 145)]

    assert hr.time_in_zones(samples, BANDS) == {
        hr.LIGHT: 0.0,
        hr.FAT_BURN: 20.0,
        hr.CARDIO: 10.0,
        hr.PEAK: 0.0,
    }


def test_a_dropout_is_credited_to_nobody():
    """Twenty minutes with no readings is the watch having stopped, not
    twenty minutes spent at the last bpm it saw."""
    samples = [(0, 120), (10, 120), (1810, 150), (1820, 150)]

    seconds = hr.time_in_zones(samples, BANDS)
    assert seconds[hr.FAT_BURN] == 10.0
    assert seconds[hr.CARDIO] == 10.0
    assert sum(seconds.values()) == 20.0


def test_time_in_zones_needs_both_bands_and_a_second_sample():
    assert hr.time_in_zones([(0, 120), (10, 130)], []) == {}
    assert hr.time_in_zones([(0, 120)], BANDS) == {}


def test_covered_seconds_ignores_the_gap_it_did_not_measure():
    assert hr.covered_seconds([(0, 120), (10, 120), (1810, 150), (1820, 150)]) == 20.0
    assert hr.covered_seconds([]) == 0.0


# --- thinning the trace -----------------------------------------------------


def test_downsample_leaves_a_short_trace_alone():
    samples = [(i, 100 + i) for i in range(50)]
    assert hr.downsample(samples, 400) == samples


def test_downsample_keeps_the_peak_it_is_thinning_around():
    """The spike is the whole point of the chart — an average would sand it
    off exactly where the zone colouring is decided."""
    samples = [(i, 120) for i in range(1000)]
    samples[500] = (500, 194)
    samples[600] = (600, 61)

    thinned = hr.downsample(samples, 100)

    assert len(thinned) <= 100
    assert (500, 194) in thinned
    assert (600, 61) in thinned
    # Still in the order they were recorded, or the line would zig-zag back
    # through time.
    assert [t for t, _ in thinned] == sorted(t for t, _ in thinned)


def test_every_thinned_point_is_a_reading_that_was_really_taken():
    samples = [(i, 100 + (i % 37)) for i in range(2000)]

    assert set(hr.downsample(samples, 200)) <= set(samples)


def test_summarize():
    assert hr.summarize([(0, 100), (1, 150), (2, 110)]) == hr.TraceSummary(100, 150, 120.0)
    assert hr.summarize([]) is None


# --- fetching ---------------------------------------------------------------


def hr_point(stamp: str, bpm: str) -> dict:
    """The documented shape: sampleTime.physicalTime, and an int64 bpm as a
    JSON string like every other int64 in this API."""
    return {
        "heartRate": {
            "sampleTime": {"physicalTime": stamp, "utcOffset": "7200s"},
            "beatsPerMinute": bpm,
            "metadata": {"motionContext": "ACTIVE", "sensorLocation": "WRIST"},
        }
    }


@pytest.fixture
def token(monkeypatch):
    monkeypatch.setattr(gh, "get_valid_access_token", lambda target: "test-token")


@pytest.fixture(autouse=True)
def forget_rejected_filters():
    """The rejection cache is process-wide on purpose (one wasted request
    per process, not per session) — which makes it leak between tests."""
    gh._FILTER_REJECTED.clear()
    yield
    gh._FILTER_REJECTED.clear()


def test_heart_rate_samples_are_parsed_and_windowed(monkeypatch, token):
    calls = []

    def fake_get(access_token, url, params):
        calls.append(params)
        return {
            "dataPoints": [
                hr_point("2026-08-20T17:00:10Z", "142"),
                hr_point("2026-08-20T17:00:00Z", "138"),
                # Outside the asked-for window: dropped here even though the
                # server sent it, so a neighbouring session's readings can
                # never land on this session's chart.
                hr_point("2026-08-20T18:30:00Z", "80"),
                # Junk of three kinds — no timestamp, no bpm, a zero.
                {"heartRate": {"beatsPerMinute": "150"}},
                hr_point("2026-08-20T17:00:20Z", "nonsense"),
                hr_point("2026-08-20T17:00:30Z", "0"),
            ]
        }

    monkeypatch.setattr(gh, "_get", fake_get)
    samples = gh.fetch_heart_rate_samples(
        datetime(2026, 8, 20, 17, 0, tzinfo=UTC), datetime(2026, 8, 20, 18, 5, tzinfo=UTC)
    )

    assert [bpm for _, bpm in samples] == [138, 142]  # oldest first
    assert 'heart_rate.sample_time.physical_time >= "2026-08-20T17:00:00Z"' in calls[0]["filter"]


def test_a_rejected_filter_falls_back_to_paging_and_is_only_tried_once(monkeypatch, token):
    """The daily types in this module have no working filter at all, so this
    one cannot be assumed to work either — but the wasted request should be
    spent once per process, not once per session."""
    attempts = []

    def fake_get(access_token, url, params):
        attempts.append(params)
        if "filter" in params:
            response = requests.Response()
            response.status_code = 400
            raise requests.HTTPError("bad filter", response=response)
        return {"dataPoints": [hr_point("2026-08-20T17:00:00Z", "138")]}

    monkeypatch.setattr(gh, "_get", fake_get)
    window = (datetime(2026, 8, 20, 17, 0, tzinfo=UTC), datetime(2026, 8, 20, 18, 5, tzinfo=UTC))

    assert gh.fetch_heart_rate_samples(*window) == [(datetime(2026, 8, 20, 17, 0, tzinfo=UTC), 138)]
    assert gh.fetch_heart_rate_samples(*window) != []

    assert sum("filter" in params for params in attempts) == 1


def test_a_failure_that_is_not_the_filter_is_raised(monkeypatch, token):
    """A dead token or a 500 must reach the sync, which knows the difference
    between "no readings" and "we could not ask"."""

    def fake_get(access_token, url, params):
        response = requests.Response()
        response.status_code = 401
        raise requests.HTTPError("expired", response=response)

    monkeypatch.setattr(gh, "_get", fake_get)

    with pytest.raises(requests.HTTPError):
        gh.fetch_heart_rate_samples(
            datetime(2026, 8, 20, 17, 0, tzinfo=UTC), datetime(2026, 8, 20, 18, 5, tzinfo=UTC)
        )


def test_paging_stops_once_a_whole_page_falls_before_the_window(monkeypatch, token):
    """Points come newest-first, so a page entirely older than the window
    means there is nothing left behind it worth reading."""
    pages = [
        {"dataPoints": [hr_point("2026-08-20T17:00:00Z", "138")], "nextPageToken": "p2"},
        {"dataPoints": [hr_point("2026-08-19T09:00:00Z", "70")], "nextPageToken": "p3"},
        {"dataPoints": [hr_point("2026-08-18T09:00:00Z", "70")], "nextPageToken": "p4"},
    ]
    seen = []

    def fake_get(access_token, url, params):
        seen.append(params.get("pageToken"))
        return pages[len(seen) - 1]

    monkeypatch.setattr(gh, "_get", fake_get)
    gh._FILTER_REJECTED.add(gh.HEART_RATE_DATA_TYPE)

    gh.fetch_heart_rate_samples(
        datetime(2026, 8, 20, 17, 0, tzinfo=UTC), datetime(2026, 8, 20, 18, 5, tzinfo=UTC)
    )

    assert seen == [None, "p2"]


def test_time_in_zones_are_summed_per_zone_in_seconds(monkeypatch, token):
    def fake_get(access_token, url, params):
        return {
            "dataPoints": [
                {
                    "timeInHeartRateZone": {
                        "interval": {"startTime": "2026-08-20T17:00:00Z"},
                        "heartRateZone": "CARDIO",
                        "durationMillis": "600000",
                    }
                },
                {
                    "timeInHeartRateZone": {
                        "interval": {"startTime": "2026-08-20T17:20:00Z"},
                        "heartRateZone": "CARDIO",
                        "durationMillis": "300000",
                    }
                },
                {
                    "timeInHeartRateZone": {
                        "interval": {"startTime": "2026-08-20T17:40:00Z"},
                        "heartRateZone": "FAT_BURN",
                        "durationMillis": "60000",
                    }
                },
                # No zone name, so nothing to file it under.
                {"timeInHeartRateZone": {"interval": {"startTime": "2026-08-20T17:50:00Z"}}},
            ]
        }

    monkeypatch.setattr(gh, "_get", fake_get)

    assert gh.fetch_time_in_zones(
        datetime(2026, 8, 20, 17, 0, tzinfo=UTC), datetime(2026, 8, 20, 18, 5, tzinfo=UTC)
    ) == {"CARDIO": 900.0, "FAT_BURN": 60.0}


# --- which answer wins ------------------------------------------------------


def test_googles_own_time_in_zone_wins_and_light_is_the_remainder():
    """Google names only the three scoring zones; what is left of the time
    the samples cover was below the first of them — the same subtraction the
    Google Health app's own "light" bar is."""
    samples = [(i, 150) for i in range(0, 600, 10)]  # 590 s covered

    zones, source = service._zone_times(
        BANDS, samples, {"CARDIO": 400.0, "FAT_BURN": 100.0, "PEAK": 30.0}
    )

    assert source == service.GOOGLE
    assert {z.zone: z.seconds for z in zones} == {
        hr.LIGHT: 60.0,
        hr.FAT_BURN: 100.0,
        hr.CARDIO: 400.0,
        hr.PEAK: 30.0,
    }


def test_light_never_goes_negative_when_googles_zones_outrun_the_trace():
    zones, _ = service._zone_times(BANDS, [(0, 150), (10, 150)], {"CARDIO": 9999.0})

    assert {z.zone: z.seconds for z in zones}[hr.LIGHT] == 0.0


def test_without_googles_answer_the_samples_are_counted_here_and_say_so():
    samples = [(0, 120), (10, 125), (20, 140), (30, 145)]

    zones, source = service._zone_times(BANDS, samples, {})

    assert source == service.DERIVED
    assert {z.zone: z.seconds for z in zones}[hr.FAT_BURN] == 20.0


def test_no_bands_means_no_zone_rows_at_all():
    assert service._zone_times([], [(0, 150), (10, 150)], {"CARDIO": 10.0}) == ([], None)


def test_zone_rows_carry_the_boundaries_they_were_measured_against():
    zones, _ = service._zone_times(BANDS, [(0, 150), (10, 150)], {})

    assert [(z.zone, z.lower_bpm, z.upper_bpm) for z in zones] == [
        (hr.LIGHT, None, 110),
        (hr.FAT_BURN, 110, 137),
        (hr.CARDIO, 137, 171),
        (hr.PEAK, 171, None),
    ]


class _Row:
    def __init__(self, samples):
        self.samples = samples


@pytest.mark.parametrize(
    "stored, expected",
    [
        (None, []),
        (_Row([[0, 120], [10, 125]]), [(0, 120), (10, 125)]),
        (_Row([]), []),
        # A half-written or hand-edited row must leave the chart empty
        # rather than 500 a page load.
        (_Row("not a list"), []),
        (_Row([[0], [1, 2, 3], ["a", "b"], None, [20, 130]]), [(20, 130)]),
    ],
    ids=["no row", "pairs", "empty", "not a list", "junk mixed in"],
)
def test_stored_samples_are_read_defensively(stored, expected):
    assert service._stored_samples(stored) == expected


def test_max_heart_rate_prefers_the_measured_one_over_the_age_formula(monkeypatch):
    monkeypatch.setattr(settings, "health_max_hr_bpm", 196)
    monkeypatch.setattr(settings, "health_birth_year", 1997)
    assert settings.max_heart_rate == 196

    monkeypatch.setattr(settings, "health_max_hr_bpm", None)
    assert settings.max_heart_rate == 220 - (datetime.now().year - 1997)

    monkeypatch.setattr(settings, "health_birth_year", None)
    assert settings.max_heart_rate is None


# The sync-side tests (which sessions it fetches, and when) move with the
# heart-rate sync in phase 3.
