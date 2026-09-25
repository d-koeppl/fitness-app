"""The coach's stored chats — api/services/conversations.py (ADR-017, ADR-035).

Driven against the service rather than through HTTP: the endpoints are
covered in test_api.py, and what is worth pinning here is the behaviour the
router never sees — that the picker's order tracks *use* and not creation,
that deleting a chat takes its messages with it, and that a resumed chat is
still held at the settings it was held at.

Needs the Firestore emulator (`store` fixture): the batch that writes a turn
and the subcollection a delete has to empty are Firestore's, so an
in-memory stand-in would prove nothing.
"""

from __future__ import annotations

import pytest

from api.schemas.coach import IncludeFlags
from api.services import conversations
from api.store.rows import Conversation


@pytest.fixture
def answered(monkeypatch):
    """Stub the Gemini call, and record the turns it was handed."""
    seen: dict = {}

    def fake_answer(_store, include, messages, lookback=None, session_ids=None):
        seen["include"] = include
        seen["messages"] = messages
        seen["lookback"] = lookback
        seen["session_ids"] = session_ids
        return "ok"

    monkeypatch.setattr(conversations.coach, "answer", fake_answer)
    return seen


def reply(store, conversation_id, content, include=None, lookback=14, **kwargs):
    return conversations.reply_to(
        store,
        conversation_id,
        content,
        include if include is not None else IncludeFlags(),
        lookback,
        **kwargs,
    )


# --- titles -----------------------------------------------------------------
#
# Pure, but they belong next to what uses them.


def test_derive_title_uses_the_first_message():
    assert conversations.derive_title("how am I doing?") == "how am I doing?"


def test_derive_title_collapses_whitespace():
    assert conversations.derive_title("  how   am\nI doing? ") == "how am I doing?"


def test_derive_title_truncates_on_a_word_boundary():
    title = conversations.derive_title("word " * 40)
    assert len(title) <= conversations.TITLE_MAX + 1  # the ellipsis
    assert title.endswith("…")
    assert not title.endswith(" …")


def test_derive_title_hard_cuts_a_single_long_token():
    # No boundary to cut on; an empty title would be worse than a blunt one.
    title = conversations.derive_title("x" * 200)
    assert title == "x" * conversations.TITLE_MAX + "…"


def test_derive_title_falls_back_when_there_is_nothing_to_name_it_by():
    assert conversations.derive_title("   ") == conversations.DEFAULT_TITLE


# --- one turn ---------------------------------------------------------------


def test_a_first_message_starts_a_conversation_titled_after_it(store, answered):
    turn = reply(store, None, "how am I doing?")
    assert turn.conversation.id > 0
    assert turn.conversation.title == "how am I doing?"
    assert turn.conversation.message_count == 2
    assert (turn.question.role, turn.question.content) == ("user", "how am I doing?")
    assert (turn.reply.role, turn.reply.content) == ("assistant", "ok")


def test_ids_continue_from_the_migrated_ones(store, answered):
    """The migration raises both counters past Postgres's ids, so a new chat
    cannot overwrite an old one."""
    store.raise_counter("conversations", 41)
    store.raise_counter("messages", 900)
    turn = reply(store, None, "hi")
    assert turn.conversation.id == 42
    assert (turn.question.id, turn.reply.id) == (901, 902)


def test_the_title_is_not_rewritten_by_later_messages(store, answered):
    first = reply(store, None, "how am I doing?")
    later = reply(store, first.conversation.id, "and my sleep?")
    assert later.conversation.title == "how am I doing?"


def test_the_stored_history_is_what_reaches_the_model(store, answered):
    """The ADR-017 invariant: the model sees the conversation the server
    holds, in order, and nothing the caller supplied."""
    first = reply(store, None, "first")
    reply(store, first.conversation.id, "second")

    assert answered["messages"] == [
        {"role": "user", "content": "first"},
        {"role": "assistant", "content": "ok"},
        {"role": "user", "content": "second"},
    ]


def test_an_unknown_conversation_is_refused(store, answered):
    with pytest.raises(LookupError):
        reply(store, 9999, "hi")


def test_a_failed_reply_stores_nothing(store, monkeypatch):
    """Both turns are written after the model answers, in one batch, so a
    failure leaves no question in the transcript with nothing under it."""

    def boom(*_args, **_kwargs):
        raise RuntimeError("Gemini is not configured")

    monkeypatch.setattr(conversations.coach, "answer", boom)
    with pytest.raises(RuntimeError):
        reply(store, None, "hi")

    assert conversations.list_conversations(store) == []


def test_a_failed_reply_leaves_an_existing_chat_as_it_was(store, answered, monkeypatch):
    first = reply(store, None, "hi", lookback=14)

    monkeypatch.setattr(conversations.coach, "answer", lambda *_a, **_k: 1 / 0)
    with pytest.raises(ZeroDivisionError):
        reply(store, first.conversation.id, "again", lookback=730)

    kept = conversations.get_conversation(store, first.conversation.id)
    assert kept.lookback_days == 14
    assert kept.message_count == 2
    assert len(conversations.messages_for(store, first.conversation.id)) == 2


# --- the settings a chat is held at -----------------------------------------


def test_a_new_conversation_keeps_the_settings_it_was_started_with(store, answered):
    flags = IncludeFlags(health=True, exercises=False, matches=False, events=False, report=False)
    turn = reply(store, None, "hi", flags, 730)
    assert turn.conversation.lookback_days == 730
    assert turn.conversation.include["exercises"] is False
    # 14 is the report's own window, so anything else is a deliberate ask and
    # goes through as itself.
    assert answered["lookback"] == 730


def test_the_report_default_lookback_is_passed_on_as_unset(store, answered):
    """14 means "unset" downstream, so matches keep their last-few-by-count
    fallback rather than being windowed to an empty fortnight."""
    reply(store, None, "hi")
    assert answered["lookback"] is None


def test_omitted_settings_keep_the_conversation_where_it_was(store, answered):
    first = reply(store, None, "hi", lookback=730)
    again = conversations.reply_to(store, first.conversation.id, "again", None, None)
    assert again.conversation.lookback_days == 730
    assert answered["lookback"] == 730


def test_changing_the_toggles_mid_chat_sticks(store, answered):
    first = reply(store, None, "hi")
    flags = IncludeFlags(health=False, exercises=False, matches=True, events=False, report=False)
    reply(store, first.conversation.id, "again", flags, 90)
    stored = conversations.get_conversation(store, first.conversation.id)
    assert stored.lookback_days == 90
    assert stored.include["matches"] is True
    assert stored.include["health"] is False


# --- the picker -------------------------------------------------------------


def test_conversations_are_listed_most_recently_used_first(store, answered):
    """Ordered by use, not creation. This is what "resume the last chat"
    reads, and `updated_at` only moves because the service sets it."""
    first = reply(store, None, "oldest")
    second = reply(store, None, "newest")
    # Go back to the older one: it should come back to the top.
    reply(store, first.conversation.id, "still talking")

    listed = conversations.list_conversations(store)
    assert [conv.id for conv in listed] == [first.conversation.id, second.conversation.id]


def test_the_list_carries_each_chat_s_message_count(store, answered):
    first = reply(store, None, "hi")
    reply(store, first.conversation.id, "again")
    assert conversations.list_conversations(store)[0].message_count == 4


def test_an_empty_conversation_lists_with_no_messages(store):
    """Nothing creates one of these today — a chat is written on its first
    message — but a migrated row could be one, and must read 0."""
    store.put_conversation(Conversation(id=1, title="empty"))
    assert conversations.list_conversations(store)[0].message_count == 0


def test_messages_come_back_in_order(store, answered):
    first = reply(store, None, "first")
    reply(store, first.conversation.id, "second")
    stored = conversations.messages_for(store, first.conversation.id)
    assert [(m.role, m.content) for m in stored] == [
        ("user", "first"),
        ("assistant", "ok"),
        ("user", "second"),
        ("assistant", "ok"),
    ]


def test_deleting_a_conversation_takes_its_messages_with_it(store, answered):
    """Firestore does not delete a subcollection with its parent document;
    the store has to, or the messages outlive the chat."""
    doomed = reply(store, None, "hi")
    other = reply(store, None, "keep me")

    assert conversations.delete_conversation(store, doomed.conversation.id) is True

    assert conversations.get_conversation(store, doomed.conversation.id) is None
    assert conversations.messages_for(store, doomed.conversation.id) == []
    # The other chat is untouched.
    assert len(conversations.messages_for(store, other.conversation.id)) == 2


def test_deleting_a_conversation_that_is_not_there_says_so(store):
    assert conversations.delete_conversation(store, 9999) is False


# --- the window the model actually sees -------------------------------------


def test_a_long_conversation_is_trimmed_before_it_is_sent(store, answered, monkeypatch):
    """Every turn is kept and shown; only a window is replayed. The day's
    budget counts requests, not tokens (ADR-013), so this changes what a
    turn costs and never how many are left."""
    monkeypatch.setattr(conversations.coach.settings, "coach_history_messages", 4)
    first = reply(store, None, "one")
    for text in ("two", "three", "four"):
        reply(store, first.conversation.id, text)

    # Stored whole...
    assert len(conversations.messages_for(store, first.conversation.id)) == 8
    # ...sent trimmed. Four back from seven turns lands on an assistant one,
    # and that is dropped rather than kept: a window opening on an answer
    # reads as a conversation whose first question is missing.
    assert answered["messages"] == [
        {"role": "user", "content": "three"},
        {"role": "assistant", "content": "ok"},
        {"role": "user", "content": "four"},
    ]


# --- resends (ADR-035) ------------------------------------------------------


def test_a_resend_returns_the_same_turn(store, answered):
    first = reply(store, None, "hi", client_message_id="msg-00000001")
    again = reply(store, None, "hi", client_message_id="msg-00000001")
    assert again == first
    assert len(conversations.list_conversations(store)) == 1


def test_a_resend_into_an_existing_chat_adds_nothing(store, answered):
    first = reply(store, None, "hi")
    reply(store, first.conversation.id, "again", client_message_id="msg-00000002")
    reply(store, first.conversation.id, "again", client_message_id="msg-00000002")
    assert len(conversations.messages_for(store, first.conversation.id)) == 4


def test_a_pending_claim_blocks_a_second_copy(store, answered):
    from datetime import UTC, datetime, timedelta

    store.claim_chat_request("msg-00000001", datetime.now(UTC) - timedelta(minutes=1))
    with pytest.raises(conversations.ChatInProgress):
        reply(store, None, "hi", client_message_id="msg-00000001")
    assert "messages" not in answered


def test_already_answered_is_only_true_once_the_turn_is_stored(store, answered):
    assert conversations.already_answered(store, None) is False
    assert conversations.already_answered(store, "msg-00000001") is False
    reply(store, None, "hi", client_message_id="msg-00000001")
    assert conversations.already_answered(store, "msg-00000001") is True
