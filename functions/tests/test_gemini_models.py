"""Tests for the rolling Gemini fallback (ADR-025).

The rule being pinned: the fallback is the newest *stable* Flash that is
older than what the primary actually serves — 3.7 under a 3.8 alias, 3.8
once the alias moves to 3.9 — because it only helps if Google counts it as a
separate requests-per-day budget.
"""

from __future__ import annotations

import pytest
import requests

from api.config import settings
from api.integrations import gemini_models

LISTED = [
    {"name": "models/gemini-3.6-flash", "supportedGenerationMethods": ["generateContent"]},
    {"name": "models/gemini-3.8-flash", "supportedGenerationMethods": ["generateContent"]},
    {"name": "models/gemini-3.7-flash", "supportedGenerationMethods": ["generateContent"]},
    {"name": "models/gemini-3.9-flash-preview-09-2026", "supportedGenerationMethods": ["generateContent"]},
    {"name": "models/gemini-3.5-flash-lite", "supportedGenerationMethods": ["generateContent"]},
    {"name": "models/gemini-flash-latest", "supportedGenerationMethods": ["generateContent"]},
    {"name": "models/gemini-3.10-flash", "supportedGenerationMethods": ["embedContent"]},
    {"name": "models/gemini-3.8-pro", "supportedGenerationMethods": ["generateContent"]},
]


class FakeResponse:
    def __init__(self, payload: dict, status_code: int = 200):
        self._payload = payload
        self.status_code = status_code

    def json(self) -> dict:
        return self._payload

    def raise_for_status(self) -> None:
        if self.status_code >= 400:
            raise requests.HTTPError(f"{self.status_code} error", response=self)


@pytest.fixture
def auto(monkeypatch):
    monkeypatch.setattr(settings, "gemini_api_key", "test-key")
    monkeypatch.setattr(settings, "gemini_model", "gemini-flash-latest")
    monkeypatch.setattr(settings, "gemini_fallback_model", gemini_models.AUTO)


def stub_list(monkeypatch, pages: list[FakeResponse]) -> list[dict]:
    calls: list[dict] = []
    queue = list(pages)

    def fake_get(url, params, headers, timeout):
        assert headers == {"x-goog-api-key": "test-key"}
        assert "key" not in params, "the key must never be in the URL"
        calls.append(dict(params))
        return queue.pop(0)

    monkeypatch.setattr(gemini_models.requests, "get", fake_get)
    return calls


def test_only_stable_generate_content_flash_models_are_kept_newest_first():
    assert gemini_models.stable_flash_models(LISTED) == [
        "gemini-3.8-flash",
        "gemini-3.7-flash",
        "gemini-3.6-flash",
    ]


def test_versions_compare_as_numbers_not_strings():
    """3.10 is newer than 3.9 — a string sort would say otherwise."""
    listed = [
        {"name": f"models/gemini-{v}-flash", "supportedGenerationMethods": ["generateContent"]}
        for v in ("3.9", "3.10", "4")
    ]
    assert gemini_models.stable_flash_models(listed) == [
        "gemini-4-flash",
        "gemini-3.10-flash",
        "gemini-3.9-flash",
    ]


def test_a_preview_counts_by_its_version():
    assert gemini_models.flash_version("gemini-3.9-flash-preview-09-2026") == (3, 9)
    assert gemini_models.flash_version("gemini-flash-latest") is None


@pytest.mark.parametrize(
    ("served", "fallback"),
    [
        ("gemini-3.8-flash", "gemini-3.7-flash"),
        ("gemini-3.9-flash-preview-09-2026", "gemini-3.8-flash"),
        ("gemini-3.9-flash", "gemini-3.8-flash"),
        ("gemini-3.6-flash", None),
    ],
)
def test_the_fallback_is_the_newest_stable_below_what_the_primary_serves(served, fallback):
    stable = ["gemini-3.8-flash", "gemini-3.7-flash", "gemini-3.6-flash"]
    assert gemini_models.pick_fallback(stable, served) == fallback


def test_an_alias_not_yet_seen_is_taken_to_be_the_newest_stable():
    stable = ["gemini-3.8-flash", "gemini-3.7-flash"]
    assert gemini_models.pick_fallback(stable, "gemini-flash-latest") == "gemini-3.7-flash"


def test_candidates_before_the_primary_has_answered(monkeypatch, auto):
    stub_list(monkeypatch, [FakeResponse({"models": LISTED})])
    assert gemini_models.candidates() == ["gemini-flash-latest", "gemini-3.7-flash"]


def test_the_fallback_moves_up_when_the_alias_does(monkeypatch, auto):
    stub_list(monkeypatch, [FakeResponse({"models": LISTED})])
    gemini_models.note_primary_answered("gemini-3.9-flash-preview-09-2026")
    assert gemini_models.candidates() == ["gemini-flash-latest", "gemini-3.8-flash"]


def test_the_list_is_fetched_once_and_paged(monkeypatch, auto):
    calls = stub_list(
        monkeypatch,
        [
            FakeResponse({"models": LISTED[:2], "nextPageToken": "p2"}),
            FakeResponse({"models": LISTED[2:]}),
        ],
    )
    gemini_models.candidates()
    gemini_models.candidates()

    assert [c.get("pageToken") for c in calls] == [None, "p2"]


def test_a_failed_listing_runs_on_the_primary_alone(monkeypatch, auto):
    stub_list(monkeypatch, [FakeResponse({}, status_code=500)])
    assert gemini_models.candidates() == ["gemini-flash-latest"]


def test_no_api_key_means_no_listing(monkeypatch, auto):
    monkeypatch.setattr(settings, "gemini_api_key", "")
    calls = stub_list(monkeypatch, [])
    assert gemini_models.candidates() == ["gemini-flash-latest"]
    assert calls == []


def test_a_pinned_fallback_is_used_as_is(monkeypatch, auto):
    monkeypatch.setattr(settings, "gemini_fallback_model", "gemini-3.6-flash")
    calls = stub_list(monkeypatch, [])
    assert gemini_models.candidates() == ["gemini-flash-latest", "gemini-3.6-flash"]
    assert calls == []
