#!/usr/bin/env bash
# Runs on every container start.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER="$ROOT/server"
LOG="$SERVER/.server.log"
PID="$SERVER/.server.pid"
PORT=16384

cd "$SERVER" || exit 1

make_port_public() {
  if command -v gh >/dev/null 2>&1 && [ -n "${CODESPACE_NAME:-}" ]; then
    gh codespace ports visibility "$PORT:public" -c "$CODESPACE_NAME" >/dev/null 2>&1 \
      && echo "  port $PORT is public" \
      || echo "  could not set visibility via gh (set it manually in the PORTS panel)"
  fi
}

public_url() {
  if [ -n "${CODESPACE_NAME:-}" ] && [ -n "${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN:-}" ]; then
    echo "https://${CODESPACE_NAME}-${PORT}.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}"
  else
    echo "http://localhost:${PORT}"
  fi
}

# stop stale
if [ -f "$PID" ]; then
  OLD=$(cat "$PID" 2>/dev/null || true)
  if [ -n "${OLD:-}" ] && kill -0 "$OLD" 2>/dev/null; then
    kill "$OLD" 2>/dev/null || true
    sleep 0.5
  fi
  rm -f "$PID"
fi
pkill -f 'node dist/index.js' 2>/dev/null || true

# rebuild if stale
if [ ! -f dist/index.js ] || [ package.json -nt dist/index.js ] || [ -n "$(find src -name '*.ts' -newer dist/index.js -print -quit 2>/dev/null)" ]; then
  echo "[start] dist is stale, rebuilding"
  npm install --no-audit --no-fund >/dev/null 2>&1 || true
  npx tsc || { echo "[start] BUILD FAILED" >&2; exit 1; }
fi

# run (hold stdin open: MCP is a stdio protocol)
nohup node dist/index.js < /dev/zero > "$LOG" 2>&1 &
NEW_PID=$!
echo "$NEW_PID" > "$PID"

for _ in $(seq 1 40); do
  if curl -fsS "http://127.0.0.1:${PORT}/api/status" >/dev/null 2>&1; then break; fi
  sleep 0.5
done

if ! curl -fsS "http://127.0.0.1:${PORT}/api/status" >/dev/null 2>&1; then
  echo "[start] server did not come up; last log lines:" >&2
  tail -n 30 "$LOG" >&2
  exit 1
fi

make_port_public
URL="$(public_url)"

printf '\n  ============================================================\n'
printf '   DEX++ MCP bridge is running (pid %s)\n\n' "$NEW_PID"
printf '   Dashboard : %s/\n' "$URL"
printf '   Status    : %s/api/status\n\n' "$URL"
printf '   Paste into your executor BEFORE loading DEX++:\n\n'
printf '     getgenv().BridgeURL = "%s"\n' "$URL"
printf '     loadstring(game:HttpGet("https://raw.githubusercontent.com/986mn/roblox-DEXplusX5-AI-MCP/main/script.lua"))()\n'
printf '     loadstring(game:HttpGet("https://raw.githubusercontent.com/986mn/roblox-DEXplusX5-AI-MCP/main/dex_mcp_poller.lua"))()\n\n'
printf '   If https fails on your executor use your LAN IP instead.\n'
printf '  ============================================================\n\n'

nohup bash "$ROOT/.devcontainer/keepalive.sh" > /dev/null 2>&1 &
