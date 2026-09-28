---
name: run-app
description: Launch the fitness app headless in a cloud session — Auth/Functions/Firestore emulators, made-up demo data, the Flutter web build — and drive it in Chromium to take screenshots. Use when asked to run, start or screenshot the app, or to check a change in the real UI rather than only in tests.
---

# Run the app and screenshot it

Headless version of CLAUDE.md's "Running locally", for Claude Code on the
web. The session-start hook (`.claude/hooks/session-start.sh`) has already
installed Flutter, firebase-tools and `functions/venv`; these scripts need
nothing else.

## Start

```bash
.claude/skills/run-app/scripts/start.sh             # about 1 min, mostly the web build
.claude/skills/run-app/scripts/start.sh --no-build  # reuse app/build/web
```

It stops anything an earlier run left, then:

1. Creates `functions/.env.local` (`ALLOWED_EMAILS=["demo@example.com"]`) and
   `functions/.secret.local` (dummy secrets, a fresh Fernet key) if missing.
   Both are gitignored. Never put real secrets there: this setup is
   emulator-only.
2. Starts the Auth, Functions and Firestore emulators as project
   `fitness-75c22` (the id the API base URL carries).
3. Builds the web app against the emulators, with `--no-web-resources-cdn`.
4. Serves it on http://127.0.0.1:5050.
5. Seeds the emulator with `scripts/seed_demo.py`: 91 days of health data,
   Tuesday/Thursday "Training" and alternate-Saturday "Spiel:" calendar
   events, and one demo report. All made up; nothing real is involved.
   There are no Google tokens and no watch-tracked sessions (`raw` is
   empty), so the "Connect Google Health" banners and an empty Sessions
   list are expected; the training load comes from the calendar estimates.

Logs: `build/run-app/{emulators,build,serve}.log`.

The functions emulator reloads Python on change, so an API change needs no
restart. A Dart change needs `start.sh` again (it rebuilds). Re-running
the seeder resets the seeded documents.

## Drive

```bash
NODE_USE_ENV_PROXY=1 node .claude/skills/run-app/scripts/drive.mjs                       # desktop 1280x800
NODE_USE_ENV_PROXY=1 node .claude/skills/run-app/scripts/drive.mjs --size 412x915        # phone
NODE_USE_ENV_PROXY=1 node .claude/skills/run-app/scripts/drive.mjs --steps /path/steps.mjs
```

It signs in through the Auth emulator's Google popup as `demo@example.com`
(`--email` to change; any address not in `ALLOWED_EMAILS` shows the
"not allowed" gate), then screenshots sign-in, Today, Fitness, Health and
Coach to `build/run-app/shots/<tag>-<name>.png`. **Look at every
screenshot** before reporting: a blank frame means the app did not start.
Then send them to the user with SendUserFile.

To check a specific change, write a steps module (outside the repo, e.g.
in the scratchpad) and pass it with `--steps`. It runs after sign-in in
place of the tour:

```js
export default async ({ page, shot, nav }) => {
  await page.mouse.click(...nav.fitness);       // nav: today, fitness, health, coach
  await page.getByRole('button', { name: 'Sessions', exact: true }).click();
  await shot('fitness-sessions');
};
```

Flutter draws on a canvas. `drive.mjs` switches on its semantics tree, so
`getByRole` finds controls. Nearly every control, including the Fitness
sub-sections (Training, Sessions, Upcoming, Matches), is a `button` named
by its text, not a `tab`. To see what a screen exposes, dump it from a
steps module:
`console.log(await page.$$eval('flt-semantics[role]', els => els.map(e => e.getAttribute('role') + ' ' + e.textContent.trim())))`. Where Flutter's semantics
overlay intercepts a click, use `{ force: true }` or click a position with
`page.mouse.click(x, y)`. Nav items are positions (`nav`), because the phone
bar has no labels.

The console reports page errors, failed API calls (`api 4xx/5xx …`) and
external fetch failures. Check them as well as the pictures.

## Stop

```bash
.claude/skills/run-app/scripts/stop.sh
```

## Gotchas already handled — don't rediscover them

- **No locale → blank page.** Headless Chromium here has no system
  locale and the app dies at start with "Incorrect locale information
  provided". `drive.mjs` sets `en-GB` / `Europe/Vienna`.
- **Google CDNs.** Chromium's own fetches from gstatic (CanvasKit, the
  Firebase JS SDK, Roboto) fail intermittently with
  `ERR_TOO_MANY_RETRIES`. CanvasKit is bundled at build time. Every other
  external request is fetched by Node through the session proxy
  (`NODE_USE_ENV_PROXY=1`) and cached in `build/run-app/cdn-cache/`. Do
  not pass Playwright a `proxy`: Chromium then sends plain-HTTP requests
  the proxy rejects with 405.
- **`accounts.google.com` is blocked** by the network policy (403). The
  emulator sign-in does not use it; ignore that error.
- **Auto-generate overwrites the email** in the emulator popup, so the
  email is typed after clicking it.
- **Android cannot run here**: no SDK, no emulator. This skill covers
  the web build only.
