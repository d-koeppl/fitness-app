# ADR-037 — Crawling allowed; `/.well-known/` not rewritten to the app

**Status:** Accepted · **Date:** 2026-09-28
**Amends:** [ADR-036](036-web-load-performance.md) (`robots.txt`)

## Context

A local Lighthouse run of the ADR-036 build showed three things:

- **SEO went from 0.91 to 0.63.** The `robots.txt` that disallowed
  everything fails "Page is blocked from indexing", which carries most of
  the SEO weight.
- **CLS was 0.067.** `index.html` had no viewport tag, so the loading
  screen was first laid out at desktop width. It jumped when Flutter added
  its own tag.
- **The agentic audit fetched `/.well-known/ai-catalog.json`.** The
  hosting rewrite answered it with `index.html` and a 200, so the audit
  failed on "malformed JSON". A 404 would make the audit not applicable
  instead.

## Decision

- `robots.txt` allows crawling. Every page needs a sign-in anyway, so a
  crawler only ever sees the sign-in screen.
- `index.html` carries `width=device-width, initial-scale=1.0` from the
  start.
- The SPA rewrite is `!/.well-known/**`, so paths under `/.well-known/`
  that have no file return 404. The app has no routes of its own; the push
  opens the root.

## Consequences

Measured locally (mobile, simulated throttling, 3 runs each):

| Build | Performance | SEO | CLS |
| --- | --- | --- | --- |
| Before ADR-036 | 0.30 | 0.91 | 0 |
| After this ADR | 0.72–0.73 | 1.0 | 0 |

Best Practices stays where it was. The skwasm renderer adds a
`SharedArrayBuffer` deprecation warning, but the engine's
`Intl.v8BreakIterator` warning already failed that audit.
