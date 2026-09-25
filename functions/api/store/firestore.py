"""api/store/firestore.py — every read and write the API makes, on Firestore.

The only module that talks to Firestore. Services call these methods
instead of building SQLAlchemy queries, so the layout below (ADR-031) can
change without touching them.

Layout, and why:

| Collection | Document | Holds |
| --- | --- | --- |
| `health_months` | `YYYY-MM` | `days.<YYYY-MM-DD>` → one DailyHealth |
| `calendar_months` | `YYYY-MM` (local start month) or `undated` | `events.<id>` → one CalendarEvent |
| `meta/calendar_index` | — | `months.<id>` → the bucket an event is in |
| `matches` | `<oefb_game_id>` | one MatchPerformance |
| `hr_traces` | `<session start, UTC ISO>` | one ExerciseHeartRate |
| `skips` | `<source>~<ref_id>` | one SkippedActivity |
| `reports` | `<id>` | one AiReport |
| `drinks` | `<id>` | one DrinkLog |
| `conversations/<id>/messages` | `<id>` | a Conversation and its messages |
| `gemini_usage` | `YYYY-MM-DD` (Pacific) | `requests.<model>` → count |
| `oauth_tokens` | `<provider>` | one OAuthToken |
| `push_devices` | SHA-256 of the FCM token | one PushDevice |
| `meta/counters` | — | the next integer id per kind |

Health days and calendar events are bucketed by month because the training
model reads all of history on every /training/status call: one document per
row would make that cost grow without bound, which the free tier cannot
carry. A month of health rows measured 283 KB at its largest (2026-09-25),
a quarter of the 1 MiB document limit. Everything else is small and read
in narrow slices, so it keeps one document per row.

Conventions: timestamps are Firestore timestamps (UTC); dates are
`YYYY-MM-DD` strings, which sort and range-query correctly; free-form
payloads (`raw`, `insights`) are JSON text, because Firestore rejects an
array directly inside an array and Google's payloads are not ours to shape.
Queries use only single-field indexes, which Firestore creates itself, and
do any further filtering in Python — the emulator does not enforce
composite indexes, so a query needing one would pass every test and fail
in production.
"""

from __future__ import annotations

import functools
import hashlib
import json
import os
from collections.abc import Iterable, Iterator
from datetime import UTC, date, datetime

from google.cloud import firestore
from google.cloud.firestore_v1 import FieldFilter
from google.cloud.firestore_v1.field_path import FieldPath

from api.store.rows import (
    AiReport,
    CalendarEvent,
    Conversation,
    ConversationMessage,
    DailyHealth,
    DrinkLog,
    ExerciseHeartRate,
    MatchPerformance,
    OAuthToken,
    PushDevice,
    SkippedActivity,
)

UNDATED = "undated"
_HEALTH_FIELDS = (
    "steps",
    "resting_hr",
    "hrv_ms",
    "sleep_minutes",
    "active_kcal",
    "active_zone_minutes",
    "weight_kg",
    "vo2max",
)


# --- value conversions ------------------------------------------------------


def _d(value: date | None) -> str | None:
    return value.isoformat() if value is not None else None


def _parse_d(value: str | None) -> date | None:
    return date.fromisoformat(value) if value else None


def _ts(value: datetime | None) -> datetime | None:
    if value is None:
        return None
    if value.tzinfo is None:
        raise ValueError(f"naive datetime {value!r}: store timestamps with a timezone")
    return value.astimezone(UTC)


def _parse_ts(value) -> datetime | None:
    # Firestore hands back DatetimeWithNanoseconds, already UTC-aware. Copy
    # the fields into a plain datetime rather than going through a float
    # timestamp, which can round a value onto the neighbouring second.
    if value is None:
        return None
    value = value.astimezone(UTC)
    return datetime(
        value.year,
        value.month,
        value.day,
        value.hour,
        value.minute,
        value.second,
        value.microsecond,
        tzinfo=UTC,
    )


def _json(value) -> str:
    return json.dumps(value, separators=(",", ":"), sort_keys=True, default=str)


def _month(day: date) -> str:
    return f"{day.year:04d}-{day.month:02d}"


def _months_between(first: date, last: date) -> list[str]:
    months: list[str] = []
    year, month = first.year, first.month
    while (year, month) <= (last.year, last.month):
        months.append(f"{year:04d}-{month:02d}")
        month += 1
        if month == 13:
            year, month = year + 1, 1
    return months


def _field(*parts: str) -> str:
    """A field path whose parts may hold '-', ':' or other characters that
    need backquoting (dates, calendar ids)."""
    return FieldPath(*parts).to_api_repr()


def _doc_id(value: str) -> str:
    # Document ids cannot contain '/', and '~' is our separator.
    return value.replace("%", "%25").replace("/", "%2F").replace("~", "%7E")


# --- row <-> document ---------------------------------------------------------


def _health_to_doc(row: DailyHealth) -> dict:
    doc = {name: getattr(row, name) for name in _HEALTH_FIELDS}
    doc.update(source=row.source, raw=_json(row.raw), updated_at=_ts(row.updated_at) or datetime.now(UTC))
    return doc


def _health_from_doc(day: str, doc: dict) -> DailyHealth:
    return DailyHealth(
        date=date.fromisoformat(day),
        **{name: doc.get(name) for name in _HEALTH_FIELDS},
        source=doc.get("source", "google_health"),
        raw=json.loads(doc.get("raw") or "{}"),
        updated_at=_parse_ts(doc.get("updated_at")),
    )


def _event_to_doc(event: CalendarEvent) -> dict:
    return {
        "calendar_id": event.calendar_id,
        "title": event.title,
        "start_ts": _ts(event.start_ts),
        "end_ts": _ts(event.end_ts),
        "all_day": event.all_day,
        "category": event.category,
        "location": event.location,
        "raw": _json(event.raw),
        "updated_at": _ts(event.updated_at) or datetime.now(UTC),
    }


def _event_from_doc(event_id: str, doc: dict) -> CalendarEvent:
    return CalendarEvent(
        id=event_id,
        calendar_id=doc.get("calendar_id", ""),
        title=doc.get("title"),
        start_ts=_parse_ts(doc.get("start_ts")),
        end_ts=_parse_ts(doc.get("end_ts")),
        all_day=bool(doc.get("all_day")),
        category=doc.get("category"),
        location=doc.get("location"),
        raw=json.loads(doc.get("raw") or "{}"),
        updated_at=_parse_ts(doc.get("updated_at")),
    )


def _match_from_doc(doc: dict) -> MatchPerformance:
    return MatchPerformance(
        id=doc["id"],
        oefb_game_id=doc["oefb_game_id"],
        match_date=_parse_d(doc.get("match_date")),
        opponent=doc["opponent"],
        home_away=doc["home_away"],
        result=doc.get("result"),
        started=bool(doc.get("started")),
        minutes_played=doc.get("minutes_played", 0),
        goals=doc.get("goals", 0),
        yellow_card=bool(doc.get("yellow_card")),
        red_card=bool(doc.get("red_card")),
        created_at=_parse_ts(doc.get("created_at")),
    )


def _trace_from_doc(doc: dict) -> ExerciseHeartRate:
    return ExerciseHeartRate(
        session_start=_parse_ts(doc["session_start"]),
        date=date.fromisoformat(doc["date"]),
        session_end=_parse_ts(doc.get("session_end")),
        samples=[list(pair) for pair in zip(doc.get("offsets", []), doc.get("bpm", []), strict=True)],
        zone_seconds=dict(doc.get("zone_seconds") or {}),
        fetched_at=_parse_ts(doc.get("fetched_at")),
    )


def _report_from_doc(doc: dict) -> AiReport:
    return AiReport(
        id=doc["id"],
        created_at=_parse_ts(doc["created_at"]),
        trigger=doc["trigger"],
        model=doc["model"],
        prompt_version=doc["prompt_version"],
        summary_md=doc["summary_md"],
        period_start=_parse_d(doc.get("period_start")),
        period_end=_parse_d(doc.get("period_end")),
        insights=json.loads(doc.get("insights") or "{}"),
        tokens_used=doc.get("tokens_used"),
    )


def _drink_from_doc(doc: dict) -> DrinkLog:
    return DrinkLog(
        id=doc["id"],
        logged_at=_parse_ts(doc["logged_at"]),
        counted_report_id=doc.get("counted_report_id"),
        drank_on=_parse_d(doc.get("drank_on")),
    )


def _conversation_from_doc(doc: dict) -> Conversation:
    return Conversation(
        id=doc["id"],
        title=doc.get("title", "New chat"),
        created_at=_parse_ts(doc.get("created_at")),
        updated_at=_parse_ts(doc.get("updated_at")),
        include=dict(doc.get("include") or {}),
        lookback_days=doc.get("lookback_days", 14),
        session_ids=list(doc.get("session_ids") or []),
        message_count=doc.get("message_count", 0),
    )


def _message_from_doc(doc: dict) -> ConversationMessage:
    return ConversationMessage(
        id=doc["id"],
        conversation_id=doc["conversation_id"],
        role=doc["role"],
        content=doc["content"],
        created_at=_parse_ts(doc.get("created_at")),
    )


def _drink_sort_key(row: DrinkLog) -> tuple[datetime, int]:
    return row.logged_at, row.id


class FirestoreStore:
    """See the module docstring for the layout. `local_tz` decides which
    month a calendar event is filed under; it must be the timezone the
    services group days in (settings.health_local_tz)."""

    def __init__(self, client: firestore.Client, local_tz):
        self._db = client
        self._tz = local_tz

    # --- ids ------------------------------------------------------------------

    def next_ids(self, kind: str, count: int = 1) -> list[int]:
        """`count` fresh integer ids for `kind`, from one counter per kind.

        Integers rather than Firestore's random ids because the API has
        always exposed them (`/coach/conversations/{id}`), and because drink
        order ties are broken by id (ADR-019).
        """
        ref = self._db.collection("meta").document("counters")

        @firestore.transactional
        def allocate(transaction) -> int:
            snapshot = ref.get(transaction=transaction)
            last = (snapshot.to_dict() or {}).get(kind, 0) if snapshot.exists else 0
            transaction.set(ref, {kind: last + count}, merge=True)
            return last

        last = allocate(self._db.transaction())
        return list(range(last + 1, last + count + 1))

    def raise_counter(self, kind: str, at_least: int) -> None:
        """Make sure the next id for `kind` is above `at_least` — for the
        migration, which writes rows with the ids Postgres gave them."""
        ref = self._db.collection("meta").document("counters")
        snapshot = ref.get()
        if (snapshot.to_dict() or {}).get(kind, 0) < at_least:
            ref.set({kind: at_least}, merge=True)

    # --- daily health -----------------------------------------------------------

    def _health_month_docs(
        self, first: date | None, last: date | None, descending: bool = False
    ) -> Iterator[tuple[str, dict]]:
        collection = self._db.collection("health_months")
        if first is not None and last is not None:
            months = _months_between(first, last)
            if descending:
                months.reverse()
            refs = [collection.document(m) for m in months]
            snapshots = {s.id: s for s in self._db.get_all(refs)}
            for month in months:
                snapshot = snapshots.get(month)
                if snapshot is not None and snapshot.exists:
                    yield month, snapshot.to_dict()
            return
        # Ordered by a `month` field rather than the document id: Firestore
        # cannot scan ids in descending order ("does not support descending
        # key scans"), and "newest first" is what latest_measurements needs.
        query = collection.order_by(
            "month", direction=firestore.Query.DESCENDING if descending else firestore.Query.ASCENDING
        )
        if first is not None:
            query = query.where(filter=FieldFilter("month", ">=", _month(first)))
        if last is not None:
            query = query.where(filter=FieldFilter("month", "<=", _month(last)))
        for snapshot in query.stream():
            yield snapshot.id, snapshot.to_dict()

    def health_days(self, first: date | None = None, last: date | None = None) -> list[DailyHealth]:
        """Every stored day in [first, last], oldest first. Either bound may
        be open; with both open this is the whole history."""
        rows: list[DailyHealth] = []
        for _, doc in self._health_month_docs(first, last):
            for day, fields in (doc.get("days") or {}).items():
                parsed = date.fromisoformat(day)
                if (first is None or parsed >= first) and (last is None or parsed <= last):
                    rows.append(_health_from_doc(day, fields))
        rows.sort(key=lambda row: row.date)
        return rows

    def health_days_desc(self, before: date | None = None) -> Iterator[DailyHealth]:
        """Stored days newest first, reading one month at a time — for
        readers that stop as soon as they have what they need."""
        for _, doc in self._health_month_docs(None, before, descending=True):
            days = sorted((doc.get("days") or {}).items(), reverse=True)
            for day, fields in days:
                row = _health_from_doc(day, fields)
                if before is None or row.date <= before:
                    yield row

    def health_day(self, day: date) -> DailyHealth | None:
        snapshot = self._db.collection("health_months").document(_month(day)).get()
        fields = ((snapshot.to_dict() or {}).get("days") or {}).get(day.isoformat())
        return _health_from_doc(day.isoformat(), fields) if fields is not None else None

    def put_health_days(self, rows: Iterable[DailyHealth]) -> None:
        """Insert or replace whole days. Rows for one month share a write."""
        by_month: dict[str, dict] = {}
        for row in rows:
            by_month.setdefault(_month(row.date), {})[_field("days", row.date.isoformat())] = _health_to_doc(
                row
            )
        for month, updates in by_month.items():
            ref = self._db.collection("health_months").document(month)
            # update() replaces each named day's map whole, so a field that
            # went from a value to null is really cleared; it needs the
            # document to exist, which the merge-set guarantees.
            ref.set({"month": month}, merge=True)
            ref.update(updates)

    # --- calendar --------------------------------------------------------------

    def _calendar_month(self, event: CalendarEvent) -> str:
        if event.start_ts is None:
            return UNDATED
        return _month(event.start_ts.astimezone(self._tz).date())

    def calendar_events(
        self, start: datetime | None = None, end: datetime | None = None, include_undated: bool = False
    ) -> list[CalendarEvent]:
        """Events with `start <= start_ts < end`, by start. Undated events
        (no start) only when asked, and then last."""
        collection = self._db.collection("calendar_months")
        if start is not None and end is not None:
            months = _months_between(start.astimezone(self._tz).date(), end.astimezone(self._tz).date())
            refs = [collection.document(m) for m in months]
            if include_undated:
                refs.append(collection.document(UNDATED))
            snapshots = [s for s in self._db.get_all(refs) if s.exists]
        else:
            snapshots = list(collection.stream())
        dated: list[CalendarEvent] = []
        undated: list[CalendarEvent] = []
        for snapshot in snapshots:
            for event_id, fields in (snapshot.to_dict().get("events") or {}).items():
                event = _event_from_doc(event_id, fields)
                if event.start_ts is None:
                    if include_undated:
                        undated.append(event)
                elif (start is None or event.start_ts >= start) and (end is None or event.start_ts < end):
                    dated.append(event)
        dated.sort(key=lambda e: (e.start_ts, e.id))
        return dated + undated

    def calendar_events_from(self, start: datetime, limit: int) -> list[CalendarEvent]:
        """The next `limit` events starting at or after `start`."""
        collection = self._db.collection("calendar_months")
        query = collection.where(
            filter=FieldFilter(
                FieldPath.document_id(), ">=", collection.document(_month(start.astimezone(self._tz).date()))
            )
        ).order_by(FieldPath.document_id())
        found: list[CalendarEvent] = []
        for snapshot in query.stream():
            if snapshot.id == UNDATED:
                continue
            events = [
                _event_from_doc(event_id, fields)
                for event_id, fields in (snapshot.to_dict().get("events") or {}).items()
            ]
            found.extend(e for e in events if e.start_ts is not None and e.start_ts >= start)
            found.sort(key=lambda e: (e.start_ts, e.id))
            if len(found) >= limit:
                break
        return found[:limit]

    def calendar_event(self, event_id: str) -> CalendarEvent | None:
        month = self._calendar_index().get(event_id)
        if month is None:
            return None
        snapshot = self._db.collection("calendar_months").document(month).get()
        fields = ((snapshot.to_dict() or {}).get("events") or {}).get(event_id)
        return _event_from_doc(event_id, fields) if fields is not None else None

    def _calendar_index(self) -> dict[str, str]:
        snapshot = self._db.collection("meta").document("calendar_index").get()
        return dict((snapshot.to_dict() or {}).get("months") or {})

    def put_calendar_events(self, events: Iterable[CalendarEvent]) -> None:
        """Insert or replace events, moving any whose start changed month
        out of the bucket it was in. One index read for the whole batch."""
        events = list(events)
        if not events:
            return
        index = self._calendar_index()
        batch = self._db.batch()
        writes = 0
        index_updates: dict[str, str] = {}
        by_month: dict[str, dict] = {}
        for event in events:
            month = self._calendar_month(event)
            previous = index.get(event.id)
            if previous is not None and previous != month:
                batch.update(
                    self._db.collection("calendar_months").document(previous),
                    {_field("events", event.id): firestore.DELETE_FIELD},
                )
                writes += 1
            by_month.setdefault(month, {})[_field("events", event.id)] = _event_to_doc(event)
            index_updates[_field("months", event.id)] = month
        for month, updates in by_month.items():
            ref = self._db.collection("calendar_months").document(month)
            batch.set(ref, {}, merge=True)
            batch.update(ref, updates)
            writes += 2
        index_ref = self._db.collection("meta").document("calendar_index")
        batch.set(index_ref, {}, merge=True)
        batch.update(index_ref, index_updates)
        if writes > 400:  # pragma: no cover - a sync writes tens, not hundreds
            raise ValueError("too many calendar writes for one batch; split the call")
        batch.commit()

    def delete_calendar_events(self, event_ids: Iterable[str]) -> None:
        index = self._calendar_index()
        batch = self._db.batch()
        index_updates = {}
        for event_id in event_ids:
            month = index.get(event_id)
            if month is None:
                continue
            batch.update(
                self._db.collection("calendar_months").document(month),
                {_field("events", event_id): firestore.DELETE_FIELD},
            )
            index_updates[_field("months", event_id)] = firestore.DELETE_FIELD
        if index_updates:
            batch.update(self._db.collection("meta").document("calendar_index"), index_updates)
            batch.commit()

    # --- matches ----------------------------------------------------------------

    def matches(self) -> list[MatchPerformance]:
        rows = [_match_from_doc(s.to_dict()) for s in self._db.collection("matches").stream()]
        return rows

    def matches_between(self, first: date, last: date) -> list[MatchPerformance]:
        query = (
            self._db.collection("matches")
            .where(filter=FieldFilter("match_date", ">=", first.isoformat()))
            .where(filter=FieldFilter("match_date", "<=", last.isoformat()))
        )
        rows = [_match_from_doc(s.to_dict()) for s in query.stream()]
        rows.sort(key=lambda m: (m.match_date, m.id))
        return rows

    def match(self, oefb_game_id: str) -> MatchPerformance | None:
        snapshot = self._db.collection("matches").document(_doc_id(oefb_game_id)).get()
        return _match_from_doc(snapshot.to_dict()) if snapshot.exists else None

    def put_match(self, row: MatchPerformance) -> None:
        self._db.collection("matches").document(_doc_id(row.oefb_game_id)).set(
            {
                "id": row.id,
                "oefb_game_id": row.oefb_game_id,
                "match_date": _d(row.match_date),
                "opponent": row.opponent,
                "home_away": row.home_away,
                "result": row.result,
                "started": row.started,
                "minutes_played": row.minutes_played,
                "goals": row.goals,
                "yellow_card": row.yellow_card,
                "red_card": row.red_card,
                "created_at": _ts(row.created_at) or datetime.now(UTC),
            }
        )

    # --- heart rate traces ------------------------------------------------------

    def hr_trace(self, session_start: datetime) -> ExerciseHeartRate | None:
        snapshot = self._db.collection("hr_traces").document(_trace_id(session_start)).get()
        return _trace_from_doc(snapshot.to_dict()) if snapshot.exists else None

    def hr_traces_since(self, day: date) -> list[ExerciseHeartRate]:
        query = self._db.collection("hr_traces").where(filter=FieldFilter("date", ">=", day.isoformat()))
        return [_trace_from_doc(s.to_dict()) for s in query.stream()]

    def put_hr_trace(self, row: ExerciseHeartRate) -> None:
        self._db.collection("hr_traces").document(_trace_id(row.session_start)).set(
            {
                "session_start": _ts(row.session_start),
                "date": row.date.isoformat(),
                "session_end": _ts(row.session_end),
                "offsets": [int(pair[0]) for pair in row.samples],
                "bpm": [int(pair[1]) for pair in row.samples],
                "zone_seconds": dict(row.zone_seconds),
                "fetched_at": _ts(row.fetched_at) or datetime.now(UTC),
            }
        )

    # --- skips ------------------------------------------------------------------

    def skipped(self) -> list[SkippedActivity]:
        return [
            SkippedActivity(
                source=doc["source"], ref_id=doc["ref_id"], created_at=_parse_ts(doc.get("created_at"))
            )
            for doc in (s.to_dict() for s in self._db.collection("skips").stream())
        ]

    def set_skipped(
        self, source: str, ref_id: str, skipped: bool, created_at: datetime | None = None
    ) -> None:
        ref = self._db.collection("skips").document(f"{_doc_id(source)}~{_doc_id(ref_id)}")
        if skipped:
            if not ref.get().exists:
                ref.set(
                    {"source": source, "ref_id": ref_id, "created_at": _ts(created_at) or datetime.now(UTC)}
                )
        else:
            ref.delete()

    # --- reports ----------------------------------------------------------------

    def latest_report(self) -> AiReport | None:
        query = (
            self._db.collection("reports")
            .order_by("created_at", direction=firestore.Query.DESCENDING)
            .limit(1)
        )
        for snapshot in query.stream():
            return _report_from_doc(snapshot.to_dict())
        return None

    def report_created_since(self, cutoff: datetime) -> bool:
        query = (
            self._db.collection("reports").where(filter=FieldFilter("created_at", ">=", _ts(cutoff))).limit(1)
        )
        return any(True for _ in query.stream())

    def put_report(self, row: AiReport, claim_drink_ids: Iterable[int] = ()) -> None:
        """Write a report, and claim `claim_drink_ids` for it in the same
        batch — so a report that fails to save cannot leave the beer
        counter reset behind it (ADR-019)."""
        batch = self._db.batch()
        batch.set(
            self._db.collection("reports").document(str(row.id)),
            {
                "id": row.id,
                "created_at": _ts(row.created_at),
                "trigger": row.trigger,
                "model": row.model,
                "prompt_version": row.prompt_version,
                "summary_md": row.summary_md,
                "period_start": _d(row.period_start),
                "period_end": _d(row.period_end),
                "insights": _json(row.insights),
                "tokens_used": row.tokens_used,
            },
        )
        for drink_id in claim_drink_ids:
            batch.update(self._db.collection("drinks").document(str(drink_id)), {"counted_report_id": row.id})
        batch.commit()

    # --- drinks -----------------------------------------------------------------

    def _drinks(self, query) -> list[DrinkLog]:
        return [_drink_from_doc(s.to_dict()) for s in query.stream()]

    def pending_drinks(self) -> list[DrinkLog]:
        """Unclaimed rows logged as they happened, oldest first."""
        query = (
            self._db.collection("drinks")
            .where(filter=FieldFilter("counted_report_id", "==", None))
            .where(filter=FieldFilter("drank_on", "==", None))
        )
        return sorted(self._drinks(query), key=_drink_sort_key)

    def drinks_logged_between(self, start: datetime, end: datetime | None = None) -> list[DrinkLog]:
        """Rows *logged as they happened* with `start <= logged_at < end`."""
        query = self._db.collection("drinks").where(filter=FieldFilter("logged_at", ">=", _ts(start)))
        if end is not None:
            query = query.where(filter=FieldFilter("logged_at", "<", _ts(end)))
        return [row for row in self._drinks(query) if row.drank_on is None]

    def drinks_drank_between(self, first: date, last: date | None = None) -> list[DrinkLog]:
        """Rows *entered after the fact* for a day in [first, last]."""
        query = self._db.collection("drinks").where(filter=FieldFilter("drank_on", ">=", first.isoformat()))
        if last is not None:
            query = query.where(filter=FieldFilter("drank_on", "<=", last.isoformat()))
        return self._drinks(query)

    def add_drinks(self, count: int, drank_on: date | None = None, logged_at: datetime | None = None) -> None:
        if count <= 0:
            return
        now = _ts(logged_at) or datetime.now(UTC)
        batch = self._db.batch()
        for drink_id in self.next_ids("drinks", count):
            batch.set(
                self._db.collection("drinks").document(str(drink_id)),
                {"id": drink_id, "logged_at": now, "counted_report_id": None, "drank_on": _d(drank_on)},
            )
        batch.commit()

    def put_drinks(self, rows: Iterable[DrinkLog]) -> None:
        """Write rows with their own ids — the migration's door."""
        batch = self._db.batch()
        for row in rows:
            batch.set(
                self._db.collection("drinks").document(str(row.id)),
                {
                    "id": row.id,
                    "logged_at": _ts(row.logged_at),
                    "counted_report_id": row.counted_report_id,
                    "drank_on": _d(row.drank_on),
                },
            )
        batch.commit()

    def delete_drinks(self, ids: Iterable[int]) -> None:
        batch = self._db.batch()
        for drink_id in ids:
            batch.delete(self._db.collection("drinks").document(str(drink_id)))
        batch.commit()

    # --- Gemini usage -----------------------------------------------------------

    def gemini_usage(self, day: date) -> dict[str, int]:
        snapshot = self._db.collection("gemini_usage").document(day.isoformat()).get()
        return dict((snapshot.to_dict() or {}).get("requests") or {})

    def set_gemini_usage(self, day: date, model: str, requests: int) -> None:
        """Set a day's count outright — the migration's door, idempotent
        where `count_gemini_request` is not."""
        ref = self._db.collection("gemini_usage").document(day.isoformat())
        ref.set({}, merge=True)
        ref.update({_field("requests", model): requests, "updated_at": datetime.now(UTC)})

    def count_gemini_request(self, day: date, model: str, by: int = 1) -> None:
        ref = self._db.collection("gemini_usage").document(day.isoformat())
        ref.set({}, merge=True)
        ref.update({_field("requests", model): firestore.Increment(by), "updated_at": datetime.now(UTC)})

    # --- conversations -----------------------------------------------------------

    def conversations(self, limit: int) -> list[Conversation]:
        query = (
            self._db.collection("conversations")
            .order_by("updated_at", direction=firestore.Query.DESCENDING)
            .limit(limit)
        )
        return [_conversation_from_doc(s.to_dict()) for s in query.stream()]

    def conversation(self, conversation_id: int) -> Conversation | None:
        snapshot = self._db.collection("conversations").document(str(conversation_id)).get()
        return _conversation_from_doc(snapshot.to_dict()) if snapshot.exists else None

    def messages(self, conversation_id: int) -> list[ConversationMessage]:
        query = (
            self._db.collection("conversations")
            .document(str(conversation_id))
            .collection("messages")
            .order_by("id")
        )
        return [_message_from_doc(s.to_dict()) for s in query.stream()]

    def put_conversation(self, row: Conversation) -> None:
        self._db.collection("conversations").document(str(row.id)).set(
            {
                "id": row.id,
                "title": row.title,
                "created_at": _ts(row.created_at),
                "updated_at": _ts(row.updated_at),
                "include": dict(row.include),
                "lookback_days": row.lookback_days,
                "session_ids": list(row.session_ids),
                "message_count": row.message_count,
            }
        )

    def put_messages(self, rows: Iterable[ConversationMessage]) -> None:
        batch = self._db.batch()
        for row in rows:
            batch.set(
                self._db.collection("conversations")
                .document(str(row.conversation_id))
                .collection("messages")
                .document(str(row.id)),
                {
                    "id": row.id,
                    "conversation_id": row.conversation_id,
                    "role": row.role,
                    "content": row.content,
                    "created_at": _ts(row.created_at),
                },
            )
        batch.commit()

    def delete_conversation(self, conversation_id: int) -> bool:
        ref = self._db.collection("conversations").document(str(conversation_id))
        if not ref.get().exists:
            return False
        batch = self._db.batch()
        for message in ref.collection("messages").list_documents():
            batch.delete(message)
        batch.delete(ref)
        batch.commit()
        return True

    # --- OAuth tokens -------------------------------------------------------------

    def oauth_token(self, provider: str) -> OAuthToken | None:
        snapshot = self._db.collection("oauth_tokens").document(_doc_id(provider)).get()
        if not snapshot.exists:
            return None
        doc = snapshot.to_dict()
        return OAuthToken(
            provider=provider,
            refresh_token_enc=doc["refresh_token_enc"],
            access_token_enc=doc.get("access_token_enc"),
            expiry=_parse_ts(doc.get("expiry")),
            scopes=doc.get("scopes", ""),
            updated_at=_parse_ts(doc.get("updated_at")),
        )

    def put_oauth_token(self, row: OAuthToken) -> None:
        self._db.collection("oauth_tokens").document(_doc_id(row.provider)).set(
            {
                "refresh_token_enc": row.refresh_token_enc,
                "access_token_enc": row.access_token_enc,
                "expiry": _ts(row.expiry),
                "scopes": row.scopes,
                "updated_at": _ts(row.updated_at) or datetime.now(UTC),
            }
        )

    def delete_oauth_token(self, provider: str) -> None:
        self._db.collection("oauth_tokens").document(_doc_id(provider)).delete()

    # --- push devices -------------------------------------------------------------

    def push_devices(self) -> list[PushDevice]:
        return [
            PushDevice(
                token=doc["token"],
                platform=doc["platform"],
                registered_at=_parse_ts(doc.get("registered_at")),
            )
            for doc in (s.to_dict() for s in self._db.collection("push_devices").stream())
        ]

    def put_push_device(self, row: PushDevice) -> None:
        """Registering the same token again overwrites it: one document per
        device however often the app starts."""
        self._db.collection("push_devices").document(_token_id(row.token)).set(
            {
                "token": row.token,
                "platform": row.platform,
                "registered_at": _ts(row.registered_at) or datetime.now(UTC),
            }
        )

    def delete_push_devices(self, tokens: Iterable[str]) -> None:
        batch = self._db.batch()
        for token in tokens:
            batch.delete(self._db.collection("push_devices").document(_token_id(token)))
        batch.commit()


def _token_id(token: str) -> str:
    # Hashed rather than used as the id: a token is ~160 characters of
    # FCM's choosing, and a document id must not contain "/".
    return hashlib.sha256(token.encode()).hexdigest()


def _trace_id(session_start: datetime) -> str:
    return _ts(session_start).strftime("%Y-%m-%dT%H:%M:%S.%fZ")


# --- the process-wide store ------------------------------------------------------


@functools.cache
def _client() -> firestore.Client:
    # Built on first use, not at import: the deployed server forks its
    # workers after importing main.py, and a gRPC channel does not survive
    # a fork (the same trap as the a2wsgi adapter, ADR-028). The project
    # comes from GOOGLE_CLOUD_PROJECT, which Cloud Functions and the
    # emulator both set; FIRESTORE_EMULATOR_HOST redirects it locally.
    return firestore.Client(
        project=os.environ.get("GOOGLE_CLOUD_PROJECT") or os.environ.get("GCLOUD_PROJECT")
    )


def get_store() -> FirestoreStore:
    """The FastAPI dependency. Tests override it with a store on the
    emulator (tests/conftest.py)."""
    from api.integrations.google_health import local_tz

    return FirestoreStore(_client(), local_tz())


__all__ = ["FirestoreStore", "UNDATED", "get_store"]
