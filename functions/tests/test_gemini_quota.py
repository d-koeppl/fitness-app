"""Tests for the Gemini call's retry and quota-fallback policy.

The distinction being pinned here is the one the old code got wrong: it
retried 429 and 503 identically, on the same model, 1-2 seconds apart. A
503 clears in a second; a 429 is a refusal about a window at least a minute
long, so retrying it there only delayed the error. Free-tier
requests-per-day is counted per model, so the fallback model is a second
budget rather than a second guess (ADR-013).

This is also the one place in the process that sends a request, so it is
where they are counted — every attempt, whatever came back.
"""

from __future__ import annotations

import pytest
import requests

from api.analysis import gemini
from api.config import settings
from api.integrations import gemini_models

OK_BODY = {"candidates": [{"content": {"parts": [{"text": '{"summary_md": "hi"}'}]}}]}


class FakeResponse:
    def __init__(self, status_code: int, payload: dict | None = None):
        self.status_code = status_code
        self._payload = payload or {}

    def json(self) -> dict:
        return self._payload

    def raise_for_status(self) -> None:
        if self.status_code >= 400:
            raise requests.HTTPError(f"{self.status_code} error", response=self)


@pytest.fixture
def gemini_key(monkeypatch):
    monkeypatch.setattr(settings, "gemini_api_key", "test-key")
    monkeypatch.setattr(settings, "gemini_model", "primary-model")
    monkeypatch.setattr(settings, "gemini_fallback_model", "fallback-model")


@pytest.fixture
def no_sleep(monkeypatch):
    monkeypatch.setattr(gemini.time, "sleep", lambda _seconds: None)


@pytest.fixture(autouse=True)
def counted(monkeypatch) -> list[str]:
    """Collect what would have been written to gemini_usage. These tests are
    about the retry policy and need no store — but the counting happens on
    the same line as the request, so it has to go somewhere."""
    spent: list[str] = []
    monkeypatch.setattr(gemini.gemini_usage, "record", lambda _store, model: spent.append(model))
    return spent


def stub_post(monkeypatch, responses: list[FakeResponse]) -> list[str]:
    """Serve `responses` in order, recording the model each call asked for."""
    asked: list[str] = []
    queue = list(responses)

    def fake_post(url, **kwargs):
        asked.append(url.rsplit("/", 1)[-1].split(":")[0])
        return queue.pop(0)

    monkeypatch.setattr(gemini.requests, "post", fake_post)
    return asked


def test_429_moves_to_the_fallback_model_without_retrying_the_first(monkeypatch, gemini_key, no_sleep):
    asked = stub_post(monkeypatch, [FakeResponse(429), FakeResponse(200, OK_BODY)])

    data, model = gemini._post_gemini(None, {})

    assert data == OK_BODY
    assert model == "fallback-model"
    # One attempt on the primary, not three: the point of the change.
    assert asked == ["primary-model", "fallback-model"]


def test_the_key_travels_in_a_header_not_the_url(monkeypatch, gemini_key):
    """A key in the URL ended up in every HTTPError message, and from there
    in Cloud Logging and the app's error line."""
    sent = {}

    def fake_post(url, **kwargs):
        sent.update(kwargs, url=url)
        return FakeResponse(200, OK_BODY)

    monkeypatch.setattr(gemini.requests, "post", fake_post)
    gemini._post_gemini(None, {})

    assert sent["headers"] == {"x-goog-api-key": "test-key"}
    assert "params" not in sent
    assert "test-key" not in sent["url"]


def test_503_is_retried_on_the_same_model(monkeypatch, gemini_key, no_sleep):
    asked = stub_post(monkeypatch, [FakeResponse(503), FakeResponse(200, OK_BODY)])

    _data, model = gemini._post_gemini(None, {})

    assert model == "primary-model"
    assert asked == ["primary-model", "primary-model"]


def test_a_persistent_503_gives_up_on_that_model_and_raises(monkeypatch, gemini_key, no_sleep):
    """503 is transient, not a quota signal — it must not silently spend the
    fallback model's budget."""
    asked = stub_post(monkeypatch, [FakeResponse(503)] * 3)

    with pytest.raises(requests.HTTPError):
        gemini._post_gemini(None, {})

    assert asked == ["primary-model"] * 3


def test_429_on_every_model_surfaces_as_an_http_error(monkeypatch, gemini_key, no_sleep):
    asked = stub_post(monkeypatch, [FakeResponse(429), FakeResponse(429)])

    with pytest.raises(requests.HTTPError):
        gemini._post_gemini(None, {})

    assert asked == ["primary-model", "fallback-model"]


def test_no_fallback_configured_means_the_429_is_raised_straight_away(monkeypatch, gemini_key, no_sleep):
    monkeypatch.setattr(settings, "gemini_fallback_model", "")
    asked = stub_post(monkeypatch, [FakeResponse(429)])

    with pytest.raises(requests.HTTPError):
        gemini._post_gemini(None, {})

    assert asked == ["primary-model"]


def test_a_fallback_equal_to_the_primary_is_not_tried_twice(monkeypatch, gemini_key):
    monkeypatch.setattr(settings, "gemini_fallback_model", "primary-model")
    assert gemini_models.candidates() == ["primary-model"]


# --- what gets counted ------------------------------------------------------


def test_every_attempt_is_counted_against_the_model_it_was_sent_to(
    monkeypatch, gemini_key, no_sleep, counted
):
    """Including the one that came back 429: it reached Google, so Google
    counted it, so we do too."""
    stub_post(monkeypatch, [FakeResponse(429), FakeResponse(200, OK_BODY)])

    gemini._post_gemini(None, {})

    assert counted == ["primary-model", "fallback-model"]


def test_a_retried_503_costs_two_requests(monkeypatch, gemini_key, no_sleep, counted):
    """A retry is a second request on the same model, not a free one — the
    chat-only counter this replaced would have called it a single message."""
    stub_post(monkeypatch, [FakeResponse(503), FakeResponse(200, OK_BODY)])

    gemini._post_gemini(None, {})

    assert counted == ["primary-model", "primary-model"]


def test_nothing_is_counted_when_the_request_never_left(monkeypatch, gemini_key, counted):
    """A missing key fails before any HTTP call, so it costs nothing."""
    monkeypatch.setattr(settings, "gemini_api_key", "")

    with pytest.raises(RuntimeError):
        gemini._post_gemini(None, {})

    assert counted == []


def test_other_errors_are_raised_rather_than_falling_back(monkeypatch, gemini_key, no_sleep):
    """A 400 means the request is wrong; sending it to a second model would
    just spend that model's quota on the same mistake."""
    asked = stub_post(monkeypatch, [FakeResponse(400)])

    with pytest.raises(requests.HTTPError):
        gemini._post_gemini(None, {})

    assert asked == ["primary-model"]


def test_the_report_records_the_model_that_actually_answered(monkeypatch, gemini_key, no_sleep):
    """ai_reports.model used to be written from settings, so a report served
    by the fallback was filed under the primary's name."""
    stub_post(monkeypatch, [FakeResponse(429), FakeResponse(200, OK_BODY)])

    _parsed, _tokens, model = gemini.call_gemini(None, "prompt")

    assert model == "fallback-model"


def test_a_retired_model_falls_through_to_the_next(monkeypatch, gemini_key, no_sleep):
    """A 404 is a model id Google has retired (ADR-025). The next candidate
    may still exist, so it is tried rather than failing the request."""
    asked = stub_post(monkeypatch, [FakeResponse(404), FakeResponse(200, OK_BODY)])

    _data, model = gemini._post_gemini(None, {})

    assert model == "fallback-model"
    assert asked == ["primary-model", "fallback-model"]


def test_404_on_every_model_surfaces_as_an_http_error(monkeypatch, gemini_key, no_sleep):
    stub_post(monkeypatch, [FakeResponse(404), FakeResponse(404)])

    with pytest.raises(requests.HTTPError):
        gemini._post_gemini(None, {})


def test_an_alias_is_recorded_as_the_model_it_resolved_to(monkeypatch, gemini_key, no_sleep, counted):
    """gemini-flash-latest names no model, so the report files the response's
    modelVersion — while the budget stays keyed by the configured name, the
    thing the next request will be sent to (ADR-025)."""
    monkeypatch.setattr(settings, "gemini_model", "gemini-flash-latest")
    stub_post(monkeypatch, [FakeResponse(200, {**OK_BODY, "modelVersion": "gemini-3.8-flash"})])

    _parsed, _tokens, model = gemini.call_gemini(None, "prompt")

    assert model == "gemini-3.8-flash"
    assert counted == ["gemini-flash-latest"]


def test_a_missing_api_key_is_a_clear_error(monkeypatch):
    monkeypatch.setattr(settings, "gemini_api_key", "")
    with pytest.raises(RuntimeError, match="GEMINI_API_KEY"):
        gemini._post_gemini(None, {})


def test_token_usage_is_logged_per_answer_with_its_purpose(monkeypatch, gemini_key, caplog):
    """The chat's token counts are stored nowhere else, so this line is how
    a cheaper prompt shows up as cheaper. Counts Gemini omits read as 0."""
    usage = {
        "promptTokenCount": 900,
        "candidatesTokenCount": 120,
        "thoughtsTokenCount": 300,
        "totalTokenCount": 1320,
    }
    stub_post(
        monkeypatch,
        [FakeResponse(200, {**OK_BODY, "usageMetadata": usage, "modelVersion": "gemini-3.8-flash"})],
    )

    with caplog.at_level("INFO", logger="api.analysis.gemini"):
        gemini.chat_completion(None, "system", [{"role": "user", "content": "hi"}])

    assert (
        "Gemini usage: purpose=coach model=gemini-3.8-flash "
        "prompt=900 cached=0 output=120 thinking=300 total=1320"
    ) in caplog.messages


def test_a_refused_attempt_logs_no_usage(monkeypatch, gemini_key, caplog):
    stub_post(monkeypatch, [FakeResponse(429), FakeResponse(200, OK_BODY)])

    with caplog.at_level("INFO", logger="api.analysis.gemini"):
        gemini._post_gemini(None, {})

    usage_lines = [m for m in caplog.messages if m.startswith("Gemini usage")]
    assert usage_lines == [
        "Gemini usage: purpose=report model=fallback-model prompt=0 cached=0 output=0 thinking=0 total=0"
    ]


def bad_body(text: str | None, finish: str = "STOP") -> dict:
    parts = [{"text": text}] if text is not None else []
    return {"candidates": [{"content": {"parts": parts}, "finishReason": finish}]}


@pytest.mark.parametrize(
    "body",
    [
        bad_body('{"summary_md": "cut off'),
        bad_body("not json at all"),
        bad_body("[1, 2]"),
        bad_body(None, finish="SAFETY"),
        {"candidates": []},
    ],
)
def test_an_unreadable_reply_is_retried_once_then_succeeds(monkeypatch, gemini_key, no_sleep, body):
    """Seen in production (2026-10-13): Gemini answered, the reply could not
    be read, and the unhandled error became a bare 500 for a report that the
    next attempt would have produced."""
    asked = stub_post(monkeypatch, [FakeResponse(200, body), FakeResponse(200, OK_BODY)])

    parsed, _tokens, _model = gemini.call_gemini(None, "prompt")

    assert parsed == {"summary_md": "hi"}
    assert asked == ["primary-model", "primary-model"]


def test_a_persistent_bad_reply_is_an_http_error_not_a_crash(monkeypatch, gemini_key, no_sleep, caplog):
    """HTTPError is what the router turns into a 502 with a sentence, and
    what the evening fallback retries on the other model."""
    asked = stub_post(monkeypatch, [FakeResponse(200, bad_body("nope"))] * 2)

    caplog.set_level("WARNING", logger="api.analysis.gemini")
    with pytest.raises(gemini.GeminiBadReply) as err:
        gemini.call_gemini(None, "prompt")

    assert isinstance(err.value, requests.HTTPError)
    assert asked == ["primary-model"] * 2
    # The raw text is logged, so the next one is diagnosable.
    assert "'nope'" in caplog.text


def test_no_retries_means_no_second_try_on_an_unreadable_reply(monkeypatch, gemini_key, no_sleep):
    asked = stub_post(monkeypatch, [FakeResponse(200, bad_body("nope"))])

    with pytest.raises(gemini.GeminiBadReply):
        gemini.call_gemini(None, "prompt", max_retries=0)

    assert asked == ["primary-model"]
