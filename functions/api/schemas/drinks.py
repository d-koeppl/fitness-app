from __future__ import annotations

from datetime import date, datetime

from pydantic import BaseModel, ConfigDict, Field


class DrinkCounterOut(BaseModel):
    """The Today tab's beer counter (ADR-019).

    `count` is the drinks since the last reset — the number on the stepper
    — not a lifetime total. Every write endpoint returns this same shape,
    so the client never has to re-read the counter after changing it.

    `volume_l` and `alcohol_grams` are what one tap means, sent rather than
    hard-coded in the frontend so the label under the stepper and the
    number the report reasons about can never drift apart.
    """

    model_config = ConfigDict(from_attributes=True)

    count: int
    volume_l: float
    alcohol_grams: int
    # The span the count covers. Both null at zero — there is no window
    # when nothing has been logged since the last report.
    first_logged_at: datetime | None
    last_logged_at: datetime | None


class DrinkCountIn(BaseModel):
    """A count typed in rather than tapped up to — the counter, or one
    earlier day.

    Bounded at 99 as typo protection, not as a drinking limit: either way
    it is one evening, and a three-digit number in that box is a slipped
    finger, which is worth a 422 rather than a silent hundred rows.
    """

    count: int = Field(ge=0, le=99)


class DrinkDayOut(BaseModel):
    """One local day of beers, as the Beer sheet plots and edits it
    (ADR-023, ADR-024).

    `count` is the whole day — what was tapped in at the time plus what was
    filled in afterwards — and the day is the *server's* local day, which
    is why the client is sent the date rather than working one out in the
    browser's own zone.

    `reported` is how many of those beers an AI report already counted. It
    is the floor: those rows stay, because a report describing four beers
    must not end up beside a history holding two, so the editor stops its
    minus there instead of spending a round trip on a 422.

    `editable` is false for today alone, whose beers are the counter's. The
    server decides it for the same reason it sends the date: its day
    boundary is not necessarily the browser's.
    """

    model_config = ConfigDict(from_attributes=True)

    date: date
    count: int
    reported: int
    editable: bool
