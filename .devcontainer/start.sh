#!/usr/bin/env bash
# Runs on every container start.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SERVER="$ROOT/server"
LOG="$SERVER/.server.log"
PID="$SERVER/.server.pid"
PORT=16384

cd "$SERVER" || exit 1

public_url() {
  if [ -n "${CODESPACE_NAME:-}" ] && [ -n "${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN:-}" ]; then
    echo "https://${CODESPACE_NAME}-${PORT}.${GITHUB_CODESPACES_PORT_FORWARDING_DOMAIN}"
  else
    echo "http://localhost:${PORT}"
  fi
}

make_port_public() {
  local ok=0
  if command -v gh >/dev/null 2>&1 && [ -n "${CODESPACE_NAME:-}" ]; then
    if gh codespace ports visibility "$PORT:public" -c "$CODESPACE_NAME" >/dev/null 2>&1; then
      echo "  [port] public via gh"; ok=1
    fi
  fi
  if [ "$ok" = "0" ] && [ -n "${GITHUB_TOKEN:-}" ] && [ -n "${CODESPACE_NAME:-}" ]; then
    local api="https://api.github.com/user/codespaces/${CODESPACE_NAME}/ports/${PORT}"
    if curl -fsS -X PATCH "$api" \
        -H "Authorization: Bearer ${GITHUB_TOKEN}" \
        -H "Accept: application/vnd.github+json" \
        -H "X-GitHub-Api-Version: 2022-11-28" \
        -d '{"visibility":"public"}' >/dev/null 2>&1; then
      echo "  [port] public via api"; ok=1
    fi
  fi
  [ "$ok" = "0" ] && echo "  [port] NOT public - falling back to tunnel"
  return 0
}

start_tunnel() {
  local bin="/tmp/cloudflared" arch
  arch="$(uname -m)"
  case "$arch" in
    x86_64|amd64) arch="amd64" ;;
    aarch64|arm64) arch="arm64" ;;
    *) echo "  [tunnel] unsupported arch $arch"; return 1 ;;
  esac
  if [ ! -x "$bin" ]; then
    curl -fsSL -o "$bin" \
      "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${arch}" \
      >/dev/null 2>&1 || { echo "  [tunnel] download failed"; return 1; }
    chmod +x "$bin"
  fi
  pkill -f 'cloudflared tunnel' 2>/dev/null || true
  nohup "$bin" tunnel --url "http://127.0.0.1:${PORT}" --no-autoupdate \
    > /tmp/cf.log 2>&1 &
  for _ in $(seq 1 30); do
    sleep 1
    local u
    u="$(grep -oE 'https://[a-z0-9-]+\.trycloudflare\.com' /tmp/cf.log 2>/dev/null | head -1)"
    if [ -n "$u" ]; then echo "$u" > /tmp/cf.url; echo "  [tunnel] $u"; return 0; fi
  done
  echo "  [tunnel] no url after 30s (see /tmp/cf.log)"; return 1
}

if [ -f "$PID" ]; then
  OLD=$(cat "$PID" 2>/dev/null || true)
  if [ -n "${OLD:-}" ] && kill -0 "$OLD" 2>/dev/null; then
    kill "$OLD" 2>/dev/null || true
    sleep 0.5
  fi
  rm -f "$PID"
fi
pkill -f 'node dist/index.js' 2>/dev/null || true

if [ ! -f dist/index.js ] || [ package.json -nt dist/index.js ] \
   || [ -n "$(find src -name '*.ts' -newer dist/index.js -print -quit 2>/dev/null)" ]; then
  echo "[start] dist is stale, rebuilding"
  npm install --no-audit --no-fund >/dev/null 2>&1 || true
  npx tsc || { echo "[start] BUILD FAILED" >&2; exit 1; }
fi

nohup node dist/index.js < /dev/zero > "$LOG" 2>&1 &
NEW_PID=$!
echo "$NEW_PID" > "$PID"

for _ in $(seq 1 40); do
  curl -fsS "http://127.0.0.1:${PORT}/api/status" >/dev/null 2>&1 && break
  sleep 0.5
done

if ! curl -fsS "http://127.0.0.1:${PORT}/api/status" >/dev/null 2>&1; then
  echo "[start] server did not come up; last log lines:" >&2
  tail -n 30 "$LOG" >&2
  exit 1
fi

make_port_public
URL="$(public_url)"

external_ok=0
if [ -n "${CODESPACE_NAME:-}" ]; then
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 8 "${URL}/api/status" || echo 000)"
  [ "$code" = "200" ] && external_ok=1
  echo "  [probe] ${URL}/api/status -> ${code}"
fi

TUNNEL_URL=""
if [ "$external_ok" = "0" ]; then
  echo "  [probe] external not reachable, starting tunnel"
  TUNNEL_URL="$(start_tunnel || true)"
fi

EFFECTIVE_URL="${TUNNEL_URL:-$URL}"

printf '\n  ============================================================\n'
printf '   DEX++ MCP bridge is running (pid %s)\n\n' "$NEW_PID"
printf '   Status : %s/api/status\n' "$EFFECTIVE_URL"
printf '   MCP    : %s/mcp\n\n' "$EFFECTIVE_URL"
printf '   Paste into your executor BEFORE loading DEX++:\n\n'
printf '     getgenv().BridgeURL = "%s"\n' "$EFFECTIVE_URL"
printf '     loadstring(game:HttpGet("https://raw.githubusercontent.com/986mn/roblox-DEXplusX5-AI-MCP/main/script.lua"))()\n'
printf '     loadstring(game:HttpGet("https://raw.githubusercontent.com/986mn/roblox-DEXplusX5-AI-MCP/main/dex_mcp_poller.lua"))()\n\n'
[ -z "$TUNNEL_URL" ] && printf '   If 401 persists: PORTS panel -> 16384 -> Port Visibility -> Public\n'
printf '  ============================================================\n\n'

nohup bash "$ROOT/.devcontainer/keepalive.sh" > /dev/null 2>&1 &
