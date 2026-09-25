from __future__ import annotations

from datetime import date, datetime

from pydantic import BaseModel, ConfigDict


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


class MissingMatchOut(BaseModel):
    """Yesterday's fixture from the calendar that the ÖFB log has no game
    for — see api/services/matches.py for why that can happen."""

    model_config = ConfigDict(from_attributes=True)

    day: date
    title: str
    kickoff: datetime
