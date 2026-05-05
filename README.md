# gemma-server

A zero-config local Gemma server for the
[DoppelCheck](https://github.com/doppelcheck/main) browser extension. One
command from clone to a working OpenAI-compatible / Ollama endpoint at
`http://localhost:11434`.

Two install paths. Pick the one that fits your machine.

## Option A: native (Linux / macOS) - smallest footprint

Requirements: `bash` and `curl`. Nothing else.

```bash
git clone https://github.com/doppelcheck/gemma-server.git
cd gemma-server
./start.sh
```

If Ollama is not already installed, the script asks for confirmation and
runs the official installer (Linux: `curl -fsSL https://ollama.com/install.sh | sh`;
macOS: `brew install ollama` if Homebrew is present, otherwise it points
you at https://ollama.com/download). Then it pulls the model and starts
the server.

Press Ctrl+C to stop.

## Option B: Docker (any OS, fully isolated)

Requirements: Docker Desktop or `docker` + `docker compose`.

```bash
git clone https://github.com/doppelcheck/gemma-server.git
cd gemma-server
docker compose up
```

Heavier (Docker itself is ~1 GB installed) but self-contained: nothing is
installed on your host, the model cache lives in `./ollama_data/`, and
`docker compose down` cleans up.

## Windows

Option B (Docker Desktop) is the cleanest path on Windows.

If you would rather install Ollama natively: the `OllamaSetup.exe` from
https://ollama.com/download installs Ollama as a background service that
auto-starts. To make it accept requests from the DoppelCheck extension
you have to set `OLLAMA_ORIGINS` for that service (a plain
`$env:OLLAMA_ORIGINS = ...` in PowerShell only affects the current
window, not the service). The simplest way:

```powershell
[Environment]::SetEnvironmentVariable("OLLAMA_ORIGINS",
  "chrome-extension://*,moz-extension://*", "User")
# then quit Ollama from the system tray and start it again,
# or reboot, so the service picks up the new variable.
ollama pull gemma4:e2b-it-q4_K_M
```

After that the model is reachable at `http://localhost:11434` like on the
other platforms.

## What you need

- Disk: about 10 GB free (the default model is 7.2 GB on disk).
- RAM: 8 GB minimum, 16 GB comfortable.
- Network: the first run downloads the model from the Ollama registry.

The first start takes 5 to 20 minutes depending on your connection.
Subsequent starts reuse the cached model and come up in seconds.

## Use it from DoppelCheck

In the extension settings:

- Tier: `Network`
- Provider: `Ollama`
- Base URL: `http://localhost:11434`
- Model: `gemma4:e2b-it-q4_K_M` (or whatever you set `OLLAMA_MODEL` to)

Click `Test connection`. You should see a green check.

## Use it from anything else

The OpenAI-compatible endpoint works with any client that lets you set a
base URL:

```bash
curl http://localhost:11434/v1/chat/completions \
  -H 'content-type: application/json' \
  -d '{
    "model": "gemma4:e2b-it-q4_K_M",
    "messages": [{"role": "user", "content": "Say hi"}]
  }'
```

The native Ollama API also works:

```bash
curl http://localhost:11434/api/generate \
  -d '{"model": "gemma4:e2b-it-q4_K_M", "prompt": "Say hi", "stream": false}'
```

## Switching models

```bash
cp .env.example .env
# edit .env and change OLLAMA_MODEL to any tag from
# https://ollama.com/library, e.g.:
#   gemma3:1b-it-q4_K_M   (~815 MB, much smaller)
#   gemma4:e4b-it-q4_K_M  (~9.6 GB, larger)
#   llama3:8b
#   qwen2.5:7b
```

Then restart:

- Native: stop the script (Ctrl+C), re-run `./start.sh`.
- Docker: `docker compose down && docker compose up -d`.

The new model is pulled on the next start. Old models stay on disk
until you remove them (`ollama rm <tag>` for the native install, or
`rm -rf ollama_data/` for the Docker install).

## Stopping

- Native: Ctrl+C in the foreground terminal. The script handles SIGTERM /
  SIGINT cleanly. If you ran with `nohup` or similar, find the pid with
  `pgrep -f 'ollama serve'` and `kill` it.
- Docker: `docker compose down`. Add `-v` to remove the named volumes
  (does not touch the bind-mounted `./ollama_data/`). To free disk:
  `rm -rf ollama_data/`.

## Troubleshooting

**Extension says CORS error (HTTP 403 from the daemon).** Ollama's
built-in default origins are localhost-only - they do *not* include
`chrome-extension://*` or `moz-extension://*`. The daemon needs to be
told about them via `OLLAMA_ORIGINS`. Both `start.sh` and the compose
file set this; it only fails when something else is serving 11434.

A common cause: the official Ollama installer on Linux sets up a
systemd service that runs without `OLLAMA_ORIGINS`, and that service
auto-starts before you ever run `start.sh`. `start.sh` then detects
the existing daemon and reuses it - inheriting its (insufficient)
CORS settings. Two fixes:

1. **Take over the port:** stop the systemd-managed daemon and let
   `start.sh` own it.
   ```bash
   sudo systemctl stop ollama
   sudo systemctl disable ollama   # optional, prevents auto-start
   ./start.sh
   ```

2. **Patch the system service:** keep the systemd-managed daemon and
   give it the right origins.
   ```bash
   sudo systemctl edit ollama
   # add:
   #   [Service]
   #   Environment="OLLAMA_ORIGINS=chrome-extension://*,moz-extension://*"
   sudo systemctl restart ollama
   ```

Verify either way with a preflight from a fake extension origin:

```bash
curl -sS -o /dev/null -D - -X OPTIONS http://127.0.0.1:11434/api/chat \
  -H 'Origin: moz-extension://abc' -H 'Access-Control-Request-Method: POST' \
  -w 'STATUS=%{http_code}\n' | grep -iE '^(STATUS|access-control-allow-origin)'
```

Expect `STATUS=204` and `Access-Control-Allow-Origin: moz-extension://abc`.

**Pull is stuck or slow.** Check disk space (`df -h`) and that you can
reach `https://registry.ollama.ai`. The full model is 7.2 GB; on a
10 Mbit connection that is over an hour.

**Port 11434 is already in use.** Most often this is because you already
have an Ollama daemon running (e.g. installed via the official installer,
which sets up a systemd service). `start.sh` detects this and falls back
to just pulling the model through the existing daemon - no second
`ollama serve` is started. The model is then served by your existing
daemon at the same `http://localhost:11434`. If that daemon's CORS
configuration rejects extension origins (rare on Ollama 0.20+), stop
it (`sudo systemctl stop ollama` on Linux) and re-run `start.sh` so
this script can own the daemon and apply its own `OLLAMA_ORIGINS`.

If port 11434 is held by a non-ollama service, set `OLLAMA_HOST_PORT=11500`
(or any free port) in `.env` and update the extension's Base URL to match.

**"failed to pull model".** The tag in `OLLAMA_MODEL` does not exist.
Check https://ollama.com/library and update `.env`.

**Native: "ollama: command not found" after install.** Open a new shell
(the installer added it to PATH), or run `hash -r` in the current shell.

## Why a separate repo?

This is a companion to the DoppelCheck extension, not part of it. The
extension already supports any Ollama or OpenAI-compatible endpoint, so
hosting the model elsewhere (a remote box, a different runtime, an
existing Ollama install) is fully supported - you would just point the
extension at that endpoint instead. This repo is for the common case
where you want a local server and do not want to think about it.

## License

MIT. See [LICENSE](LICENSE).
