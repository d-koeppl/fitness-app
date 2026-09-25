"""api/routers/drinks.py — the Today tab's 0.5 L beer counter (ADR-019).

Three calls, one shape: every one answers with the whole counter, so the
stepper renders the server's number rather than its own arithmetic. The
counting rules — what is pending, and what resets it — live in
api/services/drinks.py.

No `POST /drinks {delta}`: a delta sent twice by a flaky connection would
log two beers. `+1` and `-1` are separate, and `-1` is a delete of the last
tap, which is idempotent enough that a retry costs at most one drink the
user was removing anyway. `PUT` is the exception that proves the rule — it
carries a count rather than a change, so a retry lands on the same number.

The `/days` calls are the beer remembered late (ADR-023) and answer a
different shape, because they are about a *day* rather than about the
counter: a day has a date, and a floor no correction can go under. Writing
one is a `PUT` of a count, for the same retry-safety as above. Any past day
may be written, however old (ADR-024); the list endpoints only bound how
much history one response carries.
"""

from __future__ import annotations

from datetime import date

from fastapi import APIRouter, Depends, HTTPException, Query

from api.schemas.drinks import DrinkCounterOut, DrinkCountIn, DrinkDayOut
from api.services import drinks
from api.store.firestore import FirestoreStore, get_store

router = APIRouter(prefix="/drinks", tags=["drinks"])


def _out(counter: drinks.PendingDrinks) -> DrinkCounterOut:
    return DrinkCounterOut(
        count=counter.count,
        volume_l=drinks.DRINK_VOLUME_L,
        alcohol_grams=drinks.DRINK_ALCOHOL_GRAMS,
        first_logged_at=counter.first_logged_at,
        last_logged_at=counter.last_logged_at,
    )


@router.get("/days", response_model=list[DrinkDayOut])
def list_days(
    days: int = Query(drinks.HISTORY_DAYS, ge=1, le=drinks.MAX_HISTORY_DAYS),
    store: FirestoreStore = Depends(get_store),
) -> list[DrinkDayOut]:
    """The last `days` local days ending today, newest first, empty ones
    included — the Beer sheet's chart and its editable day rows read the
    same list.

    Today is in it so the chart can plot it, and comes back
    `editable: false` because that evening belongs to the counter.
    """
    return [DrinkDayOut.model_validate(day) for day in drinks.day_history(store, days)]


@router.get("/days/{day}", response_model=DrinkDayOut)
def get_day(day: date, store: FirestoreStore = Depends(get_store)) -> DrinkDayOut:
    """One day, however far back — what the date picker reads when a date is
    chosen, so the field opens on the number already stored rather than on a
    guess (ADR-024). A day with no beers answers zero, not 404."""
    return DrinkDayOut.model_validate(drinks.day_tally(store, day))


@router.put("/days/{day}", response_model=DrinkDayOut)
def set_day(day: date, body: DrinkCountIn, store: FirestoreStore = Depends(get_store)) -> DrinkDayOut:
    """Fill in (or correct) the beers of one earlier day — the round nobody
    remembered to tap in on Saturday (ADR-023).

    Idempotent: it carries the number that day should read, so a retry
    lands on the same history. The rows it writes are off the counter from
    birth, so this cannot move the stepper upwards or feed tonight's report
    a beer from last week — it lands on the day it names, which is where
    later analysis reads it.

    Any past date is accepted, however old — the picker that sends it is a
    calendar, not a typed number (ADR-024). 422, with the reason in
    `detail`, for the two the service refuses: today or later (that is the
    counter's job), and a count below what a report already counted on that
    day. A count over 99 is refused a step earlier, by `DrinkCountIn`, the
    same slipped-finger guard the counter has.
    """
    try:
        return DrinkDayOut.model_validate(drinks.set_day(store, day, body.count))
    except ValueError as exc:
        raise HTTPException(status_code=422, detail=str(exc)) from exc


@router.get("", response_model=DrinkCounterOut)
def get_counter(store: FirestoreStore = Depends(get_store)) -> DrinkCounterOut:
    """The drinks logged since the last daily report claimed them."""
    return _out(drinks.pending(store))


@router.post("", response_model=DrinkCounterOut, status_code=201)
def add_drink(store: FirestoreStore = Depends(get_store)) -> DrinkCounterOut:
    """Plus one — one 0.5 L beer."""
    return _out(drinks.log_drink(store))


@router.delete("/last", response_model=DrinkCounterOut)
def undo_drink(store: FirestoreStore = Depends(get_store)) -> DrinkCounterOut:
    """Minus one: take back the most recent tap that no report has counted
    yet. A no-op at zero — the count that comes back says so, and a 404 for
    a button the user pressed once too often would be noise."""
    return _out(drinks.remove_last(store))


@router.put("", response_model=DrinkCounterOut)
def set_counter(body: DrinkCountIn, store: FirestoreStore = Depends(get_store)) -> DrinkCounterOut:
    """Set the counter to a number typed straight into the tile — four taps
    is fine, eleven is not.

    Idempotent, unlike the two above: it says what the counter should read,
    so a replayed request cannot add a beer. Only the drinks no report has
    claimed are moved; the difference is added or removed at the newest end.
    """
    return _out(drinks.set_count(store, body.count))
