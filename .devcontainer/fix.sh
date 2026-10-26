#!/usr/bin/env bash
# One-shot: build + run + make port public. Safe to run any time.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER="$ROOT/server"
PORT=16384

cd "$SERVER" || exit 1

if [ ! -d node_modules ]; then
  echo "[setup] npm install"
  npm install --no-audit --no-fund
fi

if [ ! -f dist/index.js ] || [ -n "$(find src -name '*.ts' -newer dist/index.js -print -quit 2>/dev/null)" ]; then
  echo "[setup] compiling TypeScript"
  npx tsc || { echo "[setup] BUILD FAILED" >&2; exit 1; }
fi

echo "[setup] restarting server"
pkill -f 'node dist/index.js' 2>/dev/null || true
sleep 0.4
nohup node dist/index.js < /dev/zero > "$SERVER/.server.log" 2>&1 &
echo $! > "$SERVER/.server.pid"

for _ in $(seq 1 40); do
  curl -fsS "http://127.0.0.1:${PORT}/api/status" >/dev/null 2>&1 && break
  sleep 0.5
done

if ! curl -fsS "http://127.0.0.1:${PORT}/api/status" >/dev/null 2>&1; then
  echo "[setup] server did not start; log:" >&2
  tail -n 30 "$SERVER/.server.log" >&2
  exit 1
fi

if command -v gh >/dev/null 2>&1 && [ -n "${CODESPACE_NAME:-}" ]; then
  gh codespace ports visibility "$PORT:public" -c "$CODESPACE_NAME" >/dev/null 2>&1 \
    && echo "[setup] port $PORT -> public" \
    || echo "[setup] gh could not set visibility; use the PORTS panel instead"
fi

URL="http://localhost:${PORT}"
if [ -n "${CODESPACE_NAME:-}" ] && [ -n "${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN:-}" ]; then
  URL="https://${CODESPACE_NAME}-${PORT}.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}"
fi

cat <<INFO

  ============================================================
   Server up.
     Status : $URL/api/status
     MCP    : $URL/mcp

   Executor (paste BEFORE loading DEX++):
     getgenv().BridgeURL = "$URL"
     loadstring(game:HttpGet("https://raw.githubusercontent.com/986mn/roblox-DEXplusX5-AI-MCP/main/script.lua"))()
     loadstring(game:HttpGet("https://raw.githubusercontent.com/986mn/roblox-DEXplusX5-AI-MCP/main/dex_mcp_poller.lua"))()
  ============================================================

INFO
