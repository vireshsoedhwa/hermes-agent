#!/bin/sh
# Preflight prerequisite check for the Hermes Agent container.
#
# Runs as a gating Compose service: `hermes` will not start unless this
# script exits 0. Fails fast with an actionable message when a required
# prerequisite is missing; optional gaps are reported as warnings only.
set -eu

ERRORS=0
WARNINGS=0

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_RED=$(printf '\033[31m')
    C_YELLOW=$(printf '\033[33m')
    C_GREEN=$(printf '\033[32m')
    C_DIM=$(printf '\033[2m')
    C_BOLD=$(printf '\033[1m')
    C_OFF=$(printf '\033[0m')
else
    C_RED='' C_YELLOW='' C_GREEN='' C_DIM='' C_BOLD='' C_OFF=''
fi

fail() {
    ERRORS=$((ERRORS + 1))
    printf '%s  FAIL%s  %s\n' "$C_RED" "$C_OFF" "$1"
}

warn() {
    WARNINGS=$((WARNINGS + 1))
    printf '%s  WARN%s  %s\n' "$C_YELLOW" "$C_OFF" "$1"
}

pass() {
    printf '%s  OK  %s  %s\n' "$C_GREEN" "$C_OFF" "$1"
}

hint() {
    printf '%s        %s%s\n' "$C_DIM" "$1" "$C_OFF"
}

# Read the value of a variable given its name (POSIX-safe indirection).
value_of() {
    eval "printf '%s' \"\${$1:-}\""
}

# A value counts as "set" only if it is non-empty and not an obvious placeholder.
is_set() {
    _v=$(value_of "$1")
    [ -n "$_v" ] || return 1
    case "$_v" in
        your_*|YOUR_*|changeme|CHANGEME|change-me|xxx|XXX|'<'*'>') return 1 ;;
    esac
    return 0
}

printf '\n%sHermes Agent preflight%s\n' "$C_BOLD" "$C_OFF"
printf '%s----------------------%s\n' "$C_DIM" "$C_OFF"

# ---------------------------------------------------------------------------
# 1. At least one LLM provider credential must be present.
# ---------------------------------------------------------------------------
PROVIDER_KEYS="OLLAMA_API_KEY OPENROUTER_API_KEY ANTHROPIC_API_KEY OPENAI_API_KEY
GOOGLE_API_KEY GEMINI_API_KEY GROQ_API_KEY GLM_API_KEY ZAI_API_KEY KIMI_API_KEY
MINIMAX_API_KEY DEEPSEEK_API_KEY XAI_API_KEY FIREWORKS_API_KEY HF_TOKEN
AI_GATEWAY_API_KEY GMI_API_KEY UPSTAGE_API_KEY KILOCODE_API_KEY XIAOMI_API_KEY"

FOUND_PROVIDERS=''
for key in $PROVIDER_KEYS; do
    if is_set "$key"; then
        FOUND_PROVIDERS="$FOUND_PROVIDERS $key"
    fi
done

if [ -n "$FOUND_PROVIDERS" ]; then
    pass "LLM provider credential found:$FOUND_PROVIDERS"
else
    fail 'No LLM provider API key is set. Hermes cannot run without a model provider.'
    hint 'Set a provider API key in .env (see .env.example).'
fi

# ---------------------------------------------------------------------------
# 2. The selected provider must have its matching credential.
# ---------------------------------------------------------------------------
PROVIDER=$(value_of HERMES_INFERENCE_PROVIDER)
if [ -n "$PROVIDER" ]; then
    case "$PROVIDER" in
        ollama-cloud) NEEDS='OLLAMA_API_KEY' ;;
        openrouter)   NEEDS='OPENROUTER_API_KEY' ;;
        anthropic)    NEEDS='ANTHROPIC_API_KEY' ;;
        openai|openai-api) NEEDS='OPENAI_API_KEY' ;;
        gemini)       NEEDS='GOOGLE_API_KEY GEMINI_API_KEY' ;;
        groq)         NEEDS='GROQ_API_KEY' ;;
        deepseek)     NEEDS='DEEPSEEK_API_KEY' ;;
        xai|grok)     NEEDS='XAI_API_KEY' ;;
        zai|glm)      NEEDS='GLM_API_KEY ZAI_API_KEY' ;;
        kimi)         NEEDS='KIMI_API_KEY' ;;
        minimax)      NEEDS='MINIMAX_API_KEY' ;;
        ai-gateway)   NEEDS='AI_GATEWAY_API_KEY' ;;
        *)            NEEDS='' ;;
    esac

    if [ -z "$NEEDS" ]; then
        pass "Provider '$PROVIDER' selected (no credential mapping to verify)"
    else
        MATCHED=''
        for key in $NEEDS; do
            if is_set "$key"; then
                MATCHED="$key"
                break
            fi
        done
        if [ -n "$MATCHED" ]; then
            pass "Provider '$PROVIDER' has its credential ($MATCHED)"
        else
            fail "HERMES_INFERENCE_PROVIDER=$PROVIDER but none of these are set: $NEEDS"
            hint 'Set the matching key in .env (see .env.example).'
        fi
    fi
else
    warn 'HERMES_INFERENCE_PROVIDER is not set; Hermes will fall back to config.yaml or auto-detection.'
fi

if is_set HERMES_DEFAULT_MODEL; then
    pass "Default model: $(value_of HERMES_DEFAULT_MODEL)"
else
    warn 'HERMES_DEFAULT_MODEL is not set; Hermes will use its built-in default.'
fi

# ---------------------------------------------------------------------------
# 3. API server key: always required (the dashboard needs the API server
#    internally for cron fires, so it cannot be disabled).
# ---------------------------------------------------------------------------
API_KEY=$(value_of API_SERVER_KEY)
if [ -z "$API_KEY" ]; then
    fail 'HERMES_API_SERVER_KEY is empty. The API server refuses to start without it.'
    hint 'Generate one with:  openssl rand -hex 32  and set HERMES_API_SERVER_KEY in .env'
elif [ "$API_KEY" = 'local-dev-key' ] || [ "$API_KEY" = 'change-me' ]; then
    fail "API_SERVER_KEY is still the placeholder '$API_KEY'."
    hint 'Generate a real one:  openssl rand -hex 32'
elif [ "${#API_KEY}" -lt 16 ]; then
    fail "API_SERVER_KEY is too short (${#API_KEY} chars); the gateway requires at least 16."
    hint 'Generate one with:  openssl rand -hex 32'
else
    pass "API server key is set (${#API_KEY} chars)"
fi

API_HOST=$(value_of API_SERVER_HOST)
if [ "$API_HOST" = '0.0.0.0' ]; then
    warn 'API_SERVER_HOST=0.0.0.0 exposes the API beyond the container. Keep HERMES_API_SERVER_KEY secret.'
else
    pass 'API server bound to loopback (default) — not reachable from the host'
fi

# ---------------------------------------------------------------------------
# 4. OpenCode worker Basic-auth credentials. OpenCode's API is only reachable
#    on the internal agent_control network, but an empty password would still
#    let any container on that network call it unauthenticated. The preflight
#    gate exists, so use it: both username and password must be non-empty.
# ---------------------------------------------------------------------------
OC_USER=$(value_of OPENCODE_SERVER_USERNAME)
OC_PASS=$(value_of OPENCODE_SERVER_PASSWORD)
if [ -z "$OC_USER" ]; then
    fail 'OPENCODE_SERVER_USERNAME is empty. OpenCode would start with no Basic-auth username.'
    hint 'Set OPENCODE_SERVER_USERNAME in .env (default is "hermes").'
else
    pass "OpenCode server username is set ($OC_USER)"
fi
if [ -z "$OC_PASS" ]; then
    fail 'OPENCODE_SERVER_PASSWORD is empty. OpenCode would start with an empty Basic-auth password.'
    hint 'Generate one with:  openssl rand -hex 32  and set OPENCODE_SERVER_PASSWORD in .env'
elif [ "${#OC_PASS}" -lt 16 ]; then
    fail "OPENCODE_SERVER_PASSWORD is too short (${#OC_PASS} chars); use at least 16."
    hint 'Generate one with:  openssl rand -hex 32'
else
    pass "OpenCode server password is set (${#OC_PASS} chars)"
fi

# ---------------------------------------------------------------------------
# 5. Gateway authorization sanity check.
# ---------------------------------------------------------------------------
case "$(value_of GATEWAY_ALLOW_ALL_USERS)" in
    true|1|yes|on|TRUE|True)
        if [ "$API_HOST" = '0.0.0.0' ]; then
            fail 'GATEWAY_ALLOW_ALL_USERS=true while API_SERVER_HOST=0.0.0.0 — the gateway is exposed to the network with no allowlist.'
            hint 'Set GATEWAY_ALLOW_ALL_USERS=false with an explicit user allowlist, or keep HERMES_API_SERVER_HOST at loopback.'
        else
            warn 'GATEWAY_ALLOW_ALL_USERS=true — every user is authorized, with no allowlist.'
            hint 'Fine for local use. Set it to false and configure an allowlist before exposing this to a network.'
        fi
        ;;
esac

# ---------------------------------------------------------------------------
# 6. The shared data directory must exist and be writable.
# ---------------------------------------------------------------------------
DATA_DIR=/data
if [ ! -d "$DATA_DIR" ]; then
    fail "Data directory is not mounted at $DATA_DIR."
    hint 'Check the volumes: entry for HERMES_DATA_DIR in docker-compose.yaml.'
elif touch "$DATA_DIR/.preflight-write-test" 2>/dev/null; then
    rm -f "$DATA_DIR/.preflight-write-test"
    pass 'Data directory is mounted and writable'
else
    fail "Data directory $DATA_DIR is not writable by the container."
    hint 'On Linux, set HERMES_UID and HERMES_GID in .env to match your user,'
    hint 'or fix ownership on the host: sudo chown -R $(id -u):$(id -g) ./hermes-data'
fi

# 6b. The agent <-> agent exchange directory is shared between Hermes and
#     OpenCode. A missing or unwritable /exchange does not block startup
#     (it is a convenience channel, not core runtime state), so warn only.
EXCHANGE_DIR=/exchange
if [ ! -d "$EXCHANGE_DIR" ]; then
    warn "Exchange directory is not mounted at $EXCHANGE_DIR."
    hint 'Agent <-> agent file exchange will be unavailable until AGENT_SHARED_DIR is mounted.'
elif touch "$EXCHANGE_DIR/.preflight-write-test" 2>/dev/null; then
    rm -f "$EXCHANGE_DIR/.preflight-write-test"
    pass 'Exchange directory is mounted and writable'
else
    warn "Exchange directory $EXCHANGE_DIR is not writable by the container."
    hint 'On Linux, match HERMES_UID/HERMES_GID so both containers can write /exchange.'
fi

# ---------------------------------------------------------------------------
# 6c. OpenCode workspace — fail on catastrophically broad paths; warn on
#     secret-looking files. Convenience only: scrub secrets before mounting,
#     and only mount disposable repositories.
# ---------------------------------------------------------------------------
OC_WS=$(value_of OPENCODE_WORKSPACE_PATH)
case "$OC_WS" in
    /|/Users|/Users/|/home|/home/|/root|/root/|/etc|/var|/tmp|/tmp/)
        fail "OPENCODE_WORKSPACE_PATH='$OC_WS' is a system root; never mount it into OpenCode."
        hint 'Point OPENCODE_WORKSPACE_PATH at a dedicated disposable clone.'
        ;;
esac

WS_DIR=/workspace
if [ -d "$WS_DIR" ]; then
    SECRET_HITS=$(find "$WS_DIR" -maxdepth 3 -type f \( \
        -name '.env' -o -name '.env.local' -o -name '.env.*.local' \
        -o -name '*.pem' -o -name '*.key' \
        -o -name 'id_rsa' -o -name 'id_ed25519' -o -name 'id_ecdsa' \
        -o -name '*.ppk' \) 2>/dev/null)
    if [ -n "$SECRET_HITS" ]; then
        warn 'Potential secret files found in the OpenCode workspace:'
        printf '%s\n' "$SECRET_HITS" | sed 's/^/        /'
        hint 'Scrub or remove secrets before mounting; OpenCode can read everything under /workspace.'
    else
        pass 'No obvious secret files in the OpenCode workspace (shallow scan)'
    fi
else
    warn 'OpenCode workspace not mounted into preflight; skipping secret scan.'
    hint 'Set OPENCODE_WORKSPACE_PATH in .env and ensure the bind mount is applied.'
fi

# ---------------------------------------------------------------------------
# 7. Optional capabilities — warnings only.
# ---------------------------------------------------------------------------
if is_set BRAVE_SEARCH_API_KEY || is_set TAVILY_API_KEY || is_set EXA_API_KEY \
    || is_set SEARXNG_URL || is_set FIRECRAWL_API_KEY || is_set PARALLEL_API_KEY; then
    pass 'Web search backend configured'
else
    warn 'No web search key set; the agent cannot search the web. Add one to .env.'
fi

MESSAGING=''
for key in TELEGRAM_BOT_TOKEN DISCORD_BOT_TOKEN SLACK_BOT_TOKEN MATRIX_ACCESS_TOKEN \
    MATTERMOST_TOKEN SIGNAL_PHONE_NUMBER; do
    if is_set "$key"; then
        MESSAGING="$MESSAGING $key"
    fi
done
if [ -n "$MESSAGING" ]; then
    pass "Messaging platform configured:$MESSAGING"
else
    warn 'No messaging platform token set; reach Hermes via the dashboard on port 9119 or docker exec.'
fi

if is_set ELEVENLABS_API_KEY || is_set GROQ_API_KEY; then
    pass 'Voice / speech-to-text backend available'
else
    warn 'No ELEVENLABS_API_KEY or GROQ_API_KEY; voice mode and audio transcription are unavailable.'
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
printf '%s----------------------%s\n' "$C_DIM" "$C_OFF"
if [ "$ERRORS" -gt 0 ]; then
    printf '%sPreflight failed: %s error(s), %s warning(s).%s\n' \
        "$C_RED$C_BOLD" "$ERRORS" "$WARNINGS" "$C_OFF"
    printf 'Hermes was not started. Check the errors above, edit .env, and re-run:\n'
    printf '\n    %sdocker compose up -d%s\n\n' "$C_BOLD" "$C_OFF"
    exit 1
fi

printf '%sPreflight passed%s with %s warning(s). Starting Hermes...\n\n' \
    "$C_GREEN$C_BOLD" "$C_OFF" "$WARNINGS"
exit 0
