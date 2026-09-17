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

Everything else needed for Hermes has a default or is optional. OpenCode starts with the empty `opencode-workspace/` fallback; configure its password, model credential, model route, and coding workspace before delegating work. See `.env.example` for the full reference.

---

## Repository layout

| Folder | Purpose |
| --- | --- |
| `hermes-data/` | Persistent Hermes runtime state. It is mounted at `/opt/data` in the Hermes container and at `/data` in preflight. Conversations, memory, learned skills, configuration, and logs live here. Runtime contents are gitignored; `.gitkeep` only preserves the empty folder in a fresh clone. Back up this folder to preserve Hermes state. |
| `hermes-shared/` | Explicit host ↔ Hermes file exchange. It is mounted read-write at `/shared` in the Hermes container. Put documents here when you want Hermes to read them, and let Hermes write exports here. It is not mounted into OpenCode, and its runtime contents are gitignored. |
| `agent-shared/` | Agent ↔ agent file exchange, mounted read-write at `/exchange` in Hermes, OpenCode, and preflight. It is the only path OpenCode is allowed to touch outside its `/workspace` (gated by a scoped `external_directory` rule in `templates/opencode.json`). Runtime contents are gitignored; `.gitkeep` only preserves the empty folder in a fresh clone. |
| `opencode-workspace/` | Empty, safe fallback mounted at `/workspace` in OpenCode when `OPENCODE_WORKSPACE_PATH` is not set. It lets the stack start before a real coding workspace is selected. Runtime contents are gitignored; do not use it as a primary checkout. |
| `scripts/` | Tracked host-side/container support scripts. `preflight.sh` is mounted read-only into the preflight container and validates Hermes credentials, API server-key requirements, optional-capability settings, and data-directory and exchange-directory writability before startup. |
| `templates/` | Tracked reusable OpenCode configuration. `opencode.json` is the default read-only global policy mounted into OpenCode. `projects.allowlist.example` is a deprecated migration artifact and is not consumed by Compose or any script. |

The real OpenCode coding workspace normally lives **outside this repository** and is selected through the gitignored `.env` file:

```dotenv
OPENCODE_WORKSPACE_PATH=/Users/you/code-workspace
```

That host directory is mounted read-write at `/workspace` only in OpenCode. It may contain one repository or multiple nested repositories. Hermes never receives this mount.

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

Back up this directory to preserve Hermes runtime state. A complete migration also requires securely recreating the machine's gitignored `.env` credentials and settings. OpenCode session state is stored separately in the Docker named volume `opencode_state`, and project files remain in the host directory selected by `OPENCODE_WORKSPACE_PATH`.

A separate host directory is mounted into Hermes at `/shared` for files you want Hermes to read:

```dotenv
HERMES_SHARED_DIR=./hermes-shared
```

The default is `./hermes-shared`; an absolute path also works. Hermes can read and write this explicit exchange directory, but it never receives the OpenCode workspace mount.

A second host directory is mounted into BOTH Hermes and OpenCode at `/exchange` for agent ↔ agent file exchange:

```dotenv
AGENT_SHARED_DIR=./agent-shared
```

The default is `./agent-shared`; an absolute path also works. Both containers can read and write `/exchange`. It is the only path OpenCode is permitted to touch outside its `/workspace` — the scoped `external_directory` rule in `templates/opencode.json` denies every other external path. Preflight warns (but does not block startup) if `/exchange` is missing or unwritable.

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

A normal `docker compose down` preserves OpenCode's named session volume. To permanently reset that state too:

```bash
docker compose down -v
```

The `-v` option deletes this Compose project's named volumes; it does not delete bind-mounted Hermes data, shared files, or workspace repositories. Remove `.env` separately only when you also intend to discard the local credentials and settings.

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

Hermes coordinates over OpenCode's authenticated HTTP API; it never receives the coding workspace mount. A separate OpenCode container is the only component allowed to modify project source. OpenCode receives one host-selected workspace root, which may be either one repository or a parent directory containing multiple repositories.

```text
you -> hermes (plans and verifies)
          |  authenticated internal HTTP API
          v
       opencode (edits the selected workspace, runs tests)
          |  session messages and diffs over the API
          v
       hermes -> you review and promote changes
```

No filesystem handoff or `agent-share` directory is required. The committed empty `opencode-workspace/` directory is the safe default workspace, and its runtime contents are gitignored. The committed `templates/opencode.json` is mounted read-only as OpenCode's global configuration. To use a host-specific policy without editing tracked files, set `OPENCODE_POLICY_PATH` in `.env`. Configuration precedence with a repository's own `opencode.json` is version-dependent and is not a security boundary.

### Minimum OpenCode configuration

Hermes itself needs one Hermes provider credential and a `HERMES_API_SERVER_KEY` of at least 16 characters. To delegate model-backed work to OpenCode, also set a separately revocable worker credential, an API password, and a valid provider/model route:

```dotenv
OPENCODE_SERVER_PASSWORD=<generated-secret>
OPENCODE_MODEL=ollama-cloud/gpt-oss:120b
OPENCODE_OLLAMA_API_KEY=<worker-provider-key>
```

The provider identifier in `OPENCODE_MODEL` must match OpenCode's provider identifier. OpenCode credentials are deliberately separate so the worker can be rate-limited or revoked without disabling Hermes.

### Selecting a workspace

The safe default is the committed empty `./opencode-workspace` directory. Select the real workspace only in the gitignored `.env`:

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

### Verifying OpenCode results

Hermes has no workspace mount, so it cannot run tests or inspect the project tree directly. It verifies OpenCode's work through two in-container channels that stay off the host:

1. **Session messages over the API.** OpenCode returns diffs, tool outputs, and exit codes in the session messages Hermes reads through the authenticated `/prompt_async` and `/file/content` endpoints on `agent_control`.
2. **A verify artifact at `/exchange/verify.json`.** After completing a task, OpenCode writes a structured verification report to `/exchange/verify.json` (the shared agent↔agent directory). Hermes reads it and treats any non-zero exit code or `passed: false` as a failure.

Convention for `/exchange/verify.json`:

```json
{
  "task": "short description of the requested change",
  "timestamp": "2026-09-16T20:51:10Z",
  "commands": [
    {
      "command": "npm test",
      "exit_code": 0,
      "duration_ms": 1234,
      "output_tail": "last lines of stdout/stderr"
    }
  ],
  "passed": true,
  "files_changed": ["src/foo.ts", "src/foo.test.ts"],
  "notes": "optional free-text summary"
}
```

To keep the verification loop low-friction, the default policy allow-lists common test, lint, typecheck, and build commands so OpenCode runs them without a per-command approval round-trip to Hermes. The allow-list is scoped to recognised test/lint/typecheck/build invocations across Node, Python, Go, Rust, Make, Maven, Gradle, .NET, Ruby, and Elixir projects; everything else still falls through to `"*": "ask"`. Destructive and exfiltration commands (`rm -rf *`, `git push*`, `ssh *`, `scp *`, `curl *`, `wget *`) remain denied. See `templates/opencode.json` for the full list.

This trust is concrete but not independent: Hermes is reading OpenCode's self-reported results, not re-executing the tests. Test runners execute arbitrary project code inside the OpenCode container (an accepted capability boundary, see below), so the boundary that actually holds is container isolation, not the command allow-list. Treat host-side CI as the real promotion gate — the default policy denies `git push` so changes are reviewed on the host before merging.

### What holds the boundary

- **No workspace mount for Hermes.** Hermes delegates and collects results through the internal OpenCode API; only OpenCode receives the host coding workspace.
- **Host-selected mount scope.** The gitignored `.env` determines the workspace root. Neither agent can change that host file.
- **An internal control network.** OpenCode's API is exposed only over the internal `agent_control` network, not through a host port.
- **A host-selected global policy.** The default policy disables sharing, denies external-directory access except for the scoped `/exchange` agent-exchange channel, denies `git push`, `ssh`, `curl`, and `wget`, and allow-lists common test/lint/typecheck/build commands so OpenCode can verify its own work without a per-command approval round-trip. Command patterns are convenience controls, not a sandbox.
- **Separate credentials.** The `OPENCODE_*_API_KEY` variables are independent from Hermes credentials.
- **Manual promotion.** The default policy denies direct `git push` shell requests. Review changes on the host before promoting them, but do not treat command patterns as a complete exfiltration boundary.

A read-write parent workspace grants OpenCode authority over all nested repositories. Test runners execute arbitrary project code inside the container, and automatic permission approval makes `ask` a workflow mechanism rather than a safety boundary. Mount only trusted, secret-scrubbed repositories.

The default configuration gives neither container the Docker socket, `privileged`, `network_mode: host`, a host home-directory mount, nor a `host.docker.internal` route. Hermes drops all Linux capabilities (except the few its s6 supervisor needs) and its image is pinned to a digest (not floating `:latest`). Host path variables are operator-controlled; preflight fails on system-root workspace paths and warns on secret-like files, but does not fully validate them: never set `OPENCODE_WORKSPACE_PATH`, `HERMES_DATA_DIR`, `HERMES_SHARED_DIR`, or `AGENT_SHARED_DIR` to your home directory or another unnecessarily broad path.

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
