from __future__ import annotations

from datetime import datetime
from enum import IntEnum
from typing import Annotated

from pydantic import BaseModel, ConfigDict, Field


# The coach's History choices: 14 / 30 / 90 days, half a year, a year, two
# years. The only list of them — the Dart client gets it as an enum from the
# schema, and the app's labels are tested against that enum, so adding one
# here fails the app's tests until it has a label. A named enum rather than
# a Literal, so the schema carries it once and the client has one type.
class CoachLookbackDays(IntEnum):
    """How far back the coach's health, workout and match data reaches, in days."""

    DAYS_14 = 14
    DAYS_30 = 30
    DAYS_90 = 90
    DAYS_182 = 182
    DAYS_365 = 365
    DAYS_730 = 730


# A client's name for one message, so a resend is answered from the first
# attempt instead of asking Gemini twice. A UUID in practice; the pattern
# only has to make it a safe Firestore document id.
ClientMessageId = Annotated[str, Field(min_length=8, max_length=64, pattern=r"^[A-Za-z0-9_-]+$")]

# One pinned workout, by the id `/health-data/exercises` gave it (ADR-021):
# `<date>#<index>` for a tracked session, `match#<ref>` / `training#<ref>`
# for one the watch never recorded. Length-bounded because it is a string
# from a client that goes into a database column and a Gemini prompt; the
# shape itself is checked by resolving it, not by a regex here — a
# well-formed id for a session that does not exist has to fail the same way
# a malformed one does.
SessionId = Annotated[str, Field(min_length=1, max_length=64)]


class ChatMessageOut(BaseModel):
    """One stored turn.

    An output type only: since ADR-017 the client names a conversation
    instead of replaying one, so nothing of this shape is ever parsed out of
    a request body.
    """

    model_config = ConfigDict(from_attributes=True)

    id: int
    role: str  # "user" | "assistant"
    content: str
    created_at: datetime


class IncludeFlags(BaseModel):
    """The dashboard's "Include in this chat" toggles.

    A new flag defaults to True so that conversations stored before it
    existed keep answering with everything on — `IncludeFlags(**conv.include)`
    fills the missing key rather than silently dropping the data out of a
    thread that was already being answered with it.
    """

    health: bool = True
    exercises: bool = True
    matches: bool = True
    events: bool = True
    report: bool = True
    # The beer counter and its recent history (ADR-019).
    alcohol: bool = True


class ConversationOut(BaseModel):
    """A row in the chat picker. No messages — the list is opened far more
    often than any one thread is read."""

    model_config = ConfigDict(from_attributes=True)

    id: int
    title: str
    created_at: datetime
    updated_at: datetime
    message_count: int


class ConversationDetailOut(ConversationOut):
    """One chat, opened. `include` and `lookback_days` are the settings it is
    being held under, so reopening it restores the toggles rather than
    answering the next turn from a different slice of the data than the turns
    above it."""

    include: IncludeFlags
    lookback_days: CoachLookbackDays
    # The workouts pinned to this chat, in the order they were attached
    # (ADR-021). Restored into the composer when the chat is reopened, for
    # the same reason the toggles are: the next turn has to be answered
    # about the same sessions as the turns above it.
    session_ids: list[SessionId]
    messages: list[ChatMessageOut]


class ChatRequest(BaseModel):
    # Reject unknown fields rather than ignoring them: a client still sending
    # the old client-built `system` prompt — or the old `messages` array,
    # which would silently answer the new question against no history at all
    # — should fail loudly. See api/analysis/coach.py.
    model_config = ConfigDict(extra="forbid")

    # None starts a new conversation; the reply carries the id it was given.
    conversation_id: int | None = None
    content: str = Field(min_length=1)
    # Both optional now: omitted means "keep whatever this conversation was
    # already being held at". On a new chat they fall back to the defaults,
    # where 14 is the same window the daily report uses.
    include: IncludeFlags | None = None
    lookback_days: CoachLookbackDays | None = None
    # Which workouts to pin, replacing whatever this chat had. Optional and
    # None like the two above — "keep what it was" — so a client that never
    # attaches anything is unchanged. An explicit `[]` detaches them all,
    # which is the only way to say that and therefore has to be distinct
    # from omitting the field.
    #
    # An id naming no session is a 404 rather than a silent drop: the client
    # only ever sends ids it was given, so one that no longer resolves is a
    # real disagreement about what exists and worth hearing about. Stored
    # ids are treated more gently — see api/services/conversations.py.
    session_ids: list[SessionId] | None = None
    # Optional so curl still works; the app always sends one. A message
    # whose reply was lost on the way back (a timeout on a slow phone
    # network, the function still finishing) is resent with the same id and
    # gets the stored reply — one Gemini request, one pair of turns. The
    # same id sent while the first is still being answered is a 409.
    client_message_id: ClientMessageId | None = None


class ModelUsageOut(BaseModel):
    """One model's share of the day. Two configured models are two separate
    requests-per-day budgets, and which one is spent is what says whether the
    fallback still has anywhere to go."""

    model: str
    used: int
    limit: int


class CoachUsageOut(BaseModel):
    """The whole day's Gemini budget, which the chat and the daily report
    share (ADR-013). `used` counts every call the process made, not just
    chat messages, so `chat_remaining` moves when a report runs too."""

    used: int
    limit: int
    chat_remaining: int
    # When the count rolls over: midnight Pacific, sent as a timestamp so
    # the browser can show it in the reader's own clock time. The local hour
    # it lands on moves with two different DST schedules, so a fixed string
    # would be wrong for several weeks a year.
    resets_at: datetime
    models: list[ModelUsageOut]


class ChatResponse(BaseModel):
    """The reply, plus the conversation it landed in — so a first message
    teaches the client the new id and the derived title in one round trip."""

    conversation: ConversationOut
    message: ChatMessageOut  # the stored user turn
    reply: ChatMessageOut
    # Returned with every reply so the counter updates without a second
    # round trip.
    usage: CoachUsageOut
