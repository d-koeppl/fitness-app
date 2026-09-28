#!/bin/bash
# Stops what start.sh started, by port: the web server, then the emulators.
set -uo pipefail

for port in 5050 4000 4400 4500 5001 8080 9099 9150; do
  pids=$(lsof -ti:"$port" -sTCP:LISTEN 2>/dev/null || true)
  [ -n "$pids" ] && kill $pids 2>/dev/null
done
# The emulators take a moment to release their ports.
timeout 20 bash -c 'while lsof -ti:5001,8080,9099,5050 -sTCP:LISTEN >/dev/null 2>&1; do sleep 1; done' || true
exit 0
