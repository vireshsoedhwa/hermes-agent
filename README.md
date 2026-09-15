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

Everything else needed for Hermes has a default or is optional. OpenCode starts with an empty sentinel workspace; configure its password, model credential, and model route before delegating work. See `.env.example` for the full reference.

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
docker compose up -d              # start (runs preflight first)
docker compose logs -f            # follow logs
docker compose down               # stop
docker compose pull && docker compose up -d   # upgrade to the latest image

docker exec -it hermes hermes     # interactive chat in your terminal
docker compose ps                 # health status
```

To reset all data (keep `.env`):

```bash
docker compose down
find hermes-data -mindepth 1 -not -name .gitkeep -delete
```

To reset everything including `.env`:

```bash
docker compose down
find hermes-data -mindepth 1 -not -name .gitkeep -delete
rm .env
```

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

## The OpenCode worker

Hermes coordinates; it never receives the coding workspace mount. A separate OpenCode container is the only component allowed to modify project source. OpenCode receives one host-selected workspace root, which may be either one repository or a parent directory containing multiple repositories.

```text
you -> hermes (plans, writes task contracts)
          |  handoff/inbox   (hermes rw, opencode ro)
          v
       opencode (edits the selected workspace, runs tests)
          |  handoff/outbox  (opencode rw, hermes ro)
          v
       you review and promote changes
```

The empty runtime directory skeleton is committed, while its contents are gitignored. No setup script or manual scaffolding is required:

```text
agent-share/
  approved-context/   sanitized notes for planning (Hermes, read-only)
  handoff/inbox/      task contracts
  handoff/outbox/     worker results
  projects/_sentinel/ empty default workspace
```

The committed `templates/opencode.json` is mounted read-only as OpenCode's global configuration. To use a host-specific policy without editing tracked files, set `OPENCODE_POLICY_PATH` in `.env`. Configuration precedence with a repository's own `opencode.json` is version-dependent and is not a security boundary.

### Minimum OpenCode configuration

Hermes itself needs one Hermes provider credential and a `HERMES_API_SERVER_KEY` of at least 16 characters. To delegate model-backed work to OpenCode, also set a separately revocable worker credential, an API password, and a valid provider/model route:

```dotenv
OPENCODE_SERVER_PASSWORD=<generated-secret>
OPENCODE_MODEL=ollama-cloud/gpt-oss:120b
OPENCODE_OLLAMA_API_KEY=<worker-provider-key>
```

The provider identifier in `OPENCODE_MODEL` must match OpenCode's provider identifier. OpenCode credentials are deliberately separate so the worker can be rate-limited or revoked without disabling Hermes.

### Selecting a workspace

The safe default is the committed empty sentinel. Select the real workspace only in the gitignored `.env`:

```dotenv
OPENCODE_WORKSPACE_PATH=/Users/you/code-workspace
```

Use only disposable clones or working copies you intentionally permit the agent to modify. Existing installations should rename `APPROVED_PROJECT_PATH` to `OPENCODE_WORKSPACE_PATH`; `APPROVED_PROJECT_ALIAS` is no longer used.

A single-repository workspace looks like:

```text
/workspace/.git
```

A multi-repository workspace looks like:

```text
/workspace/project-a/.git
/workspace/project-b/.git
```

For a multi-repository workspace, `/workspace` itself is usually not a Git repository. Name the exact repository in every task and use commands such as:

```bash
git -C /workspace/project-a status
```

Use a fresh OpenCode session for each task. Cross-repository changes are supported when requested explicitly, but OpenCode can read and modify every repository under the mounted workspace root; prompt instructions do not provide per-repository isolation.

After changing the workspace path, recreate OpenCode so Docker applies the bind mount:

```bash
docker compose up -d --force-recreate opencode
```

OpenCode waits for preflight and Hermes health before starting. Preflight validates Hermes credentials, API server-key requirements, optional-capability warnings, and data-directory writability; it does not scan or approve the coding workspace. Hermes reaches OpenCode at `opencode:4096` on the internal `agent_control` network.

### What holds the boundary

- **No workspace mount for Hermes.** Hermes gets the handoff pair and optional sanitized notes. Read-only prevents edits, not disclosure to a remote model, so only put approved material in `approved-context/`.
- **Host-selected mount scope.** The gitignored `.env` determines the workspace root. Neither agent can change that host file.
- **An internal control network.** OpenCode's API is exposed only over the internal `agent_control` network, not through a host port.
- **A host-selected global policy.** The default policy disables sharing and denies external-directory reads, `git push`, `ssh`, `curl`, and `wget`; command patterns are convenience controls, not a sandbox.
- **Separate credentials.** The `OPENCODE_*_API_KEY` variables are independent from Hermes credentials.
- **Manual promotion.** OpenCode cannot push under the default policy; review changes on the host before promoting them.

A read-write parent workspace grants OpenCode authority over all nested repositories. Test runners execute arbitrary project code inside the container, and automatic permission approval makes `ask` a workflow mechanism rather than a safety boundary. Mount only trusted, secret-scrubbed repositories. Neither container receives the Docker socket, `privileged`, `network_mode: host`, or a home-directory mount.

---

## Security notes

This compose file is tuned for **local, single-user use**:

- `GATEWAY_ALLOW_ALL_USERS=true` authorizes every user with no allowlist.
- The dashboard binds `0.0.0.0` so `localhost:9119` is reachable.
- The API server binds to `127.0.0.1` by default. Setting `HERMES_API_SERVER_HOST=0.0.0.0` exposes it on the published port — keep `HERMES_API_SERVER_KEY` secret.

Hermes can run terminal commands. Before exposing any of this beyond your own machine, read the [security guide](https://hermes-agent.nousresearch.com/docs/user-guide/security), set `GATEWAY_ALLOW_ALL_USERS=false` with an explicit allowlist, and put a [dashboard auth provider](https://hermes-agent.nousresearch.com/docs/user-guide/features/web-dashboard) in front of the UI.

Never commit `.env`. It is gitignored, and `.env.example` is the only one meant to be shared.

---

## Documentation

- [Hermes Agent docs](https://hermes-agent.nousresearch.com/docs/)
- [Docker guide](https://hermes-agent.nousresearch.com/docs/user-guide/docker)
- [Environment variable reference](https://hermes-agent.nousresearch.com/docs/reference/environment-variables)
- [Providers](https://hermes-agent.nousresearch.com/docs/integrations/providers)
- [GitHub](https://github.com/NousResearch/hermes-agent)
