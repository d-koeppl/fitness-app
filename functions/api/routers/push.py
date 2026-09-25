"""api/routers/push.py — which devices get the report-ready push (ADR-030).

The app registers its FCM token whenever it starts with notifications
allowed, since FCM may rotate it, and removes it on sign-out. Sending is not
an endpoint: only the hourly job's fallback report pushes
(api/services/push.py). fitness-dashboard's test-push button is gone.
"""

from __future__ import annotations

from fastapi import APIRouter, Depends, Response

from api.schemas.push import PushDeviceIn, PushDeviceOut, PushTokenIn
from api.services import push
from api.store.firestore import FirestoreStore, get_store
from api.store.rows import PushDevice

router = APIRouter(prefix="/push", tags=["push"])


@router.put("/devices", response_model=PushDeviceOut)
def register_push_device(body: PushDeviceIn, store: FirestoreStore = Depends(get_store)) -> PushDevice:
    """Idempotent: the same token again just refreshes its date."""
    return push.register(store, body.token, body.platform)


@router.delete("/devices", status_code=204, response_class=Response)
def unregister_push_device(body: PushTokenIn, store: FirestoreStore = Depends(get_store)) -> Response:
    """204 whether or not the token was registered, so a retry is harmless."""
    push.unregister(store, body.token)
    return Response(status_code=204)
