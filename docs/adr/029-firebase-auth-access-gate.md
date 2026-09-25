# ADR-029 — Firebase ID tokens and an email allowlist as the access gate

**Status:** Accepted · **Date:** 2026-09-25
**Supersedes:** in fitness-dashboard, [ADR-006](https://github.com/d-koeppl/fitness-dashboard/blob/main/docs/adr/006-auth-oauth-and-secrets.md)'s access gate (Cloudflare Access in front of an API with no auth of its own). Its token-at-rest encryption for the Google OAuth grants stands.

## Context

ADR-006 put access control in the network: Cloudflare Access in front of
both hostnames, and no authentication in the API. That worked for a
browser, which carries Access's session cookie, and it had already failed
twice in practice (its 2026-08-31 and 2026-09-01 amendments). A native
Android or iOS app cannot do Access's browser login at all, and under
Route C ([ADR-028](028-route-c-firebase.md)) the API is a public Cloud
Function URL with no network layer in front of it. The API has to check
callers itself.

## Decision

- **The app signs in with Google through Firebase Auth** and sends the
  Firebase ID token as `Authorization: Bearer …` on every request. The web
  uses Firebase's popup. Android (and iOS, phase 9) uses the native
  account picker from `google_sign_in` and hands Google's ID token to
  Firebase with `signInWithCredential`. The browser-tab flow
  (`signInWithProvider`) was tried first and failed on Android after the
  Google login with "missing initial state": Chrome's storage partitioning
  loses the state Firebase's web handler saved before the redirect.
- **The API verifies the token with firebase-admin** and then checks the
  token's email against `ALLOWED_EMAILS`. Firebase lets any Google account
  sign in to a project, so verification only says *who* is calling; the
  allowlist says whether they may. The email must be marked verified, and
  the comparison ignores case.
- **Guarded by default.** `require_user` is a dependency on the whole
  FastAPI app, and a route is public only if its path is in
  `api.auth.PUBLIC_PATHS` (today just `/healthz`). A test walks every
  route and fails if any other one answers without a token. The docs and
  `/openapi.json` URLs are switched off; the schema is still exported to
  `openapi/openapi.json` from `app.openapi()`.
- **401 vs 403.** No token, a malformed one or an expired one is 401 — the
  app should sign in again. A valid token for an account that is not on
  the allowlist is 403 — signing in again with the same account cannot
  fix it, so the app offers sign-out instead of retry.
- **Empty allowlist means nobody.** A deploy that forgot to set
  `ALLOWED_EMAILS` is locked, not open. The value is deployed from
  `functions/.env.fitness-75c22`, which is not committed.

An email allowlist rather than a user-ID one: the UID only exists after
the first sign-in, and the email is what the owner knows in advance.
Google does not reassign a Gmail address, so the two identify the same
person.

## Consequences

- The API is safe to expose without Cloudflare Access. The Cloudflare
  setup stays in front of the old stack until the cut-over (phase 8).
- Every request pays one token verification. firebase-admin caches
  Google's public keys, so this is a local signature check, not a network
  call.
- The Google OAuth callback (phase 3) cannot carry the header, so it will
  join `PUBLIC_PATHS` protected by a signed `state` instead.
- Local development runs against the Auth emulator, whose unsigned tokens
  firebase-admin accepts only when `FIREBASE_AUTH_EMULATOR_HOST` is set.
  The emulator sets that for the functions it runs; it must never be set
  on a deployed function.

## How we know it works

2026-09-25, against the emulators, with real emulator-issued ID tokens and
the real firebase-admin verification: `/healthz` without a token 200;
`/me` without a token 401; with a forged token 401; as a second Google
account 403; as the allowlisted account 200 with its UID and email.

Same day, deployed: `/me` without a token and with a forged one 401, and
a real Google sign-in as daniel.koeppl10@gmail.com on the Android 16
emulator answered 200 with that email.
