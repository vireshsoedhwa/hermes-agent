# Hermes Agent — Docker Compose

A ready-to-run [Hermes Agent](https://hermes-agent.nousresearch.com) deployment. Clone, add one model-provider key, generate a local API server key, and start.

Hermes is a self-improving AI agent from [Nous Research](https://nousresearch.com) with a built-in learning loop — it creates skills from experience, remembers across sessions, and reaches you over a web dashboard, an OpenAI-compatible API, or chat platforms like Telegram and Discord.

---

## Quick start

```bash
git clone <this-repo> hermes-agent
cd hermes-agent
cp .env.example .env
# Edit .env — at minimum, set one LLM provider key and HERMES_API_SERVER_KEY
docker compose up -d
```

Open the dashboard at **http://localhost:9119**.

The only external credential you need for Hermes is **one API key from a model provider**. You must also generate a local `HERMES_API_SERVER_KEY`. [Ollama Cloud](https://ollama.com/settings/keys) is the easiest provider to start with — hosted open models, no GPU, free tier.

### Minimal `.env`

At minimum, set these two values:

```bash
# Pick one provider and paste its key:
OLLAMA_API_KEY=sk-...

# Generate an API server key (required, at least 16 chars):
HERMES_API_SERVER_KEY=$(openssl rand -hex 32)
```

Everything else needed for Hermes has a default or is optional. See `.env.example` for the full reference.

---

## Repository layout

| Folder | Purpose |
| --- | --- |
| `hermes-data/` | Persistent Hermes runtime state. It is mounted at `/opt/data` in the Hermes container and at `/data` in preflight. Conversations, memory, learned skills, configuration, and logs live here. Runtime contents are gitignored; `.gitkeep` only preserves the empty folder in a fresh clone. Back up this folder to preserve Hermes state. |
| `shared/` | Explicit host ↔ Hermes file exchange. It is mounted read-write at `/shared` in the Hermes container. Put documents here when you want Hermes to read them, and let Hermes write exports here. Its runtime contents are gitignored. |
| `scripts/` | Tracked host-side/container support scripts. `preflight.sh` is mounted read-only into the preflight container and validates Hermes credentials, API server-key requirements, optional-capability settings, and data-directory writability before startup. |

---

## Prerequisites

### Software

You need **Git** and **Docker**. Nothing else — no Python, no Node, no local model runtime.

| Tool | macOS | Windows | Linux |
| --- | --- | --- | --- |
| **Git** | [git-scm.com](https://git-scm.com/downloads) or `brew install git` | [git-scm.com](https://git-scm.com/downloads) (includes Git Bash) | `apt install git` / `dnf install git` |
| **Docker** | [Docker Desktop](https://docker.com) | [Docker Desktop](https://docker.com) (includes Compose v2) | [Docker Engine](https://docs.docker.com/engine/install/) + [Compose v2](https://docs.docker.com/compose/install/) |

Docker Desktop includes everything you need (Engine + Compose). On Linux, install both Engine and the Compose plugin separately.

### API keys

| What | Required? | Where to get it |
| --- | --- | --- |
| **An LLM provider key** | **Yes** | [Ollama Cloud](https://ollama.com/settings/keys), [OpenRouter](https://openrouter.ai/keys), [Anthropic](https://console.anthropic.com/settings/keys), [OpenAI](https://platform.openai.com/api-keys), [Gemini](https://aistudio.google.com/app/apikey), [Groq](https://console.groq.com/keys), [DeepSeek](https://platform.deepseek.com/api_keys), or [xAI](https://console.x.ai) |
| **API server key** | **Yes** | Generate with `openssl rand -hex 32` — the gateway refuses to start without at least 16 characters |
| **Web search key** | Optional | [Brave](https://brave.com/search/api/) (free tier), [Tavily](https://app.tavily.com/home), or [Exa](https://exa.ai) — without one the agent cannot search the web |
| **Voice / transcription** | Optional | [ElevenLabs](https://elevenlabs.io) for speech output; a Groq key also enables Whisper transcription |
| **Chat platform token** | Optional | [Telegram](https://t.me/BotFather), [Discord](https://discord.com/developers/applications), or [Slack](https://api.slack.com/apps) — without one, use the dashboard, the API, or `docker exec` |

Everything optional can be added later by editing `.env` and running `docker compose up -d`.

---

## The preflight check

A gating `preflight` service runs before Hermes on every `docker compose up`. Hermes is blocked from starting until it passes, so you get a clear error instead of a container that boots and then quietly fails.

```
Hermes Agent preflight
----------------------
  OK    LLM provider credential found: OLLAMA_API_KEY
  OK    Provider 'ollama-cloud' has its credential (OLLAMA_API_KEY)
  OK    Default model: gpt-oss:120b
  OK    API server key is set (64 chars)
  OK    Data directory is mounted and writable
  WARN  No web search key set; web search will be limited.
  WARN  GATEWAY_ALLOW_ALL_USERS=true — every user is authorized.
----------------------
Preflight passed with 2 warning(s). Starting Hermes...
```

It **fails the startup** when:

- No LLM provider key is set at all
- `HERMES_INFERENCE_PROVIDER` points at a provider whose key is missing
- The API server key is empty, a placeholder, or under 16 characters
- The shared data directory is missing or not writable by the container

It **warns but continues** for missing optional capabilities and for insecure-but-intentional settings. Every failure message names the fix — usually editing `.env`.

Run it on its own at any time:

```bash
docker compose run --rm preflight
```

---

## Runtime state and shared files

Hermes runtime state — configuration, conversation history, memory, learned skills, and logs — lives in one directory mounted at `/opt/data` inside the container.

By default that is `./hermes-data`. Point it anywhere with `HERMES_DATA_DIR` in `.env`:

```dotenv
HERMES_DATA_DIR=/Users/you/Documents/hermes-data
```

Back up this directory to preserve Hermes runtime state. A complete migration also requires securely recreating the machine's gitignored `.env` credentials and settings.

A separate host directory is mounted into Hermes at `/shared` for files you want Hermes to read:

```dotenv
HERMES_SHARED_DIR=./shared
```

The default is `./shared`; an absolute path also works. Hermes can read and write this explicit exchange directory.

All default host exchange directories are gitignored. Their committed `.gitkeep` files only ensure that fresh clones contain usable bind-mount targets.

---

## Everyday commands

```bash
docker compose up -d              # start (runs preflight first)
docker compose logs -f            # follow logs
docker compose down               # stop
docker compose pull && docker compose up -d   # upgrade to the latest image

docker exec -it hermes hermes     # interactive chat in your terminal
docker compose ps                 # health status
```

To reset Hermes runtime state at the default `./hermes-data` path while keeping `.env`:

```bash
docker compose down
find ./hermes-data -mindepth 1 -not -name .gitkeep -delete
```

If `HERMES_DATA_DIR` points elsewhere, replace `./hermes-data` with that exact directory after verifying the path. This command permanently deletes Hermes sessions, memory, learned skills, configuration, and logs.

### Endpoints

| URL | What |
| --- | --- |
| http://localhost:9119 | Web dashboard — chat, config, sessions, skills, logs |
| http://localhost:8642/v1 | OpenAI-compatible API — **loopback by default**, see below |

### Connecting other apps (optional)

The API server always runs — the dashboard needs it internally. By default it binds to `127.0.0.1` inside the container, so port 8642 is published but not reachable from the host.

To let external apps (Open WebUI, LibreChat, any OpenAI SDK) connect, set `HERMES_API_SERVER_HOST=0.0.0.0` in `.env`:

```bash
HERMES_API_SERVER_HOST=0.0.0.0
HERMES_API_SERVER_KEY=<at least 16 chars>
```

Then `docker compose up -d`. Use `HERMES_API_SERVER_KEY` as the API key in the client.

---

## Changing the model

Three ways, easiest first:

1. **Dashboard** — open http://localhost:9119, browse available models, and switch with one click. This is the recommended way.
2. **`/model` in chat** — switch for the current session, no restart.
3. **Edit `.env`** — set `HERMES_DEFAULT_MODEL` and run `docker compose up -d`.

Whichever you choose, the provider must match a key you have set — preflight stops you if they do not line up.

---

## Troubleshooting

**Preflight fails and Hermes never starts.** Working as intended. Check the error messages, edit `.env`, and re-run `docker compose up -d`.

**Permission denied writing to the data folder (Linux).** The container runs as UID 10000, which cannot write to a folder owned by you. Add your UID/GID to `.env`:

```bash
echo "HERMES_UID=$(id -u)" >> .env
echo "HERMES_GID=$(id -g)" >> .env
docker compose up -d
```

**Container is `unhealthy`.** The healthcheck asks the s6 supervisor whether the gateway is up. Inspect it directly:

```bash
docker exec hermes /command/s6-svstat /run/service/gateway-default
```

Anything other than `up` means the gateway is crashing — check `docker compose logs hermes`. A provider authentication error from an invalid key is the usual cause.

**`/v1` requests are refused.** The API server is bound to loopback by default. Set `HERMES_API_SERVER_HOST=0.0.0.0` (see [Connecting other apps](#connecting-other-apps-optional)).

**Port already in use.** Change the host side of the mapping in `docker-compose.yaml`, e.g. `"9120:9119"`.

**Agent cannot browse the web.** No search key is configured. Add a Brave Search key to `.env` (free tier) and restart.

---

## Security notes

This compose file is tuned for **local, single-user use**:

- `GATEWAY_ALLOW_ALL_USERS` is configurable in `.env` (defaults to `true`). When `true`, every gateway/dashboard user is authorized with no allowlist — fine for single-user loopback use. Preflight fails startup if it is `true` while `HERMES_API_SERVER_HOST=0.0.0.0`. Before exposing beyond loopback, set it to `false` with an explicit user allowlist and put a [dashboard auth provider](https://hermes-agent.nousresearch.com/docs/user-guide/features/web-dashboard) in front of the UI.
- The dashboard listens inside the container while Compose publishes it only on host loopback at `127.0.0.1:9119`.
- The API server binds to container loopback by default. Setting `HERMES_API_SERVER_HOST=0.0.0.0` makes it reachable through the Compose mapping at host loopback `127.0.0.1:8642`; it is still not published on the LAN. Keep `HERMES_API_SERVER_KEY` secret.

Hermes can run terminal commands. Before changing the host port mappings or otherwise exposing this deployment beyond your own machine, read the [security guide](https://hermes-agent.nousresearch.com/docs/user-guide/security), set `GATEWAY_ALLOW_ALL_USERS=false` with an explicit user allowlist, and put a [dashboard auth provider](https://hermes-agent.nousresearch.com/docs/user-guide/features/web-dashboard) in front of the UI.

Never commit `.env`. It is gitignored, and `.env.example` is the only one meant to be shared.

---

## Documentation

- [Hermes Agent docs](https://hermes-agent.nousresearch.com/docs/)
- [Docker guide](https://hermes-agent.nousresearch.com/docs/user-guide/docker)
- [Environment variable reference](https://hermes-agent.nousresearch.com/docs/reference/environment-variables)
- [Providers](https://hermes-agent.nousresearch.com/docs/integrations/providers)
- [GitHub](https://github.com/NousResearch/hermes-agent)
