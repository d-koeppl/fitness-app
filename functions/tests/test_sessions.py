"""Pulling individual sessions back out of a stored daily_health.raw blob.

Pure — `sessions_for_day` takes the JSON, not a database — so these run
without TEST_DATABASE_URL. The endpoint that wraps it is covered in
test_api.py, and so is the coverage rule that reads these start times.

The payload shape here is the one confirmed live on 2026-08-19 (see
api/integrations/google_health.py): int64-ish fields arrive as JSON
strings, the interval carries RFC-3339 timestamps with an offset, and the
per-session numbers hang off `metricsSummary`.
"""

from __future__ import annotations

from datetime import date

from api.services.sessions import placed_start, sessions_for_day

DAY = date(2026, 8, 19)


def point(start: str, end: str, **summary) -> dict:
    return {
        "exercise": {
            "exerciseType": "RUNNING",
            "interval": {"startTime": start, "endTime": end},
            "metricsSummary": {"activeZoneMinutes": "34", "averageHeartRateBeatsPerMinute": "148", **summary},
        }
    }


def test_a_session_is_read_out_with_its_named_fields():
    (session,) = sessions_for_day(DAY, [point("2026-08-19T17:00:00+02:00", "2026-08-19T18:05:00+02:00")])

    assert session.date == DAY
    assert session.exercise_type == "RUNNING"
    assert session.duration_minutes == 65.0
    # Strings, per Google's int64 encoding — coerced, not passed through.
    assert session.active_zone_minutes == 34.0
    assert session.average_heart_rate == 148.0


def test_unknown_numeric_fields_survive_as_metrics():
    """The whole point of the open bag: a field nobody wrote code for still
    reaches the detail view."""
    (session,) = sessions_for_day(
        DAY,
        [
            point(
                "2026-08-19T17:00:00+02:00",
                "2026-08-19T18:00:00+02:00",
                distanceMeters="8412",
                calories=612,
            )
        ],
    )

    assert session.metrics == {"distanceMeters": 8412.0, "calories": 612.0}
    # ...and the two promoted ones are not repeated inside it.
    assert "activeZoneMinutes" not in session.metrics


def test_non_numeric_and_nested_summary_fields_are_dropped():
    (session,) = sessions_for_day(
        DAY,
        [
            point(
                "2026-08-19T17:00:00+02:00",
                "2026-08-19T18:00:00+02:00",
                someLabel="moderate",
                heartRateZones={"vigorous": 12},
            )
        ],
    )

    assert session.metrics == {}


def test_sessions_are_ordered_by_start_and_identified_by_that_order():
    """Ids must not depend on storage order — a re-sync rewrites `raw` and
    Google's paging does not promise the same sequence back."""
    later = point("2026-08-19T18:00:00+02:00", "2026-08-19T19:00:00+02:00")
    earlier = point("2026-08-19T07:00:00+02:00", "2026-08-19T07:30:00+02:00")

    forwards = sessions_for_day(DAY, [earlier, later])
    backwards = sessions_for_day(DAY, [later, earlier])

    assert [s.id for s in forwards] == ["2026-08-19#0", "2026-08-19#1"]
    assert [s.duration_minutes for s in forwards] == [30.0, 60.0]
    assert [(s.id, s.duration_minutes) for s in backwards] == [
        (s.id, s.duration_minutes) for s in forwards
    ]


def test_a_session_with_no_usable_interval_still_lists():
    """A missing duration is a gap on the card, not a dropped workout."""
    (session,) = sessions_for_day(DAY, [{"exercise": {"metricsSummary": {"activeZoneMinutes": 8}}}])

    assert session.duration_minutes is None
    assert session.start_ts is None
    assert session.active_zone_minutes == 8.0


def test_an_end_before_its_start_reports_no_duration():
    (session,) = sessions_for_day(DAY, [point("2026-08-19T18:00:00+02:00", "2026-08-19T17:00:00+02:00")])

    assert session.duration_minutes is None


def test_junk_in_the_raw_blob_is_skipped_rather_than_raising():
    """`raw` is a fidelity dump, so it is the one place a surprise shape is
    expected — a bad point must not take the endpoint down with it."""
    assert sessions_for_day(DAY, None) == []
    assert sessions_for_day(DAY, {"exercise": {}}) == []
    assert sessions_for_day(DAY, ["nonsense", {}, {"exercise": "not a dict"}]) == []


def test_a_tracked_session_defaults_to_carrying_no_estimate():
    """The scheduled-session fields are additive: a session read out of the
    watch's own payload is `source="tracked"` with nothing to skip and no
    estimate, so the API's "estimated or measured" distinction cannot be
    blurred by a parsing path that forgets to set them."""
    (session,) = sessions_for_day(DAY, [point("2026-08-19T17:00:00+02:00", "2026-08-19T18:00:00+02:00")])

    assert session.source == "tracked"
    assert session.ref_id is None
    assert session.title is None
    assert session.estimated_load is None
    assert session.skipped is False


def test_a_session_with_no_interval_cannot_be_placed():
    """`placed_start` is what the coverage rule asks before comparing a
    session to a scheduled time (ADR-015). No interval, no answer — and the
    caller then treats the session as covering its whole day rather than
    inventing load on top of one that was already measured."""
    (session,) = sessions_for_day(DAY, [{"exercise": {"metricsSummary": {"activeZoneMinutes": 8}}}])

    assert placed_start(session) is None


def test_a_session_with_an_offset_can_be_placed():
    (session,) = sessions_for_day(DAY, [point("2026-08-19T17:00:00+02:00", "2026-08-19T18:00:00+02:00")])

    placed = placed_start(session)
    assert placed is not None
    # Timezone-aware, or `covers` could not compare it to a kick-off at all.
    assert placed.utcoffset() is not None
