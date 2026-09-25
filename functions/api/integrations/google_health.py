"""api/integrations/google_health.py — Google Health API adapter.

Uses its own OAuth token ("google_health", requested via
/oauth/google/login?target=health) — confirmed by live testing that
health.googleapis.com 403s (DISALLOWED_OAUTH_SCOPES) any token whose
scope list includes anything outside its own googlehealth.* domain, so
it can't share a token with Calendar. See google_oauth.py.

Two request shapes, confirmed against live responses (2026-07-16):

- steps, weight: `dailyRollUp` (one POST per type, pre-aggregated per
  day). `range.start`/`range.end` are CivilDateTime {"date": {y,m,d}}
  — NOT the flat civilStartTime shape the *response* uses.
- resting HR, HRV, sleep, VO2max: `dailyRollUp` returns
  UNSUPPORTED_DATA_TYPE_ACTION for these — only `list` is supported, so
  we page raw dataPoints and aggregate client-side. Each type nests its
  fields under a type-specific key (e.g. "dailyRestingHeartRate")
  containing a {"date": {...}} object, except sleep which uses
  {"interval": {"startTime", "endTime"}, "stages": [...]}.

Confirmed field names per type (all int64-like fields come back as
JSON strings, e.g. `"beatsPerMinute": "57"`):
    steps.countSum                                           (count)
    weight.weightGramsAvg                                    (grams — divide by 1000)
    dailyRestingHeartRate.beatsPerMinute                      (bpm)
    dailyHeartRateVariability.averageHeartRateVariabilityMilliseconds
    dailyVo2Max.vo2Max
    sleep.stages[].{type, startTime, endTime}                 (sum non-AWAKE durations)

Every raw point is kept in `daily_health.raw` regardless, so a wrong
extraction never loses data — it's just wrong until fixed.

Intraday heart rate (ADR-020) is the one part of this module that has NOT
been confirmed against a live response. It is written from the published
reference on 2026-09-08 — `heart-rate` and `time-in-heart-rate-zone` data
types, `heartRate.{sampleTime.physicalTime, beatsPerMinute}` and
`timeInHeartRateZone.{interval, heartRateZone, durationMillis}` — and it
is deliberately built to fail soft: an unusable filter falls back to
paging, a data type that 400s is skipped, and a session simply ends up
with no trace rather than the sync failing. Confirm the field names
against a real response and update this note with the date, the way the
types above record theirs.
"""

from __future__ import annotations

import logging
from datetime import UTC, date, datetime, timedelta
from zoneinfo import ZoneInfo

import requests

from api.config import settings
from api.integrations.google_oauth import get_valid_access_token

logger = logging.getLogger("api.integrations.google_health")

HEALTH_API_BASE = "https://health.googleapis.com/v4"

# Sleep sessions are keyed by wake-up date in the Google Health app itself
# (a session starting ~22:xx UTC is already past midnight in most of
# Europe, so its UTC calendar date is one day behind what the app shows
# as "today"). Convert to local time before taking .date() so our
# attribution matches what the user actually sees. Configured via
# settings.health_local_tz.

# dailyRollUp-capable types: column -> (kebab-case type id, response key, value field)
ROLLUP_TYPES: dict[str, tuple[str, str, str]] = {
    "steps": ("steps", "steps", "countSum"),
    "weight_kg": ("weight", "weight", "weightGramsAvg"),
}

# list-only types: column -> (kebab-case type id, response key, value field)
LIST_TYPES: dict[str, tuple[str, str, str]] = {
    "resting_hr": ("daily-resting-heart-rate", "dailyRestingHeartRate", "beatsPerMinute"),
    "hrv_ms": (
        "daily-heart-rate-variability",
        "dailyHeartRateVariability",
        "averageHeartRateVariabilityMilliseconds",
    ),
    "vo2max": ("daily-vo2-max", "dailyVo2Max", "vo2Max"),
}

SLEEP_DATA_TYPE = "sleep"

# Per-session workout data (confirmed live 2026-08-19: real data going back
# weeks, with per-session exerciseType, averageHeartRateBeatsPerMinute, and
# activeZoneMinutes under `exercise.metricsSummary`). Google's own "Cardio
# Load" score (shown in the Fitbit app) is NOT exposed anywhere in this API
# — checked ~20 plausible data-type ids (cardio-load, training-effect,
# epoc, heart-points, ...), all 400 INVALID_ARGUMENT, and it's not a field
# on the exercise data point either. Active Zone Minutes is the closest
# real, HR-based substitute this API actually gives us.
EXERCISE_DATA_TYPE = "exercise"

def local_tz() -> ZoneInfo:
    return ZoneInfo(settings.health_local_tz)


def _civil_date(d: date) -> dict:
    """CivilDateTime per the RPC reference — {"date": {year,month,day}},
    time omitted. This is the *request* shape for range.start/range.end;
    the response's civilStartTime/civilEndTime nest the same thing one
    level deeper (see _rollup_date)."""
    return {"date": {"year": d.year, "month": d.month, "day": d.day}}


def as_number(value) -> float | None:
    """Google serializes int64 fields (e.g. countSum, beatsPerMinute) as
    JSON strings to avoid JS precision loss — coerce numeric strings too.

    Public because api/services/exercises.py reads the same stored payloads
    back out of `daily_health.raw` and has to apply the same rule; a second
    copy of it would be a second place for the bool/str edge cases to drift."""
    if isinstance(value, bool):
        return None
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        try:
            return float(value)
        except ValueError:
            return None
    return None


def _get(access_token: str, url: str, params: dict) -> dict:
    resp = requests.get(url, headers={"Authorization": f"Bearer {access_token}"}, params=params, timeout=30)
    resp.raise_for_status()
    return resp.json()


def _post(access_token: str, url: str, body: dict) -> dict:
    resp = requests.post(url, headers={"Authorization": f"Bearer {access_token}"}, json=body, timeout=30)
    resp.raise_for_status()
    return resp.json()


# Confirmed live (2026-08-19): dailyRollUp 400s with INVALID_ROLLUP_QUERY_DURATION
# once window_size_days * page_size (= the date span, at windowSizeDays=1)
# exceeds 90 days — "days_back=90" alone already tips over this since
# fetch_all_daily_metrics adds one more day to include today. Stay one
# under the cap per chunk so an inclusive [start, end] span never hits it.
MAX_ROLLUP_SPAN_DAYS = 89


def _fetch_rollup(access_token: str, data_type: str, date_from: date, date_to: date) -> list[dict]:
    """Chunked so a >90-day request (e.g. a manual 90-day backfill) doesn't
    silently fail the whole fetch for this data type."""
    points: list[dict] = []
    chunk_start = date_from
    while chunk_start <= date_to:
        chunk_end = min(chunk_start + timedelta(days=MAX_ROLLUP_SPAN_DAYS), date_to)
        body = {
            "range": {"start": _civil_date(chunk_start), "end": _civil_date(chunk_end)},
            "windowSizeDays": 1,
        }
        resp = _post(
            access_token,
            f"{HEALTH_API_BASE}/users/me/dataTypes/{data_type}/dataPoints:dailyRollUp",
            body,
        )
        points.extend(resp.get("rollupDataPoints", []))
        chunk_start = chunk_end + timedelta(days=1)
    return points


def _rollup_date(rollup_point: dict) -> date | None:
    start = rollup_point.get("civilStartTime", {}).get("date")
    if not start:
        return None
    return date(start["year"], start["month"], start["day"])


# Points come back most-recent-first, so a single page (100, or 200 for
# `exercise`) covers a routine 30-day sync but silently truncates a backfill
# — confirmed live: `exercise` alone has well over ten pages of history.
# Rather than guess a page count, page until a whole page falls before the
# window we are syncing, with a hard cap purely as a runaway guard.
# settings.health_list_max_pages is the runaway guard.


def _list_point_date(response_key: str):
    """Date extractor for the LIST_TYPES shape: the type-specific container
    holds a {"date": {year, month, day}} object."""

    def extract(point: dict) -> date | None:
        date_obj = point.get(response_key, {}).get("date")
        if not date_obj:
            return None
        return date(date_obj["year"], date_obj["month"], date_obj["day"])

    return extract


def _local_interval_date(container_key: str, field: str, fallback: str | None = None):
    """Date extractor for the interval-shaped types (sleep, exercise), read in
    local time — see HEALTH_LOCAL_TZ for why UTC misattributes these."""

    def extract(point: dict) -> date | None:
        interval = point.get(container_key, {}).get("interval", {})
        stamp = interval.get(field) or (interval.get(fallback) if fallback else None)
        if not stamp:
            return None
        return datetime.fromisoformat(stamp).astimezone(local_tz()).date()

    return extract


def _fetch_list(
    access_token: str,
    data_type: str,
    point_date,
    oldest_needed: date,
    page_size: int = 100,
) -> list[dict]:
    """Page the most-recent-first dataPoints feed until it runs past
    `oldest_needed`.

    No working server-side date filter was found for these types (every
    attempted `filter` member name 400'd), so the window is applied here and
    again by the caller.
    """
    url = f"{HEALTH_API_BASE}/users/me/dataTypes/{data_type}/dataPoints"
    points: list[dict] = []
    page_token: str | None = None

    for _page in range(settings.health_list_max_pages):
        params: dict = {"pageSize": page_size}
        if page_token:
            params["pageToken"] = page_token

        resp = _get(access_token, url, params)
        page_points = resp.get("dataPoints", [])
        points.extend(page_points)

        page_token = resp.get("nextPageToken")
        if not page_token or not page_points:
            return points

        # Every dated point on this page is already older than the window,
        # so nothing newer can appear on the pages behind it.
        dates = [d for d in (point_date(p) for p in page_points) if d is not None]
        if dates and max(dates) < oldest_needed:
            return points

    logger.warning(
        "Health data type %r hit the %d-page cap before reaching %s — raise "
        "HEALTH_LIST_MAX_PAGES if this is a long backfill.",
        data_type,
        settings.health_list_max_pages,
        oldest_needed.isoformat(),
    )
    return points


def _sleep_minutes(sleep_point: dict) -> float | None:
    stages = sleep_point.get("stages")
    if not stages:
        interval = sleep_point.get("interval", {})
        start, end = interval.get("startTime"), interval.get("endTime")
        if not start or not end:
            return None
        delta = datetime.fromisoformat(end) - datetime.fromisoformat(start)
        return delta.total_seconds() / 60

    total_seconds = 0.0
    for stage in stages:
        if stage.get("type") == "AWAKE":
            continue
        start, end = stage.get("startTime"), stage.get("endTime")
        if not start or not end:
            continue
        total_seconds += (datetime.fromisoformat(end) - datetime.fromisoformat(start)).total_seconds()
    return total_seconds / 60 if total_seconds else None


def fetch_all_daily_metrics(days_back: int | None = None) -> dict[date, dict]:
    """Fetch every configured metric and merge into one dict keyed by
    date: {date: {"steps": 8123, "resting_hr": 52, ..., "raw": {...}}}."""
    days_back = settings.health_sync_days_back if days_back is None else days_back
    access_token = get_valid_access_token("health")
    # Local date, not UTC — UTC "today" lags local by a few hours overnight
    # in Vienna, which would filter out freshly-synced entries dated
    # "today" locally until UTC catches up.
    today = datetime.now(local_tz()).date()
    date_from = today - timedelta(days=days_back)
    date_to = today + timedelta(days=1)

    by_date: dict[date, dict] = {}

    def _row(d: date) -> dict:
        return by_date.setdefault(d, {"raw": {}})

    for column, (data_type, response_key, value_field) in ROLLUP_TYPES.items():
        try:
            points = _fetch_rollup(access_token, data_type, date_from, date_to)
        except requests.HTTPError as exc:
            logger.warning("Health data type %r (rollup) failed: %s", data_type, exc)
            continue

        for point in points:
            d = _rollup_date(point)
            if d is None:
                continue
            row = _row(d)
            row["raw"][data_type] = point

            raw_value = point.get(response_key, {}).get(value_field)
            value = as_number(raw_value)
            if value is None:
                continue
            if data_type == "weight":
                value /= 1000  # grams -> kg
            row[column] = value

    for column, (data_type, response_key, value_field) in LIST_TYPES.items():
        point_date = _list_point_date(response_key)
        try:
            points = _fetch_list(access_token, data_type, point_date, date_from)
        except requests.HTTPError as exc:
            logger.warning("Health data type %r (list) failed: %s", data_type, exc)
            continue

        for point in points:
            d = point_date(point)
            if d is None or d < date_from or d > today:
                continue
            container = point.get(response_key, {})

            row = _row(d)
            row["raw"][data_type] = point

            value = as_number(container.get(value_field))
            if value is not None:
                row[column] = value

    # Keyed by wake-up date (Fitbit/Google Health's own convention — "last
    # night's sleep" shows under the morning you check it), in local time so a
    # bedtime just after local midnight isn't attributed to the wrong day by a
    # UTC read of the timestamp.
    sleep_point_date = _local_interval_date(SLEEP_DATA_TYPE, "endTime", fallback="startTime")
    try:
        sleep_points = _fetch_list(access_token, SLEEP_DATA_TYPE, sleep_point_date, date_from)
    except requests.HTTPError as exc:
        logger.warning("Health data type %r (list) failed: %s", SLEEP_DATA_TYPE, exc)
        sleep_points = []

    for point in sleep_points:
        sleep_data = point.get("sleep", {})
        d = sleep_point_date(point)
        if d is None or d < date_from or d > today:
            continue

        row = _row(d)
        row["raw"][SLEEP_DATA_TYPE] = point

        minutes = _sleep_minutes(sleep_data)
        if minutes is not None:
            row["sleep_minutes"] = minutes

    exercise_point_date = _local_interval_date(EXERCISE_DATA_TYPE, "startTime")
    try:
        exercise_points = _fetch_list(
            access_token, EXERCISE_DATA_TYPE, exercise_point_date, date_from, page_size=200
        )
    except requests.HTTPError as exc:
        logger.warning("Health data type %r (list) failed: %s", EXERCISE_DATA_TYPE, exc)
        exercise_points = []

    for point in exercise_points:
        exercise = point.get("exercise", {})
        d = exercise_point_date(point)
        if d is None or d < date_from or d > today:
            continue

        row = _row(d)
        row["raw"].setdefault(EXERCISE_DATA_TYPE, []).append(point)

        azm = as_number(exercise.get("metricsSummary", {}).get("activeZoneMinutes")) or 0.0
        # Present (even at 0) marks the day as "watch tracked a session" —
        # distinct from no exercise data at all, which stays unset so the
        # training-load fallback (flat estimate from minutes played) knows
        # to kick in. See training_load.py.
        row["active_zone_minutes"] = row.get("active_zone_minutes", 0.0) + azm

    return by_date


# --- intraday heart rate, per session (ADR-020) ------------------------------
#
# Written from the published reference on 2026-09-08, NOT confirmed live —
# see the module docstring. `heart-rate` is a *sample* type: one reading
# every few seconds while a workout is running, so a day holds tens of
# thousands of points and only a session's own window is ever wanted.
#
# The list method takes an AIP-160 `filter`, whose field paths are the
# proto's snake_case names rather than the JSON camelCase ones. The daily
# types in this module have no working filter at all (every member name
# tried in 2026-07 400'd), so this cannot be assumed to work either — hence
# `_windowed_points`, which falls back to paging the unfiltered feed and
# remembers per data type that the filter was rejected, so the wasted
# request is spent once per process rather than once per session.

HEART_RATE_DATA_TYPE = "heart-rate"
HEART_RATE_KEY = "heartRate"
TIME_IN_ZONE_DATA_TYPE = "time-in-heart-rate-zone"
TIME_IN_ZONE_KEY = "timeInHeartRateZone"

# Data types whose `filter` this process has already seen rejected.
_FILTER_REJECTED: set[str] = set()


def _rfc3339(moment: datetime) -> str:
    """UTC, seconds precision, `Z` suffix — the shape the filter examples use.

    A naive datetime is read as UTC rather than refused: the caller is
    working from stored session timestamps, and a session with no offset is
    already unplaceable for coverage (services/sessions.py::placed_start),
    so guessing here changes nothing that is otherwise right."""
    if moment.tzinfo is None:
        return moment.strftime("%Y-%m-%dT%H:%M:%SZ")
    return moment.astimezone(UTC).strftime("%Y-%m-%dT%H:%M:%SZ")


def _windowed_points(
    access_token: str,
    data_type: str,
    filter_expr: str,
    point_time,
    start: datetime,
    end: datetime,
) -> list[dict]:
    """Every point of `data_type` between `start` and `end`, newest first.

    Asks the server to do the windowing and, if it will not, does it here
    instead. The client-side window is applied either way — a filter that
    is accepted but means something slightly different from what we think
    would otherwise put a neighbouring session's readings on this session's
    chart, which is the one wrong answer that would look entirely normal.
    """
    url = f"{HEALTH_API_BASE}/users/me/dataTypes/{data_type}/dataPoints"
    use_filter = data_type not in _FILTER_REJECTED
    points: list[dict] = []
    page_token: str | None = None

    for _page in range(settings.health_hr_max_pages):
        params: dict = {"pageSize": settings.health_hr_page_size}
        if use_filter:
            params["filter"] = filter_expr
        if page_token:
            params["pageToken"] = page_token

        try:
            resp = _get(access_token, url, params)
        except requests.HTTPError as exc:
            status = exc.response.status_code if exc.response is not None else None
            if not use_filter or status not in (400, 404):
                raise
            # The filter, not the data type, is what was rejected: drop it,
            # note it for the rest of the process, and start the fetch again
            # from the top of the unfiltered feed.
            logger.warning(
                "Health data type %r rejected the time filter (%s); paging unfiltered instead.",
                data_type,
                status,
            )
            _FILTER_REJECTED.add(data_type)
            use_filter = False
            page_token = None
            points = []
            continue

        page_points = resp.get("dataPoints", [])
        points.extend(page_points)
        page_token = resp.get("nextPageToken")
        if not page_token or not page_points:
            break

        # Newest first, so once a whole page sits before the window there is
        # nothing left behind it worth reading.
        times = [t for t in (point_time(p) for p in page_points) if t is not None]
        if times and max(times) < start:
            break
    else:
        logger.warning(
            "Health data type %r hit the %d-page cap for the window %s..%s.",
            data_type,
            settings.health_hr_max_pages,
            _rfc3339(start),
            _rfc3339(end),
        )

    inside = []
    for point in points:
        moment = point_time(point)
        if moment is not None and start <= moment <= end:
            inside.append(point)
    return inside


def _sample_time(point: dict) -> datetime | None:
    stamp = point.get(HEART_RATE_KEY, {}).get("sampleTime", {}).get("physicalTime")
    if not isinstance(stamp, str):
        return None
    try:
        moment = datetime.fromisoformat(stamp.replace("Z", "+00:00"))
    except ValueError:
        return None
    return moment if moment.tzinfo else moment.replace(tzinfo=UTC)


def _zone_interval_start(point: dict) -> datetime | None:
    stamp = point.get(TIME_IN_ZONE_KEY, {}).get("interval", {}).get("startTime")
    if not isinstance(stamp, str):
        return None
    try:
        moment = datetime.fromisoformat(stamp.replace("Z", "+00:00"))
    except ValueError:
        return None
    return moment if moment.tzinfo else moment.replace(tzinfo=UTC)


def fetch_heart_rate_samples(start: datetime, end: datetime) -> list[tuple[datetime, int]]:
    """One session's heart rate readings, oldest first.

    Returns `(when, bpm)` pairs. The caller turns them into offsets from the
    session start before storing (ADR-020) — that conversion is not done
    here because this module's job ends at "what Google said"."""
    access_token = get_valid_access_token("health")
    points = _windowed_points(
        access_token,
        HEART_RATE_DATA_TYPE,
        f'heart_rate.sample_time.physical_time >= "{_rfc3339(start)}" AND '
        f'heart_rate.sample_time.physical_time <= "{_rfc3339(end)}"',
        _sample_time,
        start,
        end,
    )

    samples: list[tuple[datetime, int]] = []
    for point in points:
        moment = _sample_time(point)
        bpm = as_number(point.get(HEART_RATE_KEY, {}).get("beatsPerMinute"))
        # A zero is a dropped reading, not a stopped heart. Both it and a
        # missing bpm are skipped rather than plotted.
        if moment is None or not bpm:
            continue
        samples.append((moment, round(bpm)))

    samples.sort(key=lambda s: s[0])
    return samples


def fetch_time_in_zones(start: datetime, end: datetime) -> dict[str, float]:
    """Seconds per Google heart rate zone over a session, keyed by its own
    enum name (FAT_BURN / CARDIO / PEAK).

    This is what the Google Health app's "time in each zone" bars are drawn
    from, which is why it is fetched at all: the same minutes could be
    counted off the samples here, but only against zone boundaries this
    dashboard derived itself (api/analysis/heart_rate.py), and two answers
    to "how long was I in cardio" is worse than one round trip.

    Best-effort. An empty dict means the type or its filter was not usable,
    and the caller falls back to counting the samples.
    """
    access_token = get_valid_access_token("health")
    points = _windowed_points(
        access_token,
        TIME_IN_ZONE_DATA_TYPE,
        f'time_in_heart_rate_zone.interval.start_time >= "{_rfc3339(start)}" AND '
        f'time_in_heart_rate_zone.interval.start_time <= "{_rfc3339(end)}"',
        _zone_interval_start,
        start,
        end,
    )

    seconds: dict[str, float] = {}
    for point in points:
        zone_point = point.get(TIME_IN_ZONE_KEY, {})
        zone = zone_point.get("heartRateZone")
        millis = as_number(zone_point.get("durationMillis"))
        if not isinstance(zone, str) or millis is None:
            continue
        seconds[zone] = seconds.get(zone, 0.0) + millis / 1000
    return seconds
