"""Tests for api/integrations/google_health.py.

The response shapes asserted here are the ones the module's docstring
records as confirmed against live responses - most of the risk in this
adapter is that Google's field names or nesting change and the extraction
silently starts returning None, so the shapes are pinned as fixtures.
"""

from __future__ import annotations

from datetime import date

import pytest

from api.config import settings
from api.integrations import google_health as gh

# --- as_number -------------------------------------------------------------


@pytest.mark.parametrize(
    "raw, expected",
    [
        ("57", 57.0),  # int64 fields arrive as JSON strings
        (57, 57.0),
        (57.5, 57.5),
        ("57.5", 57.5),
        ("", None),
        ("not a number", None),
        (None, None),
        ({}, None),
        (True, None),  # a bool is not a measurement
        (False, None),
    ],
)
def test_as_number(raw, expected):
    assert gh.as_number(raw) == expected


# --- date extraction --------------------------------------------------------


def test_rollup_date_reads_the_nested_civil_date():
    point = {"civilStartTime": {"date": {"year": 2026, "month": 8, "day": 19}}}
    assert gh._rollup_date(point) == date(2026, 8, 19)


def test_rollup_date_of_a_point_without_one():
    assert gh._rollup_date({}) is None


def test_civil_date_request_shape():
    """The request uses {"date": {...}}; the response nests the same thing
    one level deeper under civilStartTime. Mixing them up 400s."""
    assert gh._civil_date(date(2026, 8, 19)) == {"date": {"year": 2026, "month": 8, "day": 19}}


def test_list_point_date_reads_the_type_specific_container():
    extract = gh._list_point_date("dailyRestingHeartRate")
    point = {"dailyRestingHeartRate": {"date": {"year": 2026, "month": 8, "day": 19}, "beatsPerMinute": "57"}}
    assert extract(point) == date(2026, 8, 19)
    assert extract({"somethingElse": {}}) is None


def test_sleep_is_attributed_to_the_local_wake_up_date(monkeypatch):
    """A session ending 23:30 UTC is already the next day in Vienna, and
    the Google Health app files it under the morning you wake up."""
    monkeypatch.setattr(settings, "health_local_tz", "Europe/Vienna")
    extract = gh._local_interval_date("sleep", "endTime", fallback="startTime")
    point = {"sleep": {"interval": {"startTime": "2026-08-18T21:00:00Z", "endTime": "2026-08-18T23:30:00Z"}}}
    assert extract(point) == date(2026, 8, 19)


def test_local_interval_date_falls_back_to_the_start():
    extract = gh._local_interval_date("sleep", "endTime", fallback="startTime")
    point = {"sleep": {"interval": {"startTime": "2026-08-19T06:00:00Z"}}}
    assert extract(point) == date(2026, 8, 19)
    assert extract({"sleep": {"interval": {}}}) is None


# --- _sleep_minutes ---------------------------------------------------------


def test_sleep_minutes_sums_stages_and_excludes_awake():
    point = {
        "stages": [
            {"type": "LIGHT", "startTime": "2026-08-18T22:00:00Z", "endTime": "2026-08-18T23:00:00Z"},
            {"type": "AWAKE", "startTime": "2026-08-18T23:00:00Z", "endTime": "2026-08-18T23:30:00Z"},
            {"type": "DEEP", "startTime": "2026-08-18T23:30:00Z", "endTime": "2026-08-19T00:30:00Z"},
        ]
    }
    assert gh._sleep_minutes(point) == pytest.approx(120.0)


def test_sleep_minutes_falls_back_to_the_interval_without_stages():
    point = {"interval": {"startTime": "2026-08-18T22:00:00Z", "endTime": "2026-08-19T06:00:00Z"}}
    assert gh._sleep_minutes(point) == pytest.approx(480.0)


def test_sleep_minutes_of_an_all_awake_session():
    point = {
        "stages": [
            {"type": "AWAKE", "startTime": "2026-08-18T22:00:00Z", "endTime": "2026-08-18T23:00:00Z"},
        ]
    }
    assert gh._sleep_minutes(point) is None


def test_sleep_minutes_skips_stages_missing_a_bound():
    point = {"stages": [{"type": "LIGHT", "startTime": "2026-08-18T22:00:00Z"}]}
    assert gh._sleep_minutes(point) is None


def test_sleep_minutes_without_any_usable_data():
    assert gh._sleep_minutes({}) is None
    assert gh._sleep_minutes({"interval": {}}) is None


# --- _fetch_rollup chunking -------------------------------------------------


def test_rollup_requests_are_chunked_under_the_api_cap(monkeypatch):
    """dailyRollUp 400s with INVALID_ROLLUP_QUERY_DURATION once the span
    passes 90 days, so a 200-day backfill must arrive as several requests
    that each stay under the cap and together cover the range exactly."""
    calls: list[tuple[date, date]] = []

    def fake_post(_token, _url, body):
        start, end = body["range"]["start"]["date"], body["range"]["end"]["date"]
        calls.append((date(**dict(start)), date(**dict(end))))
        return {"rollupDataPoints": [{"marker": len(calls)}]}

    monkeypatch.setattr(gh, "_post", fake_post)
    points = gh._fetch_rollup("token", "steps", date(2026, 1, 1), date(2026, 7, 19))  # 200 days

    assert len(calls) > 1
    assert all((end - start).days <= gh.MAX_ROLLUP_SPAN_DAYS for start, end in calls)
    assert calls[0][0] == date(2026, 1, 1)
    assert calls[-1][1] == date(2026, 7, 19)
    # Contiguous, no gaps and no overlaps.
    for (_, prev_end), (next_start, _) in zip(calls, calls[1:], strict=False):
        assert (next_start - prev_end).days == 1
    assert len(points) == len(calls)


def test_a_single_short_range_is_one_request(monkeypatch):
    calls = []
    monkeypatch.setattr(gh, "_post", lambda *a: calls.append(a) or {"rollupDataPoints": []})
    gh._fetch_rollup("token", "steps", date(2026, 8, 1), date(2026, 8, 20))
    assert len(calls) == 1


# --- _fetch_list pagination -------------------------------------------------


def _page(dates, token=None):
    points = [{"x": {"date": {"year": d.year, "month": d.month, "day": d.day}}} for d in dates]
    return {"dataPoints": points, **({"nextPageToken": token} if token else {})}


def test_list_stops_once_a_page_falls_before_the_window(monkeypatch):
    """Points come back most-recent-first, so once a whole page predates
    the window there is nothing newer behind it - continuing would re-read
    years of history on every hourly sync."""
    pages = [
        _page([date(2026, 8, 19), date(2026, 8, 18)], token="p2"),
        _page([date(2026, 1, 2), date(2026, 1, 1)], token="p3"),
        _page([date(2025, 1, 1)], token="p4"),
    ]
    seen = []

    def fake_get(_token, _url, params):
        seen.append(params.get("pageToken"))
        return pages[len(seen) - 1]

    monkeypatch.setattr(gh, "_get", fake_get)
    points = gh._fetch_list("token", "daily-resting-heart-rate", gh._list_point_date("x"), date(2026, 8, 1))

    assert seen == [None, "p2"]  # stopped after the page that predates the window
    assert len(points) == 4


def test_list_follows_pages_while_they_are_inside_the_window(monkeypatch):
    pages = [
        _page([date(2026, 8, 19)], token="p2"),
        _page([date(2026, 8, 18)], token="p3"),
        _page([date(2026, 8, 17)]),  # no token: last page
    ]
    seen = []

    def fake_get(_token, _url, params):
        seen.append(params.get("pageToken"))
        return pages[len(seen) - 1]

    monkeypatch.setattr(gh, "_get", fake_get)
    points = gh._fetch_list("token", "sleep", gh._list_point_date("x"), date(2026, 8, 1))

    assert seen == [None, "p2", "p3"]
    assert len(points) == 3


def test_list_respects_the_runaway_cap(monkeypatch):
    monkeypatch.setattr(settings, "health_list_max_pages", 3)
    monkeypatch.setattr(gh, "_get", lambda *a: _page([date(2026, 8, 19)], token="more"))
    points = gh._fetch_list("token", "exercise", gh._list_point_date("x"), date(2026, 8, 1))
    assert len(points) == 3


def test_list_handles_an_empty_first_page(monkeypatch):
    monkeypatch.setattr(gh, "_get", lambda *a: {"dataPoints": []})
    assert gh._fetch_list("token", "sleep", gh._list_point_date("x"), date(2026, 8, 1)) == []
