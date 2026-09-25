"""api/services/skips.py — scheduled sessions that did not happen.

A match on the ÖFB log or a "Training" block on the calendar is evidence
that something happened, and the training model leans on it: on a day the
watch tracked nothing, those scheduled minutes are what stops the day
reading as rest (see api/analysis/training_load.py). That evidence is
wrong exactly when the session was missed — ill, or no time — and there is
nothing in either source that says so, because neither the club's match
report nor a recurring calendar block knows the user stayed home.

So the user says it, and it lands here: one row per skipped activity,
which `services/training.py` subtracts before the day is ever built and
`services/exercises.py` marks on the listed session. Two readers, one
table, and no third opinion about what "skipped" means.

Kept in its own module rather than inside either reader because both need
it and they already point one way (exercises → training); putting it in
either would make that a cycle.
"""

from __future__ import annotations

from api.analysis.training_load import MATCH, TRAINING
from api.config import settings
from api.store.firestore import FirestoreStore
from api.store.like import ilike

# The two things that can be scheduled and then missed, spelled the way the
# model spells them — a skip and the load it removes have to be talking
# about the same kind of session. `ref_id` is the natural key of the row in
# question, see the model for why not the surrogate one.
SOURCES = (MATCH, TRAINING)

__all__ = ["MATCH", "SOURCES", "TRAINING", "activity_exists", "set_skipped", "skipped_refs"]


def skipped_refs(store: FirestoreStore) -> set[tuple[str, str]]:
    """Every `(source, ref_id)` currently marked skipped.

    Returned whole rather than queried per activity: both callers are
    already looping over a list of candidates, and this is a handful of
    rows for one person.
    """
    return {(row.source, row.ref_id) for row in store.skipped()}


def activity_exists(store: FirestoreStore, source: str, ref_id: str) -> bool:
    """Whether `ref_id` names a real match or a real training block.

    Checked before a skip is stored so a typo becomes a 404 instead of a
    row that quietly matches nothing forever. A calendar event only counts
    as a training if its title is the one the model reads as training —
    skipping a dentist appointment would change no number.
    """
    if source == MATCH:
        return store.match(ref_id) is not None
    if source == TRAINING:
        event = store.calendar_event(ref_id)
        return event is not None and ilike(event.title, settings.calendar_training_title)
    return False


def set_skipped(store: FirestoreStore, source: str, ref_id: str, skipped: bool) -> None:
    """Mark an activity skipped, or unmark it. Idempotent either way — the
    dashboard sends the state it wants, not a toggle, so a double tap or a
    replayed request cannot flip it back."""
    store.set_skipped(source, ref_id, skipped)
