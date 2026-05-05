#!/usr/bin/env bash
set -euo pipefail

MODEL="${OLLAMA_MODEL:-gemma4:e2b-it-q4_K_M}"

echo "[pull-on-start] starting ollama serve in background"
ollama serve &
SERVE_PID=$!

shutdown() {
  echo "[pull-on-start] received signal, stopping ollama (pid $SERVE_PID)"
  kill -TERM "$SERVE_PID" 2>/dev/null || true
  wait "$SERVE_PID" 2>/dev/null || true
  exit 0
}
trap shutdown SIGTERM SIGINT

echo "[pull-on-start] waiting for API on 127.0.0.1:11434"
for i in $(seq 1 60); do
  if curl -fs http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
    echo "[pull-on-start] API is up"
    break
  fi
  sleep 1
done

if ! curl -fs http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
  echo "[pull-on-start] ERROR: ollama serve did not become ready within 60s" >&2
  kill -TERM "$SERVE_PID" 2>/dev/null || true
  exit 1
fi

echo "[pull-on-start] ensuring model is pulled: $MODEL"
if ! ollama pull "$MODEL"; then
  echo "[pull-on-start] ERROR: failed to pull model '$MODEL'" >&2
  echo "[pull-on-start] check the tag at https://ollama.com/library" >&2
  kill -TERM "$SERVE_PID" 2>/dev/null || true
  exit 1
fi

echo "[pull-on-start] model ready, attaching to ollama serve"
wait "$SERVE_PID"
