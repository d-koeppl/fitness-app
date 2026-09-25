from __future__ import annotations

from typing import Literal

from pydantic import BaseModel, ConfigDict


class DayPointOut(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    date: str
    load: float
    fitness: float
    fatigue: float


class ScorePointOut(BaseModel):
    """One day's recovery and readiness. Separate from DayPointOut because
    the two series end on different days — see analysis.training_load."""

    model_config = ConfigDict(from_attributes=True)

    date: str
    recovery: int | None
    readiness: int | None


class TrainingStatusOut(BaseModel):
    """Mirrors api.analysis.training_load.TrainingStatus. Form travels as a
    percentage of fitness because the load unit (Active Zone Minutes) does
    not carry the ±25 TSB bands cycling uses."""

    model_config = ConfigDict(from_attributes=True)

    status: str
    headline: str
    fitness: float
    fatigue: float
    form: float
    form_pct: float
    ramp_pct: float
    recovery: int | None
    recovery_parts: dict[str, float]
    readiness: int | None
    readiness_parts: dict[str, float]
    days_of_history: int
    series: list[DayPointOut]
    scores: list[ScorePointOut]
    notes: list[str]


class SkipIn(BaseModel):
    """Mark a scheduled session as done-or-not.

    A state, not a toggle: the dashboard sends what it wants to be true, so
    a double tap or a replayed request lands on the same answer. `ref_id` is
    the natural key the listed session carries — `oefb_game_id` for a match,
    the Google event id for a training.
    """

    source: Literal["match", "training"]
    ref_id: str
    skipped: bool


class SkipOut(BaseModel):
    source: str
    ref_id: str
    skipped: bool
