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

**Extension says CORS error.** Confirm the origins env var reached the
running server process:

- Native: `start.sh` prints `[start] CORS: chrome-extension://*,moz-extension://*`
  on startup; if that line is missing or different, your `.env` is
  overriding it. To inspect the live process on Linux:
  `cat /proc/$(pgrep -f 'ollama serve' | tail -1)/environ | tr '\0' '\n' | grep ORIGINS`.
- Docker: `docker compose exec ollama env | grep OLLAMA_ORIGINS`.

The script and compose file both set it to
`chrome-extension://*,moz-extension://*`. Ollama also includes those
origins in its built-in defaults as of v0.20, so most users never need
to think about this.

**Pull is stuck or slow.** Check disk space (`df -h`) and that you can
reach `https://registry.ollama.ai`. The full model is 7.2 GB; on a
10 Mbit connection that is over an hour.

**Port 11434 is already in use.** Set `OLLAMA_HOST_PORT=11500` (or any
free port) in `.env`, then update the extension's Base URL accordingly.

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
