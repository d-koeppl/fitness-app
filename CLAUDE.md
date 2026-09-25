# Working on this repo

The Flutter client and its Firebase backend, in one repo. It replaces
`d-koeppl/fitness-dashboard` (Next.js + FastAPI + Postgres on a home
server); that repo stays as read-only history and as the running
reference until the cut-over. Why: [ADR-028](docs/adr/028-route-c-firebase.md).

## Branching

Never commit or push directly to `main`. Work on a `feature/…` or `fix/…`
branch and open a pull request.

## Checks

CI runs all of these on every pull request
([.github/workflows/ci.yml](.github/workflows/ci.yml)); run them locally
before pushing:

```bash
cd functions && venv/Scripts/python -m ruff check . && venv/Scripts/python -m pytest
cd app && flutter analyze && flutter test
```

The store tests need the Firestore emulator and skip without it. To run
everything, as CI does:

```bash
firebase emulators:exec --only firestore --project demo-fitness-test "cd functions && venv/Scripts/python -m pytest"
```

Set up `functions/venv` once with Python 3.13 (the deployed runtime):
`py -3.13 -m venv functions/venv` then
`functions/venv/Scripts/pip install -r functions/requirements-dev.txt`.
Firebase looks for the virtualenv at exactly that path.

## Where things go

- **`functions/api/`** is the FastAPI app, carried over from the old
  backend. Routers parse and delegate; queries go in `api/services/`,
  models in `api/schemas/`. Every endpoint declares a response model and a
  stable `operation_id`, because the Dart client is generated from the
  schema.
- **Settings** belong in `functions/api/config.py`. No `os.getenv`
  anywhere else.
- **`functions/main.py`** only adapts the ASGI app to a Cloud Function.
  The adapter must be built lazily — see the comment there before
  touching it.
- **`openapi/openapi.json`** is a snapshot. After changing a route, run
  `python -m tools.export_openapi` from `functions/`; a test fails until
  you do.
- **Firestore** is reached only by the functions, and inside them only by
  `functions/api/store/firestore.py` ([ADR-031](docs/adr/031-firestore-layout.md)).
  Services call its methods; none imports the Firestore client.
  `firestore.rules` denies all client access; keep it that way.
- **Queries use single-field indexes only.** The emulator does not enforce
  composite indexes, so a query that needs one passes every test and
  fails in production. Filter further in Python instead.
- **`functions/api/analysis/training_load.py` is pure** and has no I/O, as
  in fitness-dashboard. It is where a wrong number stays invisible longest.
- **Flutter app** (`app/lib/`): `api/` client code, `domain/` pure logic
  ported from `web/lib/` with its tests, `data/` state, `ui/` widgets.

## Running locally

```bash
firebase emulators:start --only auth,functions,firestore
cd app && flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:5001/fitness-75c22/europe-west1/api --dart-define=AUTH_EMULATOR_HOST=127.0.0.1
```

The emulated API reads `functions/.env.local` (copy `functions/.env.example`)
and only trusts Auth-emulator tokens; the deployed one reads
`functions/.env.fitness-75c22` and only trusts real ones. Point both
dart-defines at the emulators or neither.

## Auth

Every API route requires a Firebase ID token whose email is in
`ALLOWED_EMAILS`, unless its path is in `api.auth.PUBLIC_PATHS`
([ADR-029](docs/adr/029-firebase-auth-access-gate.md)). Adding to that set
is a security decision, not a convenience.

## Documentation

- [docs/adr/](docs/adr/) — why each decision was made. Numbering
  continues from the fitness-dashboard ADRs (last there: 027). When a
  decision turns out wrong, add a superseding ADR rather than editing the
  old one.
- The port plan (phases, free-tier budget) is a shared doc:
  https://claude.ai/code/artifact/b439e7c3-4caf-4c99-aa69-205966b2d822
