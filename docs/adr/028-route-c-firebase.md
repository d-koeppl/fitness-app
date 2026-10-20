# ADR-028 — Route C: a Flutter client on Firebase, no home server

**Status:** Accepted · **Date:** 2026-09-24
**Supersedes:** in fitness-dashboard, ADR-001 (topology), ADR-002 (Postgres), ADR-004 (APScheduler and the wake trigger), ADR-007 (deployment)

Numbered on from fitness-dashboard, whose last ADR is 027, so the two
repos read as one decision history.

## Context

The dashboard was a Next.js PWA in front of FastAPI and Postgres, in
Docker on a Proxmox host at home. Three things pushed against that:

- A native app is the only way to read Health Connect or HealthKit on the
  phone, and the only route to Apple data at all
  (fitness-dashboard's `docs/PRODUCTIZATION.md` §3).
- A native app cannot do Cloudflare Access's browser-cookie login, which
  was the whole access gate (ADR-006).
- The home server was the one piece that needed looking after.

Three backend routes were weighed:

| Route | Backend | Home server | Code reused |
| --- | --- | --- | --- |
| A | FastAPI + Postgres at home, unchanged | Yes | All |
| B | Same FastAPI on Cloud Run + managed Postgres | No | Almost all |
| C | Firebase: Cloud Functions + Firestore + Auth + FCM + Hosting | No | Routers, schemas and maths; storage rewritten |

## Decision

Route C. One Flutter codebase for Android, iOS and the web, and a Firebase
backend, in one repository.

- **The FastAPI app runs inside one HTTPS Cloud Function** (`api`, Python
  3.13, europe-west1) through an ASGI-to-WSGI adapter, so routers, schemas
  and `/openapi.json` carry over. The client never reads Firestore;
  `firestore.rules` denies everything and the maths stays server-side.
- **Firestore** (`eur3`, standard edition) replaces Postgres. Its layout
  (month buckets, a precomputed training document, packed heart-rate
  traces) gets its own ADR when phase 2 designs it.
- **One scheduled function** replaces the five APScheduler jobs.
- **The Home Assistant wake trigger is dropped.** The morning report comes
  only from the in-app report button (ADR-027's sync-then-generate flow).
- **Blaze plan**, sized to stay inside its no-cost quotas for one user,
  with a €1 budget alert.

## Consequences

- No server to maintain, and a plausible €0 monthly bill — but only while
  the design respects the quotas: reads that stay flat as history grows,
  min instances 0 (so 2–5 s Python cold starts), at most three Cloud
  Scheduler jobs per billing account, and an Artifact Registry cleanup
  policy (set to 1 day on europe-west1).
- Postgres → Firestore is a redesign, not a driver swap. The numbers the
  old ADRs call load-bearing (training load, Form, zone times, the beer
  counter's claims) must be diffed against the old stack for every day
  before cut-over.
- Access control moves from the network to Firebase ID tokens (its own
  ADR, phase 1); push moves from Web Push to FCM (its own ADR, phase 6).
- Vendor lock-in to Firebase is accepted for a single-user app.

## How we know the adapter works

Phase 0, 2026-09-24. The first deploy built `ASGIMiddleware` at import time
and every production request hung until the 60 s timeout, while the
emulator answered instantly: the deployed server imports the module and
then forks its workers, and the adapter's event-loop thread does not
survive the fork. Building it on the first request fixed it — `/healthz`
now answers in about 0.15 s warm. `tests/test_app.py` guards the import
side of that.
