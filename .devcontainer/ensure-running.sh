#!/usr/bin/env bash
# Self-healing probe. Safe to run any time.
#   --status   report only, exit 0 if healthy
#   --quiet    suppress success banner
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER="$ROOT/server"
LOG="$SERVER/.server.log"
PORT=16384
PROBE="http://127.0.0.1:${PORT}/api/status"
MODE="${1:-}"

alive() { curl -fsS --max-time 3 "$PROBE" >/dev/null 2>&1; }

if alive; then
  [ "$MODE" = "--quiet" ] || echo "[ensure] running"
  [ "$MODE" = "--status" ] && exit 0
  exit 0
fi

if [ "$MODE" = "--status" ]; then
  echo "[ensure] DOWN"
  exit 1
fi

echo "[ensure] not responding, restarting"
cd "$SERVER" || exit 1

if [ ! -f dist/index.js ]; then
  echo "[ensure] dist missing, rebuilding"
  npm install --no-audit --no-fund >/dev/null 2>&1 || true
  npx tsc || { echo "[ensure] rebuild failed" >&2; exit 1; }
fi

pkill -f 'node dist/index.js' 2>/dev/null || true
sleep 0.3
nohup node dist/index.js < /dev/zero > "$LOG" 2>&1 &
echo $! > "$SERVER/.server.pid"

for _ in $(seq 1 40); do
  if alive; then
    [ "$MODE" = "--quiet" ] || echo "[ensure] restarted ok"
    exit 0
  fi
  sleep 0.5
done

echo "[ensure] restart FAILED" >&2
tail -n 20 "$LOG" >&2
exit 1
