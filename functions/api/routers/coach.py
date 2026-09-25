"""api/routers/coach.py — the app's Coach tab.

The client sends its "include" toggles and one message, naming the
conversation it belongs to; the history, the system prompt and all data
assembly happen server-side (api/services/conversations.py,
api/analysis/coach.py). The client can supply neither a prompt nor a prior
turn — see those modules' docstrings for why each mattered.

It can pin workouts (ADR-021), but only by id: `session_ids` names sessions
the server then reads out of its own store, in full, heart rate trace and
all. That keeps the rule ADR-010 established — the client chooses *which*
data, never what the data says.

Each message is also one Gemini request out of the day's shared budget, so
it is checked against the chat's ceiling first: the chat stops short of the
total to leave the daily report somewhere to go
(api/services/gemini_usage.py, ADR-013). The day is Google's — midnight
Pacific — not the user's. A resent message (same `client_message_id`) is
answered from the store and checks no budget, because it spends none
(ADR-035).
"""

from __future__ import annotations

import logging

from fastapi import APIRouter, Depends, HTTPException, Response
from requests import HTTPError

from api.schemas.coach import (
    ChatMessageOut,
    ChatRequest,
    ChatResponse,
    CoachUsageOut,
    ConversationDetailOut,
    ConversationOut,
    IncludeFlags,
    ModelUsageOut,
)
from api.services import conversations, gemini_usage
from api.store.firestore import FirestoreStore, get_store
from api.store.rows import Conversation

logger = logging.getLogger("api.routers.coach")

router = APIRouter(prefix="/coach", tags=["coach"])


def _out(usage: gemini_usage.Usage) -> CoachUsageOut:
    return CoachUsageOut(
        used=usage.used,
        limit=usage.limit,
        chat_remaining=usage.chat_remaining,
        resets_at=usage.resets_at,
        models=[ModelUsageOut(model=m.model, used=m.used, limit=m.limit) for m in usage.models],
    )


def _conversation_out(conv: Conversation) -> ConversationOut:
    return ConversationOut(
        id=conv.id,
        title=conv.title,
        created_at=conv.created_at,
        updated_at=conv.updated_at,
        message_count=conv.message_count,
    )


def _not_found(conversation_id: int) -> HTTPException:
    return HTTPException(status_code=404, detail=f"No conversation with id {conversation_id}")


@router.get("/usage", response_model=CoachUsageOut)
def get_coach_usage(store: FirestoreStore = Depends(get_store)) -> CoachUsageOut:
    """What the Coach tab shows above the conversation before a message is sent."""
    return _out(gemini_usage.snapshot(store))


@router.get("/conversations", response_model=list[ConversationOut])
def list_conversations(store: FirestoreStore = Depends(get_store)) -> list[ConversationOut]:
    """The chat picker, most recently used first. The head of this list is
    what the tab resumes into when it is opened."""
    return [_conversation_out(conv) for conv in conversations.list_conversations(store)]


@router.get("/conversations/{conversation_id}", response_model=ConversationDetailOut)
def get_conversation(
    conversation_id: int, store: FirestoreStore = Depends(get_store)
) -> ConversationDetailOut:
    conv = conversations.get_conversation(store, conversation_id)
    if conv is None:
        raise _not_found(conversation_id)
    messages = conversations.messages_for(store, conv.id)
    return ConversationDetailOut(
        **_conversation_out(conv).model_dump(),
        include=IncludeFlags(**conv.include),
        lookback_days=conv.lookback_days,
        session_ids=list(conv.session_ids),
        messages=[ChatMessageOut.model_validate(m) for m in messages],
    )


@router.delete("/conversations/{conversation_id}", status_code=204)
def delete_conversation(conversation_id: int, store: FirestoreStore = Depends(get_store)) -> Response:
    if not conversations.delete_conversation(store, conversation_id):
        raise _not_found(conversation_id)
    return Response(status_code=204)


@router.post("/chat", response_model=ChatResponse)
def send_coach_message(body: ChatRequest, store: FirestoreStore = Depends(get_store)) -> ChatResponse:
    # Checked before the call; the request itself is counted inside
    # _post_gemini, once per attempt it actually makes. 429 mirrors what
    # Gemini would say if we let it through. A resend of an answered
    # message spends nothing, so it is let through even on a spent day.
    try:
        if not conversations.already_answered(store, body.client_message_id):
            gemini_usage.require_chat_budget(store)
    except gemini_usage.GeminiQuotaExceeded as exc:
        raise HTTPException(status_code=429, detail=str(exc)) from exc

    try:
        turn = conversations.reply_to(
            store,
            body.conversation_id,
            body.content,
            body.include,
            body.lookback_days,
            body.session_ids,
            body.client_message_id,
        )
    except conversations.ChatInProgress as exc:
        raise HTTPException(status_code=409, detail=str(exc)) from exc
    except LookupError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    except RuntimeError as exc:
        raise HTTPException(status_code=500, detail=str(exc)) from exc
    except HTTPError as exc:
        logger.exception("Gemini chat call failed")
        raise HTTPException(status_code=502, detail=f"Gemini request failed: {exc}") from exc

    # Re-read rather than reuse the pre-call snapshot: the reply may have
    # cost more than one request if it fell through to the fallback model.
    return ChatResponse(
        conversation=_conversation_out(turn.conversation),
        message=ChatMessageOut.model_validate(turn.question),
        reply=ChatMessageOut.model_validate(turn.reply),
        usage=_out(gemini_usage.snapshot(store)),
    )
