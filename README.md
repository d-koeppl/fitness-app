# fitness-app

A personal fitness dashboard: training load, recovery, sleep, matches and an
AI coach, for Android, iOS and the browser. One Flutter codebase, with a
Firebase backend (Cloud Functions in Python, Firestore, Auth, FCM, Hosting).

Single user by design. Successor to
[fitness-dashboard](https://github.com/d-koeppl/fitness-dashboard); the port
is in progress.

| Path | What |
| --- | --- |
| `app/` | Flutter app (`cc.koeppl.fitness`) |
| `functions/` | Python Cloud Functions: the FastAPI app behind `api` |
| `openapi/` | API schema snapshot the Dart client is generated from |
| `firestore.rules` | Deny-all: only the functions touch Firestore |
| `docs/adr/` | Decision records |

Setup, checks and conventions: [CLAUDE.md](CLAUDE.md).
