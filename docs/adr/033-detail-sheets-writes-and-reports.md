# ADR-033 — Detail sheets on fl_chart, the writes, and reports on Firebase

**Status:** Accepted · **Date:** 2026-09-25
**Carries over:** in fitness-dashboard, ADR-013 (the Gemini budget),
ADR-019 and ADR-023/024 (the beer counter and earlier days), ADR-025 (the
rolling model alias) and ADR-027 (one New report button).

## Context

Phase 5 of the port. The read-only app of phase 4 gains the four detail
sheets (a metric, training load, beer, one session), every write the web
app had (the beer stepper, earlier days, marking a session skipped, New
report), and the 18:00 fallback report. The last two need the Gemini
pipeline, which had not moved to Firebase yet.

## Decision

- **Charts are fl_chart.** A sheet's chart is a `BarChart` with a
  `LineChart` laid over it on the same y-range and the same reserved
  gutters, because fl_chart draws bars and lines in different charts:
  bars spaced around their slots and the line running from -0.5 to n-0.5
  put point i at the centre of bar i in both. The y-axis, the buckets and
  the tick labels are `domain/series.dart`, a port of `series.ts` with its
  tests, so the scale is the web's (`niceScale`, never a step the labels
  cannot show). The crosshair and the pointer handling are the widget's
  own. The session heart-rate trace is one `LineChart` of zone-coloured
  segments.
- **Writes follow the web's rules.** The stepper moves the number at once
  and only the last reply still in flight may replace it; a failed tap
  takes back its own step. Earlier days are corrected in the beer sheet,
  never below what a report counted. Sync and Gemini requests get a
  five-minute receive timeout (`api/slow_requests.dart`); every other
  request keeps 20 s.
- **The Gemini pipeline moves over with its prompt unchanged (v5)**:
  `analysis/gemini.py`, the model picker and the shared budget, now on the
  Firestore store. A report and the drinks it claims are written in one
  Firestore batch (`put_report(..., claim_drink_ids=...)`), as they were
  one Postgres transaction.
- **The fallback report runs in the hourly job at 18:30**, after that
  hour's sync, when the day has no report yet. The old scheduler ran it at
  18:00 on whatever the last sync had left; one Cloud Scheduler job is all
  the free tier needs (ADR-028). Its push arrives in phase 6.
- **"Ask the coach about this session"** waits for the coach, phase 7.

## Consequences

- `GEMINI_API_KEY` is a fourth Secret Manager secret, declared by both
  functions; a deploy fails until it exists. The emulator reads it from
  `functions/.secret.local`, which must hold a non-empty value or the
  emulator asks Secret Manager on every request.
- The api function's timeout is 300 s, for the Gemini wait.
- The generated client puts path parameters into the URL unescaped and
  writes a `DateTime` with `toString()`. The API accepts
  "2026-09-24 00:00:00.000" as a date; a session id ("…#0") has to be
  escaped by the caller.

## How we know it works

2026-09-25:

- 413 backend tests on the Firestore emulator, among them the ported
  Gemini context, retry, budget and fallback tests, and a run that claims
  the counter on the day's first report and not on its second.
- 175 Flutter tests, 43 of them the ported series cases, and widget tests
  for each write against a fake API.
- The generated client over real HTTP against the emulators, seeded from
  the production dump: the stepper, an earlier day (and the refusal below
  a report's count), a skip moving a day's load from 164.1 to 0 and back,
  a heart-rate trace, and a bad Gemini key coming back as a 502. This
  found two bugs, both fixed with a regression test: every request with a
  JSON body hung in `main.py` (the server had already drained the socket
  a2wsgi read), and the unescaped "#" in a session id.
- On the Android emulator against production, the resting-HR sheet
  matched the web app's in all four periods, row for row, and the
  training-load sheet matched its readout and history.
