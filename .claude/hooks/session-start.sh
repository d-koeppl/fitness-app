#!/bin/bash
# Installs what CI uses (.github/workflows/ci.yml) so a Claude Code on the
# web session can run the checks in CLAUDE.md, the emulators and a web
# build: Flutter, firebase-tools and the Firestore emulator, and the
# functions virtualenv. Every step skips work already done, so a cached
# container starts fast.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

# Keep these in step with ci.yml.
FLUTTER_VERSION="3.47.5"
FIREBASE_TOOLS_VERSION="15.31.0"

REPO="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"
FLUTTER_HOME="$HOME/flutter"
NODE_HOME="/opt/node22"
JAVA_HOME="${JAVA_HOME:-/usr/lib/jvm/java-21-openjdk-amd64}"
NPM_PREFIX="$HOME/.npm-global"

export JAVA_HOME
export PATH="$FLUTTER_HOME/bin:$NODE_HOME/bin:$NPM_PREFIX/bin:$JAVA_HOME/bin:$PATH"

# Flutter, pinned to CI's version.
git config --global --add safe.directory "$FLUTTER_HOME" 2>/dev/null || true
if [ "$(git -C "$FLUTTER_HOME" describe --tags --exact-match 2>/dev/null || true)" != "$FLUTTER_VERSION" ]; then
  rm -rf "$FLUTTER_HOME"
  git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$FLUTTER_VERSION" \
    https://github.com/flutter/flutter.git "$FLUTTER_HOME"
fi
flutter config --no-analytics >/dev/null 2>&1 || true
flutter --version >/dev/null
flutter precache --web >/dev/null

# firebase-tools, and the Firestore emulator jar it would otherwise fetch on
# first use.
if [ "$(firebase --version 2>/dev/null || true)" != "$FIREBASE_TOOLS_VERSION" ]; then
  npm install -g --prefix "$NPM_PREFIX" --silent "firebase-tools@$FIREBASE_TOOLS_VERSION"
fi
firebase setup:emulators:firestore >/dev/null 2>&1 || true

# functions/venv on Python 3.13, the deployed runtime. Firebase looks for
# the virtualenv at exactly this path; on Linux it has bin/, not Scripts/.
if [ ! -x "$REPO/functions/venv/bin/python" ]; then
  python3.13 -m venv "$REPO/functions/venv"
fi
"$REPO/functions/venv/bin/pip" install --quiet --disable-pip-version-check \
  -r "$REPO/functions/requirements-dev.txt"

(cd "$REPO/app" && flutter pub get >/dev/null)

if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  {
    echo "export JAVA_HOME=\"$JAVA_HOME\""
    echo "export PATH=\"$FLUTTER_HOME/bin:$NODE_HOME/bin:$NPM_PREFIX/bin:$JAVA_HOME/bin:\$PATH\""
  } >> "$CLAUDE_ENV_FILE"
fi
