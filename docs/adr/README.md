# Architecture decision records

Why each decision was made, one record per decision. The numbering
continues from fitness-dashboard, this app's predecessor (Next.js +
FastAPI + Postgres on a home server), whose records run from ADR-001 to
ADR-027. That repository is private; where a record here supersedes,
amends or carries over one of its decisions, it names that record and
says what it decided. When a decision turns out wrong, a new record
supersedes it; the old one is not edited.

| ADR | Decision |
| --- | --- |
| [028](028-route-c-firebase.md) | Route C: a Flutter client on Firebase, no home server |
| [029](029-firebase-auth-access-gate.md) | Firebase ID tokens and an email allowlist as the access gate |
| [030](030-fcm-report-push.md) | The report push through Firebase Cloud Messaging |
| [031](031-firestore-layout.md) | Firestore layout: month buckets for history, one document per record elsewhere |
| [032](032-flutter-client-state-and-api.md) | The Flutter client: Riverpod for state, a Dart client generated from the schema |
| [033](033-detail-sheets-writes-and-reports.md) | Detail sheets on fl_chart, the writes, and reports on Firebase |
| [034](034-evening-report-last-try.md) | The evening report tries again at 19:30, then on the fallback model |
| [035](035-coach-on-firebase.md) | The coach on Firebase: charts instead of Mermaid, safe resends |
| [036](036-web-load-performance.md) | The browser build: WebAssembly, a loading screen, KaTeX fonts on first use |
| [037](037-crawling-allowed.md) | Crawling allowed; `/.well-known/` not rewritten to the app |
| [038](038-document-isolation-policy.md) | Cross-origin isolation through `Document-Isolation-Policy` |
| [039](039-recorded-max-heart-rate.md) | The zones' max heart rate is the highest one recorded |
| [040](040-league-table.md) | The league table, and opponents rated on points per game |
