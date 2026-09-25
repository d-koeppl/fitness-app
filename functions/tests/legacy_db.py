"""A SQLAlchemy-Session-shaped shim over the Firestore store, for tests only.

The fitness-dashboard tests set up their data with `db.add(DrinkLog(...))`,
`db.flush()`, `db.get(Model, key)`, and then call the services with `db`.
Porting them by rewriting every setup line would put a hand-made change in
front of every assertion — exactly where a behaviour difference could hide.
Instead, the tests keep their bodies, and this shim turns those calls into
store writes:

- The model classes below accept the old keyword constructors (ids may be
  omitted, as Postgres assigned them).
- `add` writes the row and assigns an id where the old table had a serial
  one; `flush` re-writes everything added so far, so a test that mutates a
  row after adding it (`row.counted_report_id = report.id; db.flush()`)
  sees the change stored, as it did in Postgres.
- Any other attribute is the store's, so `drinks.pending(db)` and friends
  receive a working store.
"""

from __future__ import annotations

from datetime import UTC, datetime

from api.store import rows
from api.store.firestore import FirestoreStore


class _Model:
    _defaults: dict = {}

    def __init__(self, **kwargs):
        for name, value in {**self._defaults, **kwargs}.items():
            setattr(self, name, value)

    def __repr__(self) -> str:  # pragma: no cover - debugging aid
        return f"{type(self).__name__}({vars(self)})"


class DailyHealth(_Model):
    _defaults = {
        "steps": None,
        "resting_hr": None,
        "hrv_ms": None,
        "sleep_minutes": None,
        "active_kcal": None,
        "active_zone_minutes": None,
        "weight_kg": None,
        "vo2max": None,
        "source": "google_health",
        "raw": {},
        "updated_at": None,
    }


class CalendarEvent(_Model):
    _defaults = {
        "calendar_id": "primary",
        "title": None,
        "start_ts": None,
        "end_ts": None,
        "all_day": False,
        "category": None,
        "location": None,
        "raw": {},
        "updated_at": None,
    }


class MatchPerformance(_Model):
    _defaults = {
        "id": None,
        "match_date": None,
        "result": None,
        "started": False,
        "minutes_played": 0,
        "goals": 0,
        "yellow_card": False,
        "red_card": False,
        "created_at": None,
    }


class ExerciseHeartRate(_Model):
    _defaults = {"session_end": None, "samples": [], "zone_seconds": {}, "fetched_at": None}


class AiReport(_Model):
    _defaults = {
        "id": None,
        "created_at": None,
        "period_start": None,
        "period_end": None,
        "insights": {},
        "tokens_used": None,
    }


class DrinkLog(_Model):
    _defaults = {"id": None, "logged_at": None, "counted_report_id": None, "drank_on": None}


class SkippedActivity(_Model):
    _defaults = {"created_at": None}


class LegacySession:
    def __init__(self, store: FirestoreStore):
        self._store = store
        # (object, the fields as last written). Only objects whose fields
        # changed are written again on flush — re-writing everything would
        # resurrect a row a service had deleted in the meantime.
        self._tracked: list[tuple[object, dict]] = []

    def __getattr__(self, name):
        return getattr(self._store, name)

    # --- writes ---------------------------------------------------------------

    def add(self, obj: _Model) -> None:
        self._assign_id(obj)
        self._write(obj)
        self._track(obj)

    def add_all(self, objs) -> None:
        for obj in objs:
            self.add(obj)

    def _track(self, obj) -> None:
        self._tracked = [(o, s) for o, s in self._tracked if o is not obj]
        self._tracked.append((obj, dict(vars(obj))))

    def flush(self) -> None:
        for obj, written in list(self._tracked):
            if vars(obj) != written:
                self._write(obj)
                self._track(obj)

    def commit(self) -> None:
        self.flush()

    def refresh(self, obj: _Model) -> None:
        """Rows are written whole on add; nothing to reload."""

    def delete(self, obj) -> None:
        if isinstance(obj, (DrinkLog, rows.DrinkLog)):
            self._store.delete_drinks([obj.id])
        elif isinstance(obj, (CalendarEvent, rows.CalendarEvent)):
            self._store.delete_calendar_events([obj.id])
        else:  # pragma: no cover - only what the ported tests delete
            raise NotImplementedError(type(obj).__name__)
        self._tracked = [(o, s) for o, s in self._tracked if o is not obj]

    def _assign_id(self, obj: _Model) -> None:
        kinds = {DrinkLog: "drinks", AiReport: "reports", MatchPerformance: "matches"}
        kind = kinds.get(type(obj))
        if kind is None:
            return
        if getattr(obj, "id", None) is None:
            obj.id = self._store.next_ids(kind)[0]
        else:
            self._store.raise_counter(kind, obj.id)
        # Postgres filled these from the server clock on INSERT.
        if isinstance(obj, DrinkLog) and obj.logged_at is None:
            obj.logged_at = datetime.now(UTC)
        if isinstance(obj, AiReport) and obj.created_at is None:
            obj.created_at = datetime.now(UTC)

    def _write(self, obj) -> None:
        store = self._store
        fields = dict(vars(obj))
        if isinstance(obj, (DailyHealth, rows.DailyHealth)):
            store.put_health_days([rows.DailyHealth(**fields)])
        elif isinstance(obj, (CalendarEvent, rows.CalendarEvent)):
            store.put_calendar_events([rows.CalendarEvent(**fields)])
        elif isinstance(obj, (MatchPerformance, rows.MatchPerformance)):
            store.put_match(rows.MatchPerformance(**fields))
        elif isinstance(obj, (ExerciseHeartRate, rows.ExerciseHeartRate)):
            store.put_hr_trace(rows.ExerciseHeartRate(**fields))
        elif isinstance(obj, (AiReport, rows.AiReport)):
            store.put_report(rows.AiReport(**fields))
        elif isinstance(obj, (DrinkLog, rows.DrinkLog)):
            store.put_drinks([rows.DrinkLog(**fields)])
        elif isinstance(obj, SkippedActivity):
            store.set_skipped(obj.source, obj.ref_id, True, created_at=obj.created_at)
        else:  # pragma: no cover
            raise NotImplementedError(type(obj).__name__)

    # --- reads -------------------------------------------------------------------

    def get(self, model, key):
        """Like Session.get: the row, tracked, so a change then `flush()`
        is written back."""
        if model is DrinkLog:
            found = next((d for d in self._all_drinks() if d.id == key), None)
        elif model is DailyHealth:
            found = self._store.health_day(key)
        elif model is AiReport:
            found = next((o for o, _ in self._tracked if isinstance(o, AiReport) and o.id == key), None)
        elif model is ExerciseHeartRate:
            found = self._store.hr_trace(key)
        elif model is CalendarEvent:
            found = self._store.calendar_event(key)
        else:  # pragma: no cover
            raise NotImplementedError(model.__name__)
        if found is not None:
            self._track(found)
        return found

    def _all_drinks(self) -> list[rows.DrinkLog]:
        epoch = datetime(1970, 1, 1, tzinfo=UTC)
        return self._store.drinks_logged_between(epoch) + self._store.drinks_drank_between(epoch.date())
