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

echo "[start] launching 'ollama serve' in background"
ollama serve &
SERVE_PID=$!

shutdown() {
  echo "[start] shutting down (pid $SERVE_PID)"
  kill -TERM "$SERVE_PID" 2>/dev/null || true
  wait "$SERVE_PID" 2>/dev/null || true
  exit 0
}
trap shutdown INT TERM

echo "[start] waiting for API on http://$OLLAMA_HOST"
for i in $(seq 1 60); do
  if curl -fs "http://$OLLAMA_HOST/api/tags" >/dev/null 2>&1; then
    echo "[start] API is up"
    break
  fi
  sleep 1
done

if ! curl -fs "http://$OLLAMA_HOST/api/tags" >/dev/null 2>&1; then
  echo "[start] ERROR: API did not become ready within 60s" >&2
  kill -TERM "$SERVE_PID" 2>/dev/null || true
  exit 1
fi

echo "[start] pulling model: $OLLAMA_MODEL (first run downloads ~7 GB)"
if ! ollama pull "$OLLAMA_MODEL"; then
  echo "[start] ERROR: failed to pull '$OLLAMA_MODEL'" >&2
  echo "[start] check the tag at https://ollama.com/library" >&2
  kill -TERM "$SERVE_PID" 2>/dev/null || true
  exit 1
fi

echo "[start] ready. press Ctrl+C to stop."
wait "$SERVE_PID"
