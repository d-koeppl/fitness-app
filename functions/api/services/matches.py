"""api/services/matches.py — is yesterday's game missing from the ÖFB log?

Every fixture is in the user's calendar as "Spiel: <home> - <away>" with
its kick-off (settings.calendar_match_title, ADR-015). The ÖFB log only
gets a row when the nightly scrape (03:30 local, ADR-004) finds the game
report *and* the player in it. So a fixture yesterday with no row for that
day is worth saying out loud: without that row, the training model does not
see the match and the report cannot reason about it.

The gap alone cannot say why. The scrape may have failed (network, the
anubis challenge, a changed page); the club may not have put the report
online yet; the player may not have been in the squad; or the game may
have been called off. The scrape's lookback (`oefb_sync_days_back`) retries
the first two cases on the next two nights. The dashboard names all four
rather than guessing one.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import date, datetime, time, timedelta

from api.config import settings
from api.integrations.google_health import local_tz
from api.store.firestore import FirestoreStore
from api.store.like import ilike
from api.store.rows import MatchPerformance


def newest_first(store: FirestoreStore) -> list[MatchPerformance]:
    """Every logged match, newest first, undated rows before all of them —
    Postgres' `ORDER BY match_date DESC` puts NULLs first, and this keeps
    its order. Shared by GET /matches and the report context."""
    return sorted(
        store.matches(), key=lambda m: (m.match_date is None, m.match_date or date.min), reverse=True
    )


@dataclass(frozen=True)
class MissingMatch:
    day: date
    title: str
    kickoff: datetime


def missing_match(store: FirestoreStore, now: datetime | None = None) -> MissingMatch | None:
    """Yesterday's fixture from the calendar, if the ÖFB log has no game on
    that day. None when there was no fixture, or when the log has it.

    "Yesterday" is the local day before `now` (default: the current time).
    Also None before today's scrape has run (`oefb_sync_hour:minute`):
    between midnight and then, a missing row only means the scrape hasn't
    happened yet."""
    tz = local_tz()
    now = (now or datetime.now(tz)).astimezone(tz)
    if now.time() < time(settings.oefb_sync_hour, settings.oefb_sync_minute):
        return None
    day = now.date() - timedelta(days=1)
    start = datetime.combine(day, time.min, tzinfo=tz)
    end = datetime.combine(now.date(), time.min, tzinfo=tz)

    fixture = next(
        (e for e in store.calendar_events(start, end) if ilike(e.title, settings.calendar_match_title)),
        None,
    )
    if fixture is None:
        return None

    if store.matches_between(day, day):
        return None

    return MissingMatch(day=day, title=fixture.title or "Spiel", kickoff=fixture.start_ts)
