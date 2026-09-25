"""api/services/health.py — reads over `daily_health` that are more than a
row lookup.

Right now that is one thing: the last value a not-measured-every-day metric
actually had. Weight and VO2 max only land on the days the user steps on
the scale or the watch re-estimates, so the daily rows are null in between.
A null there means "not measured today", not "unknown" — the last reading
is still the current one (ADR-018). Everything that shows a *current*
weight — the Today tile, the Health card, the daily report and the coach —
reads it from here, so the four cannot disagree about which day the number
came from.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date as date_type

from api.store.firestore import FirestoreStore

# The metrics that are carried forward, and the only ones. Steps, sleep,
# resting HR and HRV are measured every day the watch is worn, so a gap in
# those is a gap — repeating yesterday's night of sleep as today's would be
# inventing data, and the recovery score would then be scored on it.
SPARSE_METRICS = ("weight_kg", "vo2max")


@dataclass(frozen=True)
class Measurement:
    """One metric's last recorded value, and the day it was recorded. The
    date travels with the value everywhere: a weight from three days ago is
    fine to show as current, one from three months ago is not, and only the
    reader can judge that."""

    value: float
    date: date_type


def latest_measurements(
    store: FirestoreStore, metrics: tuple[str, ...] = SPARSE_METRICS
) -> dict[str, Measurement]:
    """The most recent non-null value of each of `metrics`, over the whole
    history rather than a window — the point is to survive a gap longer than
    whatever window the caller happens to be showing. Metrics that have never
    been recorded are absent from the result rather than present as None."""
    found: dict[str, Measurement] = {}
    # One walk back through the months for all metrics together, stopping
    # once each has a value. Cheap after a recent reading, and the cost is
    # bounded by how long the longest gap actually is.
    for row in store.health_days_desc():
        for name in metrics:
            value = getattr(row, name)
            if name not in found and value is not None:
                found[name] = Measurement(value=value, date=row.date)
        if len(found) == len(metrics):
            break
    return {name: found[name] for name in metrics if name in found}
