from __future__ import annotations

from datetime import date, datetime

from pydantic import BaseModel, ConfigDict

from api.schemas.league import OpponentStandingOut


class MatchOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    oefb_game_id: str
    match_date: date | None
    opponent: str
    home_away: str
    result: str | None
    started: bool
    minutes_played: int
    goals: int
    yellow_card: bool
    red_card: bool
    # The session this match was: the tracked workout that covered kick-off,
    # or `match#<oefb_game_id>` when the watch missed it and the load is an
    # estimate. Null for a match with neither — on the bench untracked, or
    # older than the first tracked day. Open it with
    # GET /health-data/exercises/{session_id}.
    session_id: str | None
    # Where the opponent stood in the league table before kick-off (or
    # stands now, `at_kickoff` false, for a match older than every stored
    # table). Null for a team outside our league, and on a match nested in
    # an exercise session, which does not carry it.
    opponent_standing: OpponentStandingOut | None


class MissingMatchOut(BaseModel):
    """Yesterday's fixture from the calendar that the ÖFB log has no game
    for — see api/services/matches.py for why that can happen."""

    model_config = ConfigDict(from_attributes=True)

    day: date
    title: str
    kickoff: datetime
