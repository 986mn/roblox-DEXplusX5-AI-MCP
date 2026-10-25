#!/usr/bin/env bash
# Runs once when the container is created.
# Installs deps, compiles TypeScript, then sanity-checks the output.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER="$ROOT/server"

step() { printf '\n=== [%s] %s ===\n' "$1" "$2"; }

step 1/4 "Install Node dependencies"
cd "$SERVER"
if [ -f package-lock.json ]; then
  npm ci --no-audit --no-fund
else
  npm install --no-audit --no-fund
fi

step 2/4 "Compile TypeScript"
npx tsc

step 3/4 "Verify build artefacts"
for f in dist/index.js dist/http.js dist/queue.js dist/bridge.js; do
  if [ ! -f "$f" ]; then
    echo "MISSING: $f" >&2
    exit 1
  fi
  echo "  ok  $f"
done

step 4/4 "Verify bridge payloads"
if [ ! -f "$ROOT/lua/dex_mcp_poller.lua" ]; then
  echo "MISSING: lua/dex_mcp_poller.lua" >&2
  exit 1
fi
echo "  ok  lua/dex_mcp_poller.lua"

printf '\nSetup complete. The server starts automatically on container start.\n'
