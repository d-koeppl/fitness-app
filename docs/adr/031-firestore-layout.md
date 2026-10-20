# ADR-031 — Firestore layout: month buckets for history, one document per record elsewhere

**Status:** Accepted · **Date:** 2026-09-25
**Amends:** in fitness-dashboard, ADR-002 (where rows live; the keep-the-raw-payload rule stands), ADR-012 and ADR-020 (how sessions and traces are stored)

Numbering: ADR-029 is Firebase Auth; ADR-030 is reserved for FCM
(phase 6), so this one is 031 as the port plan listed it.

## Context

Route C ([ADR-028](028-route-c-firebase.md)) replaces Postgres with
Firestore, and the free tier caps reads at 50,000 a day. The expensive
request is `/training/status`: the load model runs over the *whole*
history on every call (fitness-dashboard ADR-011), reading every daily
row and every "Training"/"Spiel:" calendar event there has ever been. One
document per row would make each call cost more every day, forever.

Measured on the production data (dump of 2026-09-25, 296 days since
2025-12-03):

| Data | Largest measured | Limit that matters |
| --- | --- | --- |
| A month of daily health rows, raw payload included | 283 KB | 1 MiB per document |
| A month of calendar events | 18 KB | 1 MiB |
| One heart-rate trace | 3,688 samples, 47 KB as JSON | 1 MiB; no arrays of arrays |
| One report, one chat message | ~2 KB | — |

## Decision

All reads and writes go through one module, `api/store/firestore.py`; no
service imports the Firestore client.

- **Month buckets for the two histories the model reads whole.**
  `health_months/<YYYY-MM>` holds `days.<date>`, and
  `calendar_months/<YYYY-MM>` (the event's local start month, or
  `undated`) holds `events.<id>`. A `/training/status` call is then about
  30 reads today and about 80 after three years, instead of one per row.
  A calendar event whose start moves to another month is moved out of its
  old bucket; `meta/calendar_index` remembers where each one is.
- **One document per record for everything else,** because it is small
  and read in narrow slices: `matches`, `hr_traces`, `skips`, `reports`,
  `drinks`, `conversations` (messages as a subcollection), `gemini_usage`
  per quota day, `oauth_tokens`.
- **No precomputed training document.** The port plan proposed one. With
  month buckets the reads stay flat without it, and a cached result would
  have to be invalidated by every sync, skip and scrape — a second place
  for the numbers to go wrong in, which is what fitness-dashboard ADR-011
  warned about.
- **Raw payloads and report insights are JSON text,** not Firestore maps:
  Firestore rejects an array directly inside an array, and Google's
  payloads are not ours to shape. The keep-everything rule of ADR-002
  still holds; the payload is simply stored as text.
- **Heart-rate samples are two parallel number arrays** (`offsets`,
  `bpm`) rather than packed bytes as the plan proposed: the largest trace
  is 47 KB, so packing would only make the data harder to read.
- **Dates are `YYYY-MM-DD` strings,** which sort and range-query
  correctly; timestamps are Firestore timestamps in UTC.
- **Integer ids, from `meta/counters`.** The API has always exposed them
  (`/coach/conversations/{id}`), and drink order ties are broken by id
  (ADR-019). The migration keeps the ids Postgres assigned.
- **Only single-field indexes,** which Firestore creates itself. Anything
  a single-field query cannot express is filtered in Python. The emulator
  does not enforce composite indexes, so a query that needed one would
  pass every test and fail in production. Fields no query reads — the
  month maps, trace arrays, report and message text — are exempted from
  indexing in `firestore.indexes.json`.

## Consequences

- Reads per request stay roughly flat as history grows, which keeps the
  free-tier estimate in the port plan honest. A month document is a
  quarter full at its largest; a day's raw payload would have to grow
  about four-fold before a month bucket needs splitting.
- SQL `ILIKE` patterns in settings (`CALENDAR_MATCH_TITLE=spiel:%`) are
  matched in Python by `api/store/like.py`, with the same meaning.
- Firestore cannot scan document ids in descending order, so month
  documents carry a `month` field to sort on. Found by the store tests.
- The fitness-dashboard database tests were ported by running them
  against a SQLAlchemy-shaped shim over the store (`tests/legacy_db.py`),
  with their assertions unchanged, on the Firestore emulator. CI runs
  them inside `firebase emulators:exec` and fails, rather than skips, if
  the emulator is missing.

## How we know it works

2026-09-25: 267 tests pass on the Firestore emulator — 19 store contract
tests; 99 pure-logic tests copied unchanged (training load, sessions,
Google Health parsing); 130 tests ported from fitness-dashboard's
test_api, test_drinks, test_heart_rate and test_matches (beer counter,
ÖFB gap check, heart rate, the ADR-015 coverage rules, skips, training
status, and the rule that asking for more history changes no number);
and 19 for the app wiring and auth.

Same day, on production data: the dump of 2026-09-25 was migrated into
the Firestore emulator with `tools/migrate/`, and the old API (restored
Postgres) and the new one (emulator) were asked the same 432 questions —
the training status with its whole per-day series (296 days), every daily
row, all 426 sessions and every stored heart-rate trace (28,281 samples),
two years of drink history, matches, the calendar and the latest report.
All 432 answered 200 on both sides, with **0 differences**, floats
compared exactly. Production configures no max heart rate, so zones are
never computed there; a second run with `HEALTH_MAX_HR_BPM=190` on both
sides (21 traces with derived zones, 62,759 seconds in zones) also came
out with 0 differences. See tools/migrate/README.md.
