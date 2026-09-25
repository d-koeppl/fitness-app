"""The report-ready push (ADR-030): which devices get it, and what FCM is sent."""

from __future__ import annotations

from datetime import UTC, date, datetime
from types import SimpleNamespace

import pytest
from firebase_admin import messaging

from api.services import push
from api.store.rows import AiReport

REASON = {"readiness_reason": "Legs are fresh after two easy days."}


def _report(insights: dict | None = None) -> AiReport:
    return AiReport(
        id=7,
        created_at=datetime(2026, 9, 25, 16, 30, tzinfo=UTC),
        trigger="daily_fallback",
        model="gemini-flash-latest",
        prompt_version="v5",
        summary_md="…",
        period_start=date(2026, 9, 18),
        period_end=date(2026, 9, 25),
        insights=REASON if insights is None else insights,
    )


# --- the store ------------------------------------------------------------------


def test_a_device_registered_twice_is_stored_once(store):
    push.register(store, "tok:1", "web")
    push.register(store, "tok:1", "android")
    push.register(store, "tok/2", "web")

    devices = sorted(store.push_devices(), key=lambda d: d.token)
    assert [(d.token, d.platform) for d in devices] == [("tok/2", "web"), ("tok:1", "android")]
    assert all(d.registered_at is not None for d in devices)


def test_unregistering_removes_only_that_device(store):
    push.register(store, "a", "web")
    push.register(store, "b", "android")

    push.unregister(store, "a")
    push.unregister(store, "never-registered")

    assert [d.token for d in store.push_devices()] == ["b"]


# --- the API --------------------------------------------------------------------


def test_the_app_registers_and_unregisters_its_token(api_client, store):
    response = api_client.put("/push/devices", json={"token": "fcm-token", "platform": "android"})
    assert response.status_code == 200
    assert response.json()["platform"] == "android"
    assert "token" not in response.json()
    assert [d.token for d in store.push_devices()] == ["fcm-token"]

    response = api_client.request("DELETE", "/push/devices", json={"token": "fcm-token"})
    assert response.status_code == 204
    assert store.push_devices() == []

    # Again: nothing to remove, still fine.
    assert api_client.request("DELETE", "/push/devices", json={"token": "fcm-token"}).status_code == 204


@pytest.mark.parametrize(
    "body",
    [
        {"token": "t", "platform": "ios"},
        {"token": "", "platform": "web"},
        {"platform": "web"},
    ],
)
def test_a_malformed_registration_is_refused(api_client, store, body):
    assert api_client.put("/push/devices", json=body).status_code == 422
    assert store.push_devices() == []


# --- sending ----------------------------------------------------------------------


def test_the_headline_is_the_readiness_reason():
    assert push.headline(_report()) == "Legs are fresh after two easy days."
    assert push.headline(_report({})) == "Your report is ready."


def test_nothing_is_sent_without_devices(store, monkeypatch):
    def fail(*_):
        raise AssertionError("FCM called with no devices")

    monkeypatch.setattr(push, "_send", fail)
    assert push.notify_report_ready(store, _report()) == "no devices"


def test_gone_devices_are_pruned_and_others_kept(store, monkeypatch):
    for token in ("ok", "uninstalled", "flaky"):
        push.register(store, token, "android")
    outcomes = {
        "ok": None,
        "uninstalled": messaging.UnregisteredError("Requested entity was not found."),
        "flaky": messaging.QuotaExceededError("Try later."),
    }
    monkeypatch.setattr(push, "_send", lambda tokens, report: [outcomes[t] for t in tokens])

    assert push.notify_report_ready(store, _report()) == "sent 1, pruned 1, failed 1"
    assert sorted(d.token for d in store.push_devices()) == ["flaky", "ok"]


def test_the_fcm_message(monkeypatch):
    sent = {}

    def send_each_for_multicast(message, app):
        sent["message"], sent["app"] = message, app
        return SimpleNamespace(responses=[SimpleNamespace(exception=None) for _ in message.tokens])

    monkeypatch.setattr(messaging, "send_each_for_multicast", send_each_for_multicast)
    monkeypatch.setattr("api.auth.firebase_app", lambda: "the-app")

    assert push._send(["a", "b"], _report()) == [None, None]

    message = sent["message"]
    assert sent["app"] == "the-app"
    assert message.tokens == ["a", "b"]
    assert message.notification.title == "Fitness report ready"
    assert message.notification.body == "Legs are fresh after two easy days."
    assert message.data == {"report_id": "7"}
    assert message.android.notification.tag == "report"
    assert message.webpush.fcm_options.link == "https://fitness-75c22.web.app"
