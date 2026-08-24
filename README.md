# Hermes Agent — Docker Compose

A ready-to-run [Hermes Agent](https://hermes-agent.nousresearch.com) deployment. Clone, add one API key, and start.

Hermes is a self-improving AI agent from [Nous Research](https://nousresearch.com) with a built-in learning loop — it creates skills from experience, remembers across sessions, and reaches you over a web dashboard, an OpenAI-compatible API, or chat platforms like Telegram and Discord.

No config files to edit. A guided setup asks a few questions, writes your configuration, and starts the agent.

---

## Quick start

```bash
git clone <this-repo> hermes-agent
cd hermes-agent
./setup.sh
```

That's it. The wizard walks you through six short steps, then offers to start Hermes. When it finishes, open the dashboard:

**http://localhost:9119**

The only thing you need to bring is **one API key from a model provider**. [Ollama Cloud](https://ollama.com/settings/keys) is the easiest place to start — hosted open models, no GPU, free tier — and the wizard links you straight to the signup page for whichever provider you pick.

### What the wizard asks

| Step | Question | Notes |
| --- | --- | --- |
| 1 | Which model provider? | Menu of 8, with a link to get the key |
| 2 | Which model? | Suggestions for your provider, or type your own |
| 3 | Allow external API access? | Loopback by default; say yes for Open WebUI etc. |
| 4 | Web search? | Optional, skippable |
| 5 | Chat platform? | Optional — Telegram, Discord, Slack, or skip |
| 6 | Where to store data? | Defaults to `./hermes-data` |

Keys are hidden as you paste them and echoed back masked (`****3456`) so you can confirm. Re-run `./setup.sh` any time to change your answers; your previous `.env` is backed up with a timestamp.

Prefer to configure by hand? `cp .env.example .env` and edit — every option is documented there.

---

## Prerequisites

Docker Desktop (macOS/Windows) or Docker Engine + Compose v2 (Linux). Nothing else — no Python, no Node, no local model runtime.

| What | Required? | Where to get it |
| --- | --- | --- |
| **An LLM provider key** | **Yes** | [Ollama Cloud](https://ollama.com/settings/keys), [OpenRouter](https://openrouter.ai/keys), [Anthropic](https://console.anthropic.com/settings/keys), [OpenAI](https://platform.openai.com/api-keys), [Gemini](https://aistudio.google.com/app/apikey), [Groq](https://console.groq.com/keys), [DeepSeek](https://platform.deepseek.com/api_keys), or [xAI](https://console.x.ai) |
| **API server key** | **Yes** | Generated for you by `./setup.sh` (always required) |
| **Web search key** | Optional | [Brave](https://brave.com/search/api/) (free tier), [Tavily](https://app.tavily.com/home), or [Exa](https://exa.ai) — without one the agent cannot search the web |
| **Voice / transcription** | Optional | [ElevenLabs](https://elevenlabs.io) for speech output; a Groq key also enables Whisper transcription |
| **Chat platform token** | Optional | [Telegram](https://t.me/BotFather), [Discord](https://discord.com/developers/applications), or [Slack](https://api.slack.com/apps) — without one, use the dashboard, the API, or `docker exec` |

Everything optional can be added later by re-running `./setup.sh`.

---

## The preflight check

A gating `preflight` service runs before Hermes on every `docker compose up`. Hermes is blocked from starting until it passes, so you get a clear error instead of a container that boots and then quietly fails.

```
Hermes Agent preflight
----------------------
  OK    LLM provider credential found: OLLAMA_API_KEY
  OK    Provider 'ollama-cloud' has its credential (OLLAMA_API_KEY)
  OK    Default model: ollama-cloud/gemma4:31b-cloud
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

It **warns but continues** for missing optional capabilities and for insecure-but-intentional settings. Every failure message names the fix, usually `./setup.sh`.

Run it on its own at any time:

```bash
docker compose run --rm preflight
```

The wizard and the gate are complementary: `./setup.sh` is interactive and gets your configuration right the first time, while `preflight` runs non-interactively on every `docker compose up` and catches drift afterwards.

---

## Your data lives in one folder

Everything Hermes owns — config, conversation history, memory, learned skills, credentials, and logs — lives in a single directory mounted at `/opt/data` inside the container.

By default that is `./hermes-data`. Point it anywhere with `HERMES_DATA_DIR` in `.env`:

```bash
HERMES_DATA_DIR=/Users/you/Documents/hermes-data
```

**This one folder is your entire agent.** Back it up and you have backed up everything. Copy it to another machine, clone this repo there, and your agent picks up exactly where it left off. It is gitignored, so nothing personal is ever committed.

---

## Everyday commands

```bash
./setup.sh                        # guided setup / reconfigure
docker compose up -d              # start (runs preflight first)
docker compose logs -f            # follow logs
docker compose down               # stop
docker compose pull && docker compose up -d   # upgrade to the latest image

docker exec -it hermes hermes     # interactive chat in your terminal
docker compose ps                 # health status
```

### Endpoints

| URL | What |
| --- | --- |
| http://localhost:9119 | Web dashboard — chat, config, sessions, skills, logs |
| http://localhost:8642/v1 | OpenAI-compatible API — **loopback by default**, see below |

### Connecting other apps (optional)

The API server always runs — the dashboard needs it internally. By default it binds to `127.0.0.1` inside the container, so port 8642 is published but not reachable from the host.

To let external apps (Open WebUI, LibreChat, any OpenAI SDK) connect, say yes during `./setup.sh`, or set it directly:

```bash
HERMES_API_SERVER_HOST=0.0.0.0
HERMES_API_SERVER_KEY=<at least 16 chars>
```

Then `docker compose up -d`. Use `HERMES_API_SERVER_KEY` as the API key in the client.

---

## Changing the model

Three ways, easiest first:

1. **`/model` in the dashboard chat** — switch for the current session, no restart.
2. **`./setup.sh`** — pick a new provider and model, then it restarts for you.
3. **Edit `.env`** and run `docker compose up -d`.

Whichever you choose, the provider must match a key you have set — preflight stops you if they do not line up.

---

## Troubleshooting

**Preflight fails and Hermes never starts.** Working as intended. Run `./setup.sh` — it fixes every condition preflight checks for.

**`./setup.sh: Permission denied`.** Run `chmod +x setup.sh` first, or invoke it as `sh setup.sh`.

**Permission denied writing to the data folder (Linux).** The container runs as UID 10000, which cannot write to a folder owned by you. `./setup.sh` detects Linux and sets this automatically; to fix it manually:

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

**Agent cannot browse the web.** No search key is configured. Re-run `./setup.sh` and pick Brave at step 4 (free tier).

---

## Security notes

This compose file is tuned for **local, single-user use**:

- `GATEWAY_ALLOW_ALL_USERS=true` authorizes every user with no allowlist.
- The dashboard binds `0.0.0.0` so `localhost:9119` is reachable.
- The API server binds to `127.0.0.1` by default. Setting `HERMES_API_SERVER_HOST=0.0.0.0` exposes it on the published port — keep `HERMES_API_SERVER_KEY` secret.

Hermes can run terminal commands. Before exposing any of this beyond your own machine, read the [security guide](https://hermes-agent.nousresearch.com/docs/user-guide/security), set `GATEWAY_ALLOW_ALL_USERS=false` with an explicit allowlist, and put a [dashboard auth provider](https://hermes-agent.nousresearch.com/docs/user-guide/features/web-dashboard) in front of the UI.

Never commit `.env`. It and its `.env.backup.*` files are gitignored, written with `600` permissions, and `.env.example` is the only one meant to be shared.

---

## Documentation

- [Hermes Agent docs](https://hermes-agent.nousresearch.com/docs/)
- [Docker guide](https://hermes-agent.nousresearch.com/docs/user-guide/docker)
- [Environment variable reference](https://hermes-agent.nousresearch.com/docs/reference/environment-variables)
- [Providers](https://hermes-agent.nousresearch.com/docs/integrations/providers)
- [GitHub](https://github.com/NousResearch/hermes-agent)