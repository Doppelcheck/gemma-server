#!/usr/bin/env bash
set -euo pipefail

MODEL="${OLLAMA_MODEL:-gemma4:e2b-it-q4_K_M}"

# Strategy: run a temporary 'ollama serve' for the pull, then exec into a
# fresh 'ollama serve' as PID 1 so docker stop / SIGTERM goes straight to
# ollama with no shell trap fragility.

echo "[pull-on-start] launching temporary 'ollama serve' for the pull"
ollama serve >/dev/null 2>&1 &
SERVE_PID=$!

cleanup_temp() {
  if [ -n "${SERVE_PID:-}" ] && kill -0 "$SERVE_PID" 2>/dev/null; then
    kill -TERM "$SERVE_PID" 2>/dev/null || true
    wait "$SERVE_PID" 2>/dev/null || true
  fi
}
trap cleanup_temp EXIT

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
  exit 1
fi

echo "[pull-on-start] ensuring model is pulled: $MODEL"
if ! ollama pull "$MODEL"; then
  echo "[pull-on-start] ERROR: failed to pull model '$MODEL'" >&2
  echo "[pull-on-start] check the tag at https://ollama.com/library" >&2
  exit 1
fi

echo "[pull-on-start] stopping temporary serve to hand off"
kill -TERM "$SERVE_PID" 2>/dev/null || true
wait "$SERVE_PID" 2>/dev/null || true
SERVE_PID=""
trap - EXIT

for _ in $(seq 1 30); do
  if ! curl -fs http://127.0.0.1:11434/api/tags >/dev/null 2>&1; then
    break
  fi
  sleep 1
done

echo "[pull-on-start] handing off: exec ollama serve"
exec ollama serve
