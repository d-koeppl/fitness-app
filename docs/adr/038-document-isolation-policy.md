# ADR-038 — Cross-origin isolation through `Document-Isolation-Policy`

**Status:** Accepted · **Date:** 2026-09-28
**Amends:** [ADR-036](036-web-load-performance.md) (no COOP/COEP, skwasm single-threaded)

## Context

skwasm renders on a worker thread only when the page is cross-origin
isolated (`window.crossOriginIsolated`); otherwise it draws on the main
thread and logs a warning. It also creates a `SharedArrayBuffer` either way,
which Lighthouse reports as a deprecation. ADR-036 left isolation off
because the usual way to get it breaks sign-in: `Cross-Origin-Opener-Policy:
same-origin` cuts the page off from the `signInWithPopup` window on
`fitness-75c22.firebaseapp.com`, and `Cross-Origin-Embedder-Policy` blocks
Google's auth iframes, which do not opt in.

`Document-Isolation-Policy` (Chromium 137 and later) isolates one document
without either header: it needs no opener change, and embedded frames do not
have to opt in.

## Decision

Hosting sends `Document-Isolation-Policy: isolate-and-credentialless` on
every response (`firebase.json`). COOP and COEP stay unset.

On a preview channel, headless Chromium reported `crossOriginIsolated`
true, skwasm started its worker, and the sign-in popup reached Google's
account page with `window.opener` intact. The median Lighthouse mobile run
went from Performance 72 to 81, with Total Blocking Time down from 850 ms to
460 ms. Desktop stayed at 95–96.

## Consequences

- Browsers without the header (Firefox, Safari, older Chromium) ignore it
  and run skwasm single-threaded, as before.
- `credentialless` sends cross-origin no-CORS subresource requests without
  cookies. Nothing the app loads that way needs them; the API is called
  with CORS and a bearer token.
- Adding COOP or COEP later would break the sign-in popup; this header is
  the one to keep.
- Best Practices stays at 81: the remaining deprecation,
  `Intl.v8BreakIterator`, is in the Flutter engine (ADR-036).
