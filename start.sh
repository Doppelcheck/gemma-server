#!/usr/bin/env bash
# Native (no-Docker) launcher for gemma-server.
# Installs Ollama if missing, pulls the model, and starts the server with
# CORS origins set so the DoppelCheck browser extension can connect.
set -euo pipefail

cd "$(dirname "$0")"

if [ -f .env ]; then
  set -a
  . ./.env
  set +a
fi

OLLAMA_MODEL="${OLLAMA_MODEL:-gemma4:e2b-it-q4_K_M}"
OLLAMA_HOST_PORT="${OLLAMA_HOST_PORT:-11434}"
export OLLAMA_HOST="${OLLAMA_HOST:-127.0.0.1:${OLLAMA_HOST_PORT}}"
export OLLAMA_ORIGINS="${OLLAMA_ORIGINS:-chrome-extension://*,moz-extension://*}"

prompt_yes() {
  local q="$1"
  if [ ! -t 0 ]; then
    return 1
  fi
  read -r -p "$q [y/N] " ans
  [[ "$ans" =~ ^[Yy]$ ]]
}

install_ollama() {
  local os
  os="$(uname -s)"
  case "$os" in
    Linux)
      echo "[start] Ollama not found. The official installer will run:"
      echo "        curl -fsSL https://ollama.com/install.sh | sh"
      if ! prompt_yes "Proceed with install?"; then
        echo "[start] Aborted. Install manually from https://ollama.com/download" >&2
        exit 1
      fi
      curl -fsSL https://ollama.com/install.sh | sh
      ;;
    Darwin)
      if command -v brew >/dev/null 2>&1; then
        echo "[start] Ollama not found. Homebrew is available."
        if prompt_yes "Install via 'brew install ollama'?"; then
          brew install ollama
          return
        fi
      fi
      echo "[start] On macOS without Homebrew, download the app from"
      echo "        https://ollama.com/download then re-run this script." >&2
      exit 1
      ;;
    *)
      echo "[start] Auto-install not supported on '$os'." >&2
      echo "[start] Install Ollama from https://ollama.com/download and re-run." >&2
      exit 1
      ;;
  esac
}

if ! command -v ollama >/dev/null 2>&1; then
  install_ollama
fi

if ! command -v ollama >/dev/null 2>&1; then
  echo "[start] ERROR: ollama is still not on PATH after install." >&2
  echo "[start] Open a new shell or check the installer output." >&2
  exit 1
fi

echo "[start] ollama: $(command -v ollama)"
echo "[start] model:  $OLLAMA_MODEL"
echo "[start] listen: http://$OLLAMA_HOST"
echo "[start] CORS:   $OLLAMA_ORIGINS"

# Pre-flight: if an ollama daemon is already on this port (typical when
# the user installed via the official installer, which sets up a systemd
# service), we cannot bind a second serve. Reuse the existing daemon:
# do the pull through it and exit cleanly. CORS in that case is governed
# by the running daemon's OLLAMA_ORIGINS, not ours - Ollama 0.20+ already
# includes chrome-extension://* and moz-extension://* by default, so
# this usually Just Works.
if curl -fs "http://$OLLAMA_HOST/api/version" -o /dev/null 2>&1; then
  echo "[start] detected an existing ollama daemon on $OLLAMA_HOST"
  echo "[start] reusing it (will not start a second serve)"
  echo "[start] pulling model: $OLLAMA_MODEL"
  if ! ollama pull "$OLLAMA_MODEL"; then
    echo "[start] ERROR: failed to pull '$OLLAMA_MODEL'" >&2
    echo "[start] check the tag at https://ollama.com/library" >&2
    exit 1
  fi
  echo "[start] ready. the model is served by the existing ollama daemon."
  echo "[start] note: CORS is governed by that daemon's OLLAMA_ORIGINS,"
  echo "        not by this script. Ollama's built-in defaults do NOT include"
  echo "        extension origins, so if the daemon was started without"
  echo "        OLLAMA_ORIGINS (typical for the systemd unit), the DoppelCheck"
  echo "        extension will get HTTP 403. Either stop the existing daemon"
  echo "        ('sudo systemctl stop ollama') and re-run start.sh, or add"
  echo "        OLLAMA_ORIGINS to the systemd unit ('sudo systemctl edit ollama')."
  exit 0
fi

# Strategy: spawn a temporary 'ollama serve' just long enough to do the
# pull, then replace this script process with a fresh 'ollama serve' via
# exec. SIGTERM / SIGINT then go straight to ollama (which handles them
# natively), so there is no child-process or trap fragility.

echo "[start] launching temporary 'ollama serve' for the pull step"
ollama serve >/dev/null 2>&1 &
SERVE_PID=$!

# If the script dies before the exec (errors, Ctrl+C during pull), make
# sure we do not leave the temporary serve running.
cleanup_temp() {
  if [ -n "${SERVE_PID:-}" ] && kill -0 "$SERVE_PID" 2>/dev/null; then
    kill -TERM "$SERVE_PID" 2>/dev/null || true
    wait "$SERVE_PID" 2>/dev/null || true
  fi
}
trap cleanup_temp EXIT

echo "[start] waiting for API on http://$OLLAMA_HOST"
for _ in $(seq 1 60); do
  if curl -fs "http://$OLLAMA_HOST/api/tags" >/dev/null 2>&1; then
    echo "[start] API is up"
    break
  fi
  sleep 1
done

if ! curl -fs "http://$OLLAMA_HOST/api/tags" >/dev/null 2>&1; then
  echo "[start] ERROR: API did not become ready within 60s" >&2
  exit 1
fi

echo "[start] pulling model: $OLLAMA_MODEL"
echo "        (first run downloads several GB; idempotent on later runs)"
if ! ollama pull "$OLLAMA_MODEL"; then
  echo "[start] ERROR: failed to pull '$OLLAMA_MODEL'" >&2
  echo "[start] check the tag at https://ollama.com/library" >&2
  exit 1
fi

# Stop the temporary serve so we can rebind the port via exec.
echo "[start] stopping temporary serve to hand off"
kill -TERM "$SERVE_PID" 2>/dev/null || true
wait "$SERVE_PID" 2>/dev/null || true
trap - EXIT

# Wait for the port to be released (usually instant).
for _ in $(seq 1 30); do
  if ! curl -fs "http://$OLLAMA_HOST/api/tags" >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

echo "[start] ready. press Ctrl+C to stop."
# Replace this script with ollama serve. From here on, ollama itself is
# the foreground process, so it receives SIGTERM / SIGINT directly and
# shuts down cleanly.
exec ollama serve
