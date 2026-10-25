#!/usr/bin/env bash
# Prevents Codespaces from pausing a free container due to inactivity.
# NOTE: this does NOT bypass the 12-hour hard cap on free Codespaces.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PORT=16384
INTERVAL=${KEEPALIVE_INTERVAL:-240}

while true; do
  sleep "$INTERVAL"
  curl -fsS --max-time 5 "http://127.0.0.1:${PORT}/api/status" >/dev/null 2>&1 \
    || bash "$ROOT/.devcontainer/ensure-running.sh" --quiet
  # a tiny filesystem touch also counts as activity for some watchdog heuristics
  touch /tmp/.keepalive 2>/dev/null || true
done
