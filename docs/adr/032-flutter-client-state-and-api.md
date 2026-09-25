# ADR-032 — The Flutter client: Riverpod for state, a Dart client generated from the schema

**Status:** Accepted · **Date:** 2026-09-25
**Carries over:** in fitness-dashboard, the web client's shape
(`web/lib/api.ts`, `web/hooks/useDashboardData.ts`, `web/lib/format.ts`),
not a decision record of its own there.

## Context

Phase 4 of the port builds the dashboard's read-only screens in Flutter.
The web app did three things by hand that now need a Dart home:

- **Talking to the API.** `web/lib/api.ts` held about thirty hand-written
  types and fetch helpers. Each one could drift from the Python schemas
  unnoticed, and did twice (a field renamed server-side kept rendering as
  `undefined`).
- **Loading and refreshing.** `useDashboardData` fired ten requests in
  parallel, let each fail on its own, re-read every five minutes, and
  applied the report as soon as it landed.
- **Formatting.** `web/lib/format.ts` and `key-metrics.ts` decide how every
  number on screen reads, with 70-odd tests.

## Decision

- **The Dart client is generated** from `openapi/openapi.json` by
  openapi-generator's `dart-dio` generator with `json_serializable`, pinned
  in `openapitools.json` (generator 7.14.0) and run by
  `tool/generate_api_client.sh` into `app/packages/fitness_api`. The
  output is committed; CI regenerates it and fails on any difference, the
  same way a test already fails when `openapi.json` falls behind the
  routes. Two adjustments make it work:
  - operation ids are the handler's name in camelCase (`api/main.py`),
    so the Dart methods are `listDailyHealth`, not
    `list_daily_health_health_data_daily_get`, and do not change when a
    path does;
  - FastAPI's 422 body types `loc` as "string or integer", which the
    generator turns into a class that does not compile. The script feeds
    it a copy of the schema with that one field untyped. The app never
    reads a 422's location.
- **Riverpod** (`flutter_riverpod`, no code generation) holds the state.
  `dashboardProvider` is the port of `useDashboardData`: the same ten
  requests, each settled on its own, the report applied early, a re-read
  every five minutes and on a range change, and none of it syncing Google
  (that stays the header chip's job, ADR-026 in fitness-dashboard). A 403
  from any source puts the whole shell on "not allowed", a 401 on "sign in
  again" (ADR-029).
- **`lib/domain/` ports `format.ts` and `key-metrics.ts` with their
  tests**, case for case. Dates and numbers are written out by hand rather
  than with `intl`, because what has to match is Chrome's en-GB output
  ("Sept", "12,480") and Math.round's halves-up rounding (`jsRound`), not
  a locale library's idea of them. Colours stay out of `domain/`: a metric
  names a palette role, and `lib/ui/theme/palette.dart` resolves it, with
  the web's colour-mix tokens ported one line each.

## Consequences

- A schema change is three steps: change the route, run
  `python -m tools.export_openapi`, run `tool/generate_api_client.sh`. CI
  names whichever was skipped.
- The generator needs Java and Node, both already in CI for the Firebase
  emulators. Locally they are the JDK Android Studio uses and the Node the
  Firebase CLI runs on.
- The generated models type date-only fields as `DateTime` at local
  midnight, and a few (`series[].date`) as strings; `parseDay` covers the
  latter. Timestamps arrive in UTC and are shown with `toLocal()`.
- Not ported yet: KaTeX and Mermaid in report text (they render as source
  until phase 7). The writes arrived in phase 5 (ADR-033).

## How we know it works

2026-09-25, the debug build on the Android emulator against production
(signed in as the allowlisted account): every number on Today, Fitness
(training status, sessions, matches) and Health matched
https://fitness.koeppl.cc for the same day. The one difference was
today's steps, because the new hourly sync had run six minutes after the
web page was read. 102 Flutter tests pass: 92 ported domain cases and the
dashboard against a fake API, including the 401, 403, a failing source and
no report yet.
