# Postgres → Firestore migration

Moves the fitness-dashboard data into the Firestore layout of
[ADR-031](../../docs/adr/031-firestore-layout.md), and proves nothing
changed on the way by asking the old and the new API the same questions.

Run it as a dry run against the emulator first, and against production
only at the cut-over (phase 8), from a fresh dump.

All dumps and snapshots go in `C:\Coding\fitness\dumps\` — outside both
repositories. They hold the whole health history and the encrypted OAuth
refresh tokens.

## 1. Dump production (read-only)

```bash
ssh root@<proxmox-host> "pct exec 110 -- bash -lc 'cd /root/fitness-dashboard && docker compose exec -T db pg_dump -U fitness fitness | gzip'" > dumps/prod-YYYY-MM-DD.sql.gz
```

Restore it into a separate local database, never over the local dev one:

```bash
docker exec fitness-dashboard-db-1 psql -U fitness -d postgres -c "CREATE DATABASE fitness_prod;"
gunzip -c dumps/prod-YYYY-MM-DD.sql.gz | docker exec -i fitness-dashboard-db-1 psql -q -U fitness -d fitness_prod
```

## 2. Export to JSON

```bash
python tools/migrate/export_postgres.py dumps/prod-YYYY-MM-DD-json \
    --psql "docker exec -i fitness-dashboard-db-1 psql -U fitness -d fitness_prod"
```

## 3. Import

Into the emulator:

```bash
firebase emulators:start --only firestore --project demo-fitness-migration
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 python tools/migrate/import_firestore.py dumps/prod-YYYY-MM-DD-json --project demo-fitness-migration
```

Into production, at the cut-over only, into an empty database:

```bash
python tools/migrate/import_firestore.py dumps/prod-YYYY-MM-DD-json --project fitness-75c22 --production
```

Idempotent: a second run leaves the same state.

## 4. Compare the old and the new API

The old API is fitness-dashboard at `origin/main`, run in-process without
its scheduler, from a virtualenv with its own `api/requirements.txt`. Set
the same non-secret settings on both sides (production uses the code
defaults, except that the old repo's local `.env` may pin
`WAKE_FALLBACK_HOUR`; set it to 18). Run both within the same minute.

```bash
DATABASE_URL=postgresql+psycopg2://fitness:<pw>@localhost:5433/fitness_prod WAKE_FALLBACK_HOUR=18 \
    <old-venv>/python tools/migrate/snapshot_api.py old <fitness-dashboard checkout> dumps/snapshot-old.json
FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 \
    functions/venv/Scripts/python tools/migrate/snapshot_api.py new functions dumps/snapshot-new.json --project demo-fitness-migration
functions/venv/Scripts/python tools/migrate/compare_snapshots.py dumps/snapshot-old.json dumps/snapshot-new.json
```

`compare_snapshots.py` exits non-zero on any difference, floats compared
exactly. Check the status-code line each snapshot prints: two runs that
failed identically also compare as "no differences".

Production has no max heart rate configured, so no heart-rate zones are
computed on either side. Run steps 4 a second time with
`HEALTH_MAX_HR_BPM=190` set for both snapshots, so the zone arithmetic is
compared too.

## Results

| Date | Data | Requests | Differences |
| --- | --- | --- | --- |
| 2026-09-25 | dump of 2026-09-25: 296 days, 426 sessions (28,281 heart-rate samples), 30 beers, 45 reports | 432, all 200 | 0 |
| 2026-09-25 | same, `HEALTH_MAX_HR_BPM=190` (21 traces with derived zones, 62,759 s in zones) | 432, all 200 | 0 |
