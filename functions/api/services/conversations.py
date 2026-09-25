"""api/services/conversations.py — the coach's stored chats (ADR-017).

The conversation used to live in the browser tab and be POSTed back whole on
every message. Two things followed from that: closing the app lost it, and
the caller could put words in the coach's mouth — ADR-010 stopped the client
supplying a *prompt*, but not an "assistant" turn claiming the coach had
already agreed to something. Holding the history here ends both.

What is stored and what is sent are deliberately different: every turn is
kept and shown, but only a trailing window reaches Gemini
(api/analysis/coach.py::trim_history).

On Firestore (ADR-035) a turn is one batched write — the conversation, both
messages and the resend record — and a message the client names by id is
answered at most once: a resend of it gets the stored reply.
"""

from __future__ import annotations

from dataclasses import dataclass, replace
from datetime import UTC, datetime, timedelta

from api.analysis import coach
from api.config import settings
from api.schemas.coach import IncludeFlags
from api.services.exercises import find_sessions
from api.store.firestore import FirestoreStore
from api.store.rows import Conversation, ConversationMessage

DEFAULT_TITLE = "New chat"
TITLE_MAX = 60
# The daily report's own window. Passed on to the assembler as None so
# matches keep their last-few-by-count fallback rather than being windowed
# to an empty fortnight — the rule the router used to hold inline.
REPORT_DEFAULT_LOOKBACK = 14
# How many chats the picker lists.
LIST_LIMIT = 50


class ChatInProgress(RuntimeError):
    """The same message is still being answered by another request."""


@dataclass(frozen=True)
class Turn:
    """One answered message: the conversation after it, and both turns."""

    conversation: Conversation
    question: ConversationMessage
    reply: ConversationMessage


def derive_title(text: str) -> str:
    """A title out of the first user message, not out of Gemini.

    A generated title costs one request from a day that holds about 37 of
    them (ADR-013), spent at the exact moment the user has started asking
    something. The first thing you type is nearly always what the chat turns
    out to be about.
    """
    flat = " ".join(text.split())
    if not flat:
        return DEFAULT_TITLE
    if len(flat) <= TITLE_MAX:
        return flat
    # Cut on a word boundary where there is one; a single long token falls
    # back to a hard cut rather than to an empty title.
    cut = flat[:TITLE_MAX].rsplit(" ", 1)[0] or flat[:TITLE_MAX]
    return f"{cut}…"


def list_conversations(store: FirestoreStore, limit: int = LIST_LIMIT) -> list[Conversation]:
    """Most recently *used* first, each carrying its message count.

    Ordered by `updated_at`, not `created_at`: the picker's job is "the one I
    was in", and the head of this list is what the tab resumes into.
    """
    return store.conversations(limit)


def get_conversation(store: FirestoreStore, conversation_id: int) -> Conversation | None:
    return store.conversation(conversation_id)


def messages_for(store: FirestoreStore, conversation_id: int) -> list[ConversationMessage]:
    return store.messages(conversation_id)


def delete_conversation(store: FirestoreStore, conversation_id: int) -> bool:
    """The conversation, its messages and its resend records, in one batch.
    False when there was no such conversation."""
    return store.delete_conversation(conversation_id)


def already_answered(store: FirestoreStore, client_message_id: str | None) -> bool:
    """Whether this message has a stored reply, so a resend spends nothing."""
    return client_message_id is not None and store.chat_request_done(client_message_id)


def _checked_session_ids(store: FirestoreStore, session_ids: list[str]) -> list[str]:
    """The ids as given, once every one of them has been shown to name a
    real session. Raises LookupError otherwise (ADR-021).

    Only ever applied to ids arriving in *this request*. The client is
    attaching workouts it was just handed by `/health-data/exercises`, so an
    id that does not resolve means the two sides disagree about what exists,
    and pinning it silently would produce a chat that answers about fewer
    workouts than the composer is showing chips for.

    Ids already *stored* on a conversation are not re-checked here: a
    re-sync can rewrite a day and move an id out from under a thread that
    was fine when it was written, and refusing to answer that thread ever
    again would be the worse failure. Those are resolved leniently at prompt
    time, where a missing one becomes a sentence the coach can say out loud
    (api/analysis/coach.py::MISSING_ATTACHED).

    Duplicates are dropped rather than rejected: attaching the same workout
    twice is a double tap, not an error, and sending its trace twice would
    cost a few thousand tokens to say nothing.
    """
    unique = list(dict.fromkeys(session_ids))
    if len(unique) > settings.coach_max_attached_sessions:
        raise LookupError(
            f"At most {settings.coach_max_attached_sessions} workouts can be "
            f"attached to one chat; {len(unique)} were sent."
        )

    found = find_sessions(store, unique)
    missing = [session_id for session_id in unique if session_id not in found]
    if missing:
        raise LookupError(f"No exercise session with id {', '.join(missing)}")
    return unique


def _replayed(store: FirestoreStore, record: dict) -> Turn:
    """The turn a finished resend record points at."""
    conversation = store.conversation(record["conversation_id"])
    question = store.message(record["conversation_id"], record["question_id"])
    reply = store.message(record["conversation_id"], record["reply_id"])
    if conversation is None or question is None or reply is None:
        # delete_conversation removes the records with the chat, so this is
        # a record that outlived its data some other way.
        raise LookupError(f"No conversation with id {record['conversation_id']}")
    return Turn(conversation, question, reply)


def reply_to(
    store: FirestoreStore,
    conversation_id: int | None,
    content: str,
    include: IncludeFlags | None,
    lookback_days: int | None,
    session_ids: list[str] | None = None,
    client_message_id: str | None = None,
) -> Turn:
    """One turn: resolve or start the conversation, answer it against the
    stored history, then store both turns.

    Written *after* the model has answered, in one batch, so the transcript
    never holds a question with nothing under it. A failed request still
    spends a Gemini slot — which is why the app re-reads the counter on
    error — but it leaves the text in the composer to retry rather than half
    a turn in the database.

    With a `client_message_id`, a message already answered is not answered
    again: the stored turn comes back as it was. One still being answered
    raises ChatInProgress.

    Raises LookupError if `conversation_id` names a chat that is not there,
    or if `session_ids` names a workout that is not.
    """
    if client_message_id is not None:
        stale_before = datetime.now(UTC) - timedelta(seconds=settings.coach_request_stale_seconds)
        record = store.claim_chat_request(client_message_id, stale_before)
        if record is not None:
            if record.get("status") == "done":
                return _replayed(store, record)
            raise ChatInProgress("This message is still being answered.")

    try:
        turn = _answer(
            store, conversation_id, content, include, lookback_days, session_ids, client_message_id
        )
    except Exception:
        # Let a resend ask again: nothing was stored for this attempt.
        if client_message_id is not None:
            store.release_chat_request(client_message_id)
        raise
    return turn


def _answer(
    store: FirestoreStore,
    conversation_id: int | None,
    content: str,
    include: IncludeFlags | None,
    lookback_days: int | None,
    session_ids: list[str] | None,
    client_message_id: str | None,
) -> Turn:
    checked = _checked_session_ids(store, session_ids) if session_ids is not None else None
    conv = store.conversation(conversation_id) if conversation_id else None
    if conversation_id and conv is None:
        raise LookupError(f"No conversation with id {conversation_id}")

    if conv is None:
        conv = Conversation(
            id=0,  # allocated once the model has answered
            title=derive_title(content),
            include=(include or IncludeFlags()).model_dump(),
            lookback_days=int(lookback_days or REPORT_DEFAULT_LOOKBACK),
            session_ids=checked or [],
        )
        history: list[ConversationMessage] = []
    else:
        # Omitted means "keep holding this chat where it was".
        changes: dict = {}
        if include is not None:
            changes["include"] = include.model_dump()
        if lookback_days is not None:
            changes["lookback_days"] = int(lookback_days)
        # An explicit list replaces the whole set, `[]` included — that is
        # how the composer says "detach everything", and it has to be
        # distinguishable from the field being omitted.
        if checked is not None:
            changes["session_ids"] = checked
        conv = replace(conv, **changes)
        history = store.messages(conv.id)

    flags = IncludeFlags(**conv.include)
    # 14 is the daily report's window: pass it through as "unset" so matches
    # fall back to the last few by count rather than to an empty 14 days.
    window = None if conv.lookback_days == REPORT_DEFAULT_LOOKBACK else conv.lookback_days

    turns = coach.trim_history(
        [{"role": m.role, "content": m.content} for m in history] + [{"role": "user", "content": content}]
    )
    # Off the conversation rather than from `checked`: on a turn that
    # omitted the field these are the chat's stored attachments, which is
    # the whole point of storing them.
    pinned = list(conv.session_ids)

    text = coach.answer(store, coach.CoachInclude(**flags.model_dump()), turns, window, pinned)

    now = datetime.now(UTC)
    if conv.id == 0:
        conv = replace(conv, id=store.next_ids("conversations")[0], created_at=now)
    question_id, reply_id = store.next_ids("messages", 2)
    question = ConversationMessage(question_id, conv.id, "user", content, now)
    reply = ConversationMessage(reply_id, conv.id, "assistant", text, now)
    # Set explicitly, as it was in Postgres: the picker sorts by use, and
    # "resume the last chat" resumes the head of that list.
    conv = replace(conv, updated_at=now, message_count=len(history) + 2)
    store.put_turn(conv, question, reply, client_message_id)
    return Turn(conv, question, reply)
