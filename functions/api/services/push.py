"""api/services/push.py — the report-ready push, through FCM (ADR-030).

One message, to every registered device: the automatic evening report is
ready. Nothing else pushes. New report does not, because whoever tapped it
is already looking at the result (ADR-016).

Replaces fitness-dashboard's Web Push sender (its ADR-005). FCM reaches the
Android app and the browser build through one API, and the functions'
own service account is allowed to send, so there are no VAPID or server
keys to keep. The browser needs a public VAPID key, and it is compiled into
the app.

A device FCM says is gone is deleted here, as the old sender pruned a
410 Gone: the token of an uninstalled app, a cleared browser, or one the
app deleted itself because notifications were switched off.
"""

from __future__ import annotations

import logging
from datetime import UTC, datetime

from api.config import settings
from api.store.firestore import FirestoreStore
from api.store.rows import AiReport, PushDevice

logger = logging.getLogger("api.push")

PLATFORMS = ("android", "web")
TITLE = "Fitness report ready"


def register(store: FirestoreStore, token: str, platform: str) -> PushDevice:
    device = PushDevice(token=token, platform=platform, registered_at=datetime.now(UTC))
    store.put_push_device(device)
    return device


def unregister(store: FirestoreStore, token: str) -> None:
    store.delete_push_devices([token])


def headline(report: AiReport) -> str:
    """The notification's text: the report's one-sentence reason for today's
    readiness, as the old push had."""
    return (report.insights or {}).get("readiness_reason") or "Your report is ready."


def _send(tokens: list[str], report: AiReport) -> list[Exception | None]:
    """One FCM multicast. Returns, per token, the error it failed with or
    None. Kept apart so the tests can stand in for FCM."""
    from firebase_admin import messaging

    from api.auth import firebase_app

    message = messaging.MulticastMessage(
        tokens=tokens,
        notification=messaging.Notification(title=TITLE, body=headline(report)),
        # The app reads this to open the report rather than just the app.
        data={"report_id": str(report.id)},
        # Replaces an unread one from yesterday instead of stacking.
        android=messaging.AndroidConfig(notification=messaging.AndroidNotification(tag="report")),
        webpush=messaging.WebpushConfig(
            notification=messaging.WebpushNotification(tag="report", icon="/icons/Icon-192.png"),
            fcm_options=messaging.WebpushFCMOptions(link=settings.web_app_url),
        ),
    )
    response = messaging.send_each_for_multicast(message, app=firebase_app())
    return [r.exception for r in response.responses]


def _is_gone(error: Exception) -> bool:
    from firebase_admin import messaging

    # Unregistered: the app was uninstalled or deleted its token.
    # SenderIdMismatch: the token belongs to another Firebase project.
    # Anything else (quota, a network fault, FCM itself) may pass, so the
    # device stays.
    return isinstance(error, (messaging.UnregisteredError, messaging.SenderIdMismatchError))


def notify_report_ready(store: FirestoreStore, report: AiReport) -> str:
    """Push the report to every device; returns what happened, for the
    hourly job's log line."""
    devices = store.push_devices()
    if not devices:
        return "no devices"
    tokens = [device.token for device in devices]
    errors = _send(tokens, report)

    outcomes = list(zip(tokens, errors, strict=True))
    gone = [token for token, error in outcomes if error is not None and _is_gone(error)]
    failed = [error for _, error in outcomes if error is not None and not _is_gone(error)]
    for error in failed:
        logger.warning("Push failed: %s", error)
    if gone:
        store.delete_push_devices(gone)

    sent = len(tokens) - len(gone) - len(failed)
    return f"sent {sent}, pruned {len(gone)}, failed {len(failed)}"
