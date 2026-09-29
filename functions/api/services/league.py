"""api/services/league.py — where an opponent stands against us.

The nightly scrape keeps one copy of the league table a day and the games
still to play (oefb/scraper.py). This module reads them: the opponent's
row, next to ours, for a fixture or a played match.

Rank alone compares badly — 1st against 2nd and 7th against 14th are the
same ratio and very different games — and teams can be apart in games
played. So the comparison is points per game, and the strength label is
the difference in it: a team taking half a point a game more than us is
"stronger", half a point fewer "weaker", anything between "level". It is
a label for a fitness app to plan recovery around, not a prediction.

A played match is shown against the table as it stood before kick-off:
the newest copy from the match day or earlier (the scrape runs at 03:30,
so the match day's own copy predates the game). A match older than the
first stored copy, or older than AT_KICKOFF_MAX_AGE_DAYS, falls back to
the current table and says so (`at_kickoff=False`) — an early-season
match would otherwise be read against last season's standings.
"""

from __future__ import annotations

from bisect import bisect_right
from dataclasses import dataclass
from datetime import date, datetime, timedelta

from api.store.firestore import FirestoreStore
from api.store.rows import Fixture, LeagueRow, LeagueTable, MatchPerformance
from oefb.parser import team_key

# Points per game apart before one side counts as the stronger one.
STRENGTH_MARGIN_PPG = 0.5
# How old a stored table may be and still stand for "before kick-off" —
# three weeks covers a scrape that failed for a while, not a summer break.
AT_KICKOFF_MAX_AGE_DAYS = 21


@dataclass(frozen=True)
class Standing:
    """The opponent's row next to ours, from one table."""

    rank: int
    rank_change: int
    played: int
    points: int
    points_per_game: float | None
    goal_difference: int
    our_rank: int | None
    our_points: int | None
    our_points_per_game: float | None
    points_gap: int | None  # theirs − ours: positive means they are ahead
    strength: str | None  # "stronger" | "level" | "weaker"; None before both have played
    table_day: date
    at_kickoff: bool


@dataclass(frozen=True)
class UpcomingFixture:
    oefb_game_id: str
    kickoff: datetime | None
    opponent: str
    home_away: str
    art: str | None
    opponent_standing: Standing | None


def points_per_game(row: LeagueRow) -> float | None:
    return round(row.points / row.played, 2) if row.played else None


def strength(theirs: float | None, ours: float | None) -> str | None:
    if theirs is None or ours is None:
        return None
    if theirs - ours > STRENGTH_MARGIN_PPG:
        return "stronger"
    if ours - theirs > STRENGTH_MARGIN_PPG:
        return "weaker"
    return "level"


def our_row(table: LeagueTable) -> LeagueRow | None:
    return next((row for row in table.rows if row.is_us), None)


def team_row(table: LeagueTable, name: str) -> LeagueRow | None:
    key = team_key(name)
    return next((row for row in table.rows if team_key(row.team) == key), None)


def standing(table: LeagueTable, opponent: str, *, at_kickoff: bool = False) -> Standing | None:
    """`opponent` against us in `table`, or None when the opponent is not
    in it — a friendly or a cup game against a team from another league."""
    theirs = team_row(table, opponent)
    if theirs is None or theirs.is_us:
        return None
    ours = our_row(table)
    their_ppg = points_per_game(theirs)
    our_ppg = points_per_game(ours) if ours else None
    return Standing(
        rank=theirs.rank,
        rank_change=theirs.rank_change,
        played=theirs.played,
        points=theirs.points,
        points_per_game=their_ppg,
        goal_difference=theirs.goal_difference,
        our_rank=ours.rank if ours else None,
        our_points=ours.points if ours else None,
        our_points_per_game=our_ppg,
        points_gap=theirs.points - ours.points if ours else None,
        strength=strength(their_ppg, our_ppg),
        table_day=table.day,
        at_kickoff=at_kickoff,
    )


def table_before(tables: list[LeagueTable], day: date) -> LeagueTable | None:
    """The newest of `tables` (oldest first) from `day` or earlier, if it
    is recent enough to stand for the table at kick-off."""
    i = bisect_right([t.day for t in tables], day)
    if i == 0:
        return None
    table = tables[i - 1]
    return table if day - table.day <= timedelta(days=AT_KICKOFF_MAX_AGE_DAYS) else None


def match_standings(store: FirestoreStore, matches: list[MatchPerformance]) -> dict[str, Standing]:
    """oefb_game_id -> where that match's opponent stood before kick-off,
    or stands now when no copy of the table is old enough. One read of
    every stored table, however many matches."""
    tables = store.league_tables()
    if not tables:
        return {}
    latest = tables[-1]
    result: dict[str, Standing] = {}
    for match in matches:
        before = table_before(tables, match.match_date) if match.match_date else None
        found = standing(before or latest, match.opponent, at_kickoff=before is not None)
        if found is not None:
            result[match.oefb_game_id] = found
    return result


def upcoming_fixtures(
    store: FirestoreStore, now: datetime, table: LeagueTable | None = None
) -> list[UpcomingFixture]:
    """The games still to play from `now` on, soonest first, each with the
    opponent's standing in the current table. A fixture the stored list has
    but whose kick-off has passed is left out: the list is only as fresh as
    the last scrape."""
    table = table if table is not None else store.league_table()
    fixtures = [f for f in store.fixtures() if f.kickoff is not None and f.kickoff >= now]
    fixtures.sort(key=lambda f: f.kickoff)
    return [_upcoming(f, table) for f in fixtures]


def _upcoming(fixture: Fixture, table: LeagueTable | None) -> UpcomingFixture:
    return UpcomingFixture(
        oefb_game_id=fixture.oefb_game_id,
        kickoff=fixture.kickoff,
        opponent=fixture.opponent,
        home_away=fixture.home_away,
        art=fixture.art,
        opponent_standing=standing(table, fixture.opponent) if table else None,
    )
