#!/usr/bin/env bash
# ============================================================
#  Persona - one-command launcher for Linux / macOS
#  Installs what's missing, starts the engine API + dashboard
#  and opens the web console. Ctrl+C stops both.
#
#  Usage: ./start.sh [cloak|camoufox|patchright|playwright]
#         (optional: set the default engine for NEW profiles)
#  Re-run setup: delete engine/.venv or dashboard/node_modules.
# ============================================================
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENGINE_DIR="$ROOT/engine"
DASH_DIR="$ROOT/dashboard"
VENV="$ENGINE_DIR/.venv"
PERSONA="$VENV/bin/persona"

say() { printf '  %s\n' "$*"; }
die() { printf '  [X] %s\n' "$*" >&2; exit 1; }

# ---- 1. Prerequisites ---------------------------------------
PY="$(command -v python3 || command -v python || true)"
[ -n "$PY" ] || die "Python 3.9+ not found. Install it and re-run."
command -v npm >/dev/null || die "Node.js 18+ (npm) not found. Install it and re-run."
say "[ok] Python: $("$PY" --version 2>&1)  |  Node: $(node --version)"

# ---- 2. Engine setup (only when missing) --------------------
if [ ! -x "$PERSONA" ]; then
  say "Installing the engine (Python venv)..."
  "$PY" -m venv "$VENV"
  "$VENV/bin/pip" install -q --upgrade pip
  "$VENV/bin/pip" install -q -e "$ENGINE_DIR[api,launch,secure]"
  "$VENV/bin/pip" install -q patchright cloakbrowser || say "[!] Optional engines failed to install; Playwright still works."
  say "Downloading the Chromium browser..."
  "$VENV/bin/playwright" install chromium
fi

# ---- 3. Dashboard setup (only when missing) -----------------
if [ ! -d "$DASH_DIR/node_modules" ]; then
  say "Installing the dashboard (npm)..."
  (cd "$DASH_DIR" && npm install --no-audit --no-fund)
fi

# ---- 4. Optional: default engine for new profiles -----------
if [ $# -ge 1 ]; then
  "$PERSONA" default-engine "$1"
fi

# ---- 5. Start both, stop both on exit -----------------------
pids=()
cleanup() {
  trap - INT TERM EXIT
  say "Stopping Persona..."
  for pid in "${pids[@]}"; do kill "$pid" 2>/dev/null || true; done
  wait 2>/dev/null || true
}
trap cleanup INT TERM EXIT

say "Starting the engine API on http://localhost:8787 ..."
(cd "$ENGINE_DIR" && exec "$PERSONA" serve) &
pids+=($!)

say "Starting the dashboard on http://localhost:5173 ..."
(cd "$DASH_DIR" && exec npm run dev -- --strictPort) &
pids+=($!)

# Open the browser once the dashboard answers.
(
  for _ in $(seq 1 30); do
    if curl -s -o /dev/null http://localhost:5173; then
      if command -v xdg-open >/dev/null; then xdg-open http://localhost:5173 >/dev/null 2>&1
      elif command -v open >/dev/null; then open http://localhost:5173
      fi
      break
    fi
    sleep 1
  done
) &

echo
say "Persona is running. Dashboard: http://localhost:5173  |  API: http://localhost:8787"
say "Press Ctrl+C to stop everything."
echo

# If either process dies, stop the other one too.
# (polling loop instead of `wait -n`, which macOS's bash 3.2 lacks)
while kill -0 "${pids[0]}" 2>/dev/null && kill -0 "${pids[1]}" 2>/dev/null; do
  sleep 1
done
