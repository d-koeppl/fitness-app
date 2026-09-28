#!/bin/bash
# Starts the app the way CLAUDE.md's "Running locally" does, headless: the
# Auth, Functions and Firestore emulators, demo data, and the web build
# served on :5050. Safe to re-run; it stops what an earlier run started.
#
#   start.sh              everything
#   start.sh --no-build   reuse app/build/web (the API or the data changed,
#                         the Dart did not)
set -euo pipefail

REPO="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$REPO/build/run-app"
PROJECT="fitness-75c22"
API="http://127.0.0.1:5001/$PROJECT/europe-west1/api"

export JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-21-openjdk-amd64}"
export PATH="$HOME/flutter/bin:/opt/node22/bin:$HOME/.npm-global/bin:$JAVA_HOME/bin:$PATH"
mkdir -p "$OUT"

build=1
[ "${1:-}" = "--no-build" ] && build=0

"$HERE/stop.sh"

# Emulator-only config. Both files are gitignored (*.local) and never hold
# a real secret: the emulator trusts only Auth-emulator tokens, and New
# report answers 502 with the dummy Gemini key.
if [ ! -f "$REPO/functions/.env.local" ]; then
  sed -e 's|^ALLOWED_EMAILS=.*|ALLOWED_EMAILS=["demo@example.com"]|' \
      -e "s|^GOOGLE_REDIRECT_URI=.*|GOOGLE_REDIRECT_URI=$API/oauth/google/callback|" \
      "$REPO/functions/.env.example" > "$REPO/functions/.env.local"
fi
if [ ! -f "$REPO/functions/.secret.local" ]; then
  key=$("$REPO/functions/venv/bin/python" -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())")
  printf 'TOKEN_ENCRYPTION_KEY=%s\nGOOGLE_CLIENT_ID=dummy\nGOOGLE_CLIENT_SECRET=dummy\nGEMINI_API_KEY=dummy\n' "$key" \
    > "$REPO/functions/.secret.local"
fi

# The redirects sit outside the subshell so nothing background keeps the
# caller's stdout open (a caller piping into `tail` would wait forever).
(cd "$REPO" && exec firebase emulators:start --only auth,functions,firestore --project "$PROJECT") \
  < /dev/null > "$OUT/emulators.log" 2>&1 &

if [ "$build" = 1 ] || [ ! -f "$REPO/app/build/web/index.html" ]; then
  # --no-web-resources-cdn bundles CanvasKit: Chromium's own fetches from
  # gstatic fail intermittently in the cloud container.
  (cd "$REPO/app" && flutter build web --release --no-web-resources-cdn \
    --dart-define=API_BASE_URL="$API" --dart-define=AUTH_EMULATOR_HOST=127.0.0.1 \
    > "$OUT/build.log" 2>&1) || { tail -20 "$OUT/build.log"; exit 1; }
fi

node /opt/node22/lib/node_modules/serve/build/main.js -s -l 5050 "$REPO/app/build/web" \
  < /dev/null > "$OUT/serve.log" 2>&1 &

timeout 180 bash -c "until grep -q 'All emulators ready' '$OUT/emulators.log'; do
  grep -q 'Error:' '$OUT/emulators.log' && exit 1; sleep 1; done" \
  || { tail -30 "$OUT/emulators.log"; exit 1; }
timeout 30 bash -c 'until curl -sf http://127.0.0.1:5050 >/dev/null; do sleep 1; done'

FIRESTORE_EMULATOR_HOST=127.0.0.1:8080 timeout 60 "$REPO/functions/venv/bin/python" "$HERE/seed_demo.py" "$PROJECT"

echo "ready: app http://127.0.0.1:5050  api $API  emulator UI http://127.0.0.1:4000"
echo "logs:  $OUT/{emulators,build,serve}.log"
