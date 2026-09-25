# ADR-035 — The coach on Firebase: charts instead of Mermaid, safe resends

**Status:** Accepted · **Date:** 2026-09-25
**Carries over:** fitness-dashboard ADR-010 (the server builds the prompt),
ADR-013 (the shared Gemini budget), ADR-017 (stored conversations) and
ADR-021 (pinned workouts), unchanged.

## Context

Phase 7 ports the Coach tab. The server side moves nearly intact: the
prompt assembly (`api/analysis/coach.py`), the pinned-workout payload
(`api/services/session_context.py`) and the conversation service, now on
the store's `conversations/<id>/messages` layout (ADR-031). Three things
did not carry over as they were.

1. **Mermaid.** The web coach drew ```mermaid blocks in the browser.
   Flutter has no Mermaid renderer; a WebView would not run in the web
   build, and would look like no other chart in the app. In the production
   data the coach had written 3 replies, 1 of them with a diagram (an
   `xychart-beta` trend).
2. **A lost reply.** A coach message is one Gemini request, and on a phone
   the answer can take long enough for the connection to drop while the
   function is still working. Resending then asked Gemini a second time
   and stored the question twice.
3. **No count query.** Postgres counted a chat's messages with a join;
   Firestore would need a read per message.

## Decision

- **Charts, not diagrams.** The prompt asks for a fenced ```chart block
  holding one JSON object — `type` (line, bar or pie), `title`, `unit`,
  `x` labels and up to four `series` of numbers or nulls on one axis —
  and nothing else to draw. The app parses it strictly
  (`app/lib/domain/coach_chart.dart`) and draws line and bar charts with
  the detail sheets' `MetricChart`, so a chart in a reply reads like every
  other chart: one labelled y-axis, gaps for missing days. A block that
  does not parse is shown as its source with the reason. Mermaid blocks in
  chats from the web app show as source under a line saying so.
- **Math** is rendered with `flutter_math_fork`, as KaTeX did on the web.
- **A message has an id of its own.** `POST /coach/chat` takes an optional
  `client_message_id`; the app always sends one. The server claims it in a
  transaction before asking Gemini (`chat_requests/<id>`, status
  `pending`), and writes the turn and the record (`done`, with the ids)
  in one batch. The same id again returns the stored turn and spends
  nothing, so it is answered even on a spent day; while the first copy is
  still being answered it is a 409. A failed answer drops the claim, and a
  claim older than the function's timeout (`COACH_REQUEST_STALE_SECONDS`,
  330 s) is taken over. The app resends under the same id after a timeout,
  a dropped connection or a 409, backing off over about two minutes.
  Deleting a chat deletes its records.
- **The count is stored.** A turn writes the conversation (`updated_at`,
  `message_count`), both messages and the resend record in one batch, so
  the picker reads one document per chat and the count cannot drift from
  the messages.
- **The History choices are one enum**, `CoachLookbackDays`, in the schema
  and so in the generated Dart client. The app labels it with an
  exhaustive switch and tests its include switches against `IncludeFlags`,
  so a new option on the server fails the app's build or tests until it
  has a label.

## Verification

`tools/migrate/snapshot_coach_prompt.py` builds the coach's context on the
old and the new stack from the same production dump — each include switch
off, each History choice, pinned workouts with and without a trace, a
match, a missing id, several at once, and the history window of every
stored chat — and `compare_snapshots.py` diffs them. The first run found
whole-number floats read back as ints (`"weight_kg": 79` for `79.0`),
which the migration's JSON export had written; the store now coerces the
float fields on read and write. After that: 0 differences in 22 cases,
with and without a configured max heart rate.

## Consequences

- A diagram the coach used to draw as a flowchart ("train or rest?") is
  now a short list; trends and breakdowns are charts.
- One small document per coach message (`chat_requests`), kept until its
  chat is deleted. A few a day.
- The app's resends can make one message take up to about two minutes to
  fail when the network is gone, in exchange for never paying twice for
  one answer.
- The generator's spec copy (`tool/generate_api_client.sh`) now turns an
  optional `X | None` field into plain `X`, which dart-dio could not
  generate; a null and an absent field mean the same to the server.
