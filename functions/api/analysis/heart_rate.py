"""api/analysis/heart_rate.py — one session's heart rate trace, as maths only.

Pure, like `training_load.py` and for the same reason: everything here
turns numbers into other numbers, and a wrong one would be invisible in a
chart that always looks plausible. No I/O, no database, no settings reads
— the callers pass what they have.

Three jobs:

**Zone boundaries.** The Google Health API reports how many *minutes* were
spent in each zone (`daily-heart-rate-zones`, `time-in-heart-rate-zone`)
but never the bpm the zones start at — `HeartRateZone` carries `zoneType`
and `minutesInZone` and nothing else, checked against the published
`DataPoint` schema on 2026-09-08. The dotted lines on the chart therefore
cannot be read off the API; they are derived here with the Karvonen
(heart-rate-reserve) method Google documents its own zones as using:

    reserve = max HR − resting HR
    moderate ("fat burn")  starts at resting + 0.40 · reserve
    vigorous ("cardio")    starts at resting + 0.60 · reserve
    peak                   starts at resting + 0.85 · reserve

Resting HR is measured — it is the `resting_hr` column the daily sync
already fills. Max HR is not, so it has to be configured; with neither a
measured max nor a birth year, `zone_bands` returns nothing and the chart
draws an uncoloured trace rather than a coloured guess.

**Time in each zone**, when Google's own answer is missing. Google's is
preferred wherever it was fetched (see `services/heart_rate.py`); this is
the fallback, and it is deliberately a separate function so the two can
never be confused for one another in a caller.

**Downsampling**, so a 2½-hour session's ~3 000 samples can be drawn on a
360 px phone chart. Every point that survives is a sample that was really
recorded — nothing is averaged into existence — and the highest and lowest
sample of each bucket always survive, because on this chart the peaks are
the point: they are what the zone colouring is about.
"""

from __future__ import annotations

from dataclasses import dataclass

# One sample: seconds since the session started, and the bpm read then.
# Offsets rather than timestamps because that is how they are stored — see
# ADR-020 and models/schema.py::ExerciseHeartRate.
Sample = tuple[int, int]

# --- zones ------------------------------------------------------------------

LIGHT = "light"
FAT_BURN = "fat_burn"
CARDIO = "cardio"
PEAK = "peak"

# Ascending, and the order the UI lists them in.
ZONE_ORDER: tuple[str, ...] = (LIGHT, FAT_BURN, CARDIO, PEAK)

# Google's `HeartRateZoneType` enum -> our name. There is no LIGHT member:
# the API only names the three scoring zones, and everything below the first
# of them is what the Google Health app shows as "light".
ZONE_FROM_GOOGLE: dict[str, str] = {
    "FAT_BURN": FAT_BURN,
    "CARDIO": CARDIO,
    "PEAK": PEAK,
}

# Fraction of heart-rate reserve each zone starts at. LIGHT has no floor —
# it is everything under FAT_BURN.
ZONE_FLOOR_FRACTION: dict[str, float] = {FAT_BURN: 0.40, CARDIO: 0.60, PEAK: 0.85}

# A gap this long or longer is the watch having stopped sampling, not a
# minute spent at the last bpm it saw. Credit it to nothing rather than
# handing one zone a dropout's worth of time. Google's own samples come
# every few seconds during a workout, so this is generous.
MAX_SAMPLE_GAP_SECONDS = 60


@dataclass(frozen=True)
class ZoneBand:
    """One zone and the bpm range it covers.

    `lower_bpm` is None only for LIGHT (it starts at zero) and `upper_bpm`
    only for PEAK (it has no ceiling) — the bounds are half-open upwards, so
    a bpm exactly on a boundary belongs to the higher zone, which is how
    "at least 85% of reserve" reads.
    """

    zone: str
    lower_bpm: int | None
    upper_bpm: int | None


def zone_bands(max_hr: float | None, resting_hr: float | None) -> list[ZoneBand]:
    """The four zones in bpm, or `[]` when they cannot be derived.

    Empty is a real answer and the callers render it: no max HR configured
    means no honest boundaries, and a chart with invented ones would be
    worse than a plain trace.
    """
    if not max_hr or not resting_hr:
        return []
    reserve = max_hr - resting_hr
    if reserve <= 0:
        return []

    floors = {zone: round(resting_hr + fraction * reserve) for zone, fraction in ZONE_FLOOR_FRACTION.items()}
    # A tiny reserve can round two zones onto the same bpm, which would make
    # a band that no reading can ever fall in. Push each one at least a beat
    # above the last so the bands stay strictly ascending.
    lower = 0
    for zone in (FAT_BURN, CARDIO, PEAK):
        lower = max(floors[zone], lower + 1)
        floors[zone] = lower

    return [
        ZoneBand(LIGHT, None, floors[FAT_BURN]),
        ZoneBand(FAT_BURN, floors[FAT_BURN], floors[CARDIO]),
        ZoneBand(CARDIO, floors[CARDIO], floors[PEAK]),
        ZoneBand(PEAK, floors[PEAK], None),
    ]


def zone_for(bpm: float, bands: list[ZoneBand]) -> str | None:
    """Which zone a reading falls in, or None when there are no bands."""
    match = None
    for band in bands:
        if band.lower_bpm is None or bpm >= band.lower_bpm:
            match = band.zone
    return match


def covered_seconds(samples: list[Sample]) -> float:
    """How long the trace actually covers, ignoring gaps.

    Not `last − first`: a watch that stopped sampling for twenty minutes did
    not measure those twenty minutes, and the difference is what stops the
    light-activity share (which is a subtraction — see
    services/heart_rate.py) from absorbing a dropout.
    """
    total = 0.0
    for (start, _), (next_start, _) in zip(samples, samples[1:], strict=False):
        gap = next_start - start
        if 0 < gap < MAX_SAMPLE_GAP_SECONDS:
            total += gap
    return total


def time_in_zones(samples: list[Sample], bands: list[ZoneBand]) -> dict[str, float]:
    """Seconds spent in each zone, derived from the trace itself.

    Only used when Google's own `time-in-heart-rate-zone` was not stored for
    the session — its numbers are what the phone app shows, and two
    different answers to the same question is the thing worth avoiding here.

    Each sample is credited with the time until the next one, so a stretch
    sampled sparsely counts for what it lasted rather than for how many
    readings it happens to hold. The last sample gets nothing: there is no
    next reading to say how long it went on for.
    """
    if not bands or len(samples) < 2:
        return {}

    seconds = {band.zone: 0.0 for band in bands}
    for (start, bpm), (next_start, _) in zip(samples, samples[1:], strict=False):
        gap = next_start - start
        if gap <= 0 or gap >= MAX_SAMPLE_GAP_SECONDS:
            continue
        zone = zone_for(bpm, bands)
        if zone is not None:
            seconds[zone] += gap
    return seconds


# --- shaping the trace for a chart -----------------------------------------


def downsample(samples: list[Sample], max_points: int) -> list[Sample]:
    """At most `max_points` samples, keeping every bucket's extremes.

    Bucketed by position and reduced to the lowest and highest reading of
    each bucket, in the order they were recorded. Two consequences worth
    stating, because they are why it is not a rolling average:

    - every point drawn is a reading the watch actually took, so a spike on
      the chart is a spike that happened;
    - the envelope survives. An average would sand the peaks off exactly
      where the zone colouring — and Active Zone Minutes with it — is
      decided.
    """
    if max_points < 2 or len(samples) <= max_points:
        return list(samples)

    # Two points come out of each bucket, so ask for half as many buckets.
    buckets = max_points // 2
    size = len(samples) / buckets
    out: list[Sample] = []
    for index in range(buckets):
        chunk = samples[round(index * size) : round((index + 1) * size)]
        if not chunk:
            continue
        low = min(chunk, key=lambda s: s[1])
        high = max(chunk, key=lambda s: s[1])
        if low == high:
            out.append(low)
        elif low[0] <= high[0]:
            out.extend([low, high])
        else:
            out.extend([high, low])
    return out


@dataclass(frozen=True)
class TraceSummary:
    """The three numbers under the chart. `average` is over the readings,
    not over time — the same thing Google's own per-session average is,
    and close enough on an evenly sampled trace that weighting it by gap
    would be precision the input does not have."""

    min_bpm: int
    max_bpm: int
    average_bpm: float


def summarize(samples: list[Sample]) -> TraceSummary | None:
    if not samples:
        return None
    values = [bpm for _, bpm in samples]
    return TraceSummary(
        min_bpm=min(values),
        max_bpm=max(values),
        average_bpm=round(sum(values) / len(values), 1),
    )


# --- the highest heart rate on record (ADR-039) -----------------------------

# How many consecutive readings must reach a bpm before it counts as the
# heart having got there. One is an optical sensor glitching — a lone 230
# in a trace of 180s — and it would raise the max for good, shifting every
# zone boundary upwards. Two in a row, a second or two apart, is a heart.
SUSTAINED_READINGS = 2


def sustained_peak(samples: list[Sample], readings: int = SUSTAINED_READINGS) -> int | None:
    """The highest bpm the trace held for `readings` consecutive samples,
    or None if it is shorter than that.

    It is the peak of the sliding minimum: each window of `readings`
    samples is only as high as its lowest reading, so a single spike never
    lifts one.
    """
    values = [bpm for _, bpm in samples]
    if readings < 1 or len(values) < readings:
        return None
    return max(min(values[i : i + readings]) for i in range(len(values) - readings + 1))
