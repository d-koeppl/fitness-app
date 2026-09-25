#!/usr/bin/env bash
# Regenerates app/packages/fitness_api from openapi/openapi.json.
#
# Run it after `python -m tools.export_openapi` whenever a route or a schema
# changes. CI runs it too and fails if the committed client differs, so the
# Dart models cannot drift from the API. Needs Java 11+ and Node (the
# generator is a jar that openapi-generator-cli fetches, pinned in
# openapitools.json), and the Dart SDK.
set -euo pipefail
cd "$(dirname "$0")/.."

# FastAPI's 422 body types each `loc` entry as "string or integer", which
# dart-dio turns into a class that does not compile. The app never reads a
# 422's location, so the generator is given a copy where it is untyped.
mkdir -p build
node -e '
  const fs = require("fs");
  const spec = JSON.parse(fs.readFileSync("openapi/openapi.json", "utf8"));
  const loc = spec.components?.schemas?.ValidationError?.properties?.loc;
  if (loc) loc.items = {};
  fs.writeFileSync("build/openapi-for-dart.json", JSON.stringify(spec, null, 2));
'

npx -y @openapitools/openapi-generator-cli@2.41.0 generate --generator-key fitness_api >/dev/null
cd app/packages/fitness_api
dart pub get >/dev/null
dart run build_runner build >/dev/null
dart format lib >/dev/null
