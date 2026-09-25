# ADR-034 — The evening report tries again at 19:30, then on the fallback model

**Status:** Accepted · **Date:** 2026-09-25
**Amends:** [ADR-033](033-detail-sheets-writes-and-reports.md) (the fallback report's schedule)

## Context

On 2026-09-25 the 18:30 fallback report failed. Gemini's primary model
answered 503 Service Unavailable three times, which is the first try plus
both retries. `_post_gemini` then gave up on purpose. A 503 is transient
and not a quota signal, so it does not fall through to the fallback model
the way a 429 does. That rule is tested, and it keeps an outage from
spending the second model's budget
(`test_a_persistent_503_gives_up_on_that_model_and_raises`).

The fallback report runs only in the 18:30 hour, so that was the day's
last chance. There was no report and no push.

## Decision

- **19:30 is a last try.** The hourly job calls `run_daily_fallback` again
  one hour after `WAKE_FALLBACK_HOUR`. On a day that already has a report,
  from 18:30 or from New report, this costs one read and nothing else.
- **If the last try fails too, the fallback model gets one request.**
  That happens when the normal call raises a `requests` error: a 503 that
  outlasted its retries, another 5xx, or a timeout. Then
  `run_daily_fallback(last_try=True)` asks the fallback model alone, once,
  without retries. A primary still overloaded an hour later is not about
  to recover, and one request of the fallback's budget is a fair price for
  the day's report.
- **The 503 rule in `_post_gemini` stands** for everything else: New
  report, the 18:30 run, and later the coach chat.
- **Not on a spent budget.** `GeminiQuotaExceeded` is not retried: both
  models share the day's allowance (ADR-013), so the fallback cannot help.
- The log line says when the fallback answered:
  `ok (report N on the fallback model X; push: …)`.

## Consequences

- A report that should have come at 18:30 can arrive at 19:30 instead,
  with its push.
- Worst case, a day spends 3 + 3 requests on the primary and 1 on the
  fallback for the evening report, out of 20 per model.
