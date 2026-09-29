from __future__ import annotations

from datetime import date, datetime

from pydantic import BaseModel, ConfigDict


class LeagueRowOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    rank: int
    # Places gained (+) or lost (−) in the last round, as the ÖFB table's
    # arrows show it.
    rank_change: int
    team: str
    is_us: bool
    played: int
    won: int
    drawn: int
    lost: int
    goals_for: int
    goals_against: int
    goal_difference: int
    points: int


class LeagueTableOut(BaseModel):
    """The overall league table as the nightly scrape last found it."""

    model_config = ConfigDict(from_attributes=True)

    league: str
    # The local day the table was scraped on.
    day: date
    fetched_at: datetime | None
    rows: list[LeagueRowOut]


class OpponentStandingOut(BaseModel):
    """An opponent's place in the table next to ours
    (api/services/league.py)."""

    model_config = ConfigDict(from_attributes=True)

    rank: int
    rank_change: int
    played: int
    points: int
    points_per_game: float | None
    goal_difference: int
    our_rank: int | None
    our_points: int | None
    our_points_per_game: float | None
    # Their points minus ours: positive means they are ahead.
    points_gap: int | None
    # "stronger", "level" or "weaker", from the difference in points per
    # game; null until both sides have played.
    strength: str | None
    # The day of the table this was read from.
    table_day: date
    # True when that table predates kick-off; false when the match is older
    # than every stored table and this is where the opponent stands now.
    at_kickoff: bool


class FixtureOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    oefb_game_id: str
    kickoff: datetime | None
    opponent: str
    home_away: str
    # "Liga", "Testspiel", "Cup", … as the ÖFB schedule names it.
    art: str | None
    # Null when the opponent is not in our league's table (a friendly or a
    # cup game) or no table has been scraped yet.
    opponent_standing: OpponentStandingOut | None
