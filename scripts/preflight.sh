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
    hint 'Run the guided setup to fix this:  ./setup.sh'
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
            hint 'Run the guided setup to pick a provider and paste its key:  ./setup.sh'
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
    hint 'Run ./setup.sh to generate one automatically.'
elif [ "$API_KEY" = 'local-dev-key' ] || [ "$API_KEY" = 'change-me' ]; then
    fail "API_SERVER_KEY is still the placeholder '$API_KEY'."
    hint 'Run ./setup.sh to generate a real one automatically.'
elif [ "${#API_KEY}" -lt 16 ]; then
    fail "API_SERVER_KEY is too short (${#API_KEY} chars); the gateway requires at least 16."
    hint 'Run ./setup.sh to generate one automatically.'
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
# 4. Gateway authorization sanity check.
# ---------------------------------------------------------------------------
case "$(value_of GATEWAY_ALLOW_ALL_USERS)" in
    true|1|yes|on|TRUE|True)
        warn 'GATEWAY_ALLOW_ALL_USERS=true — every user is authorized, with no allowlist.'
        hint 'Fine for local use. Set it to false and configure an allowlist before exposing this to a network.'
        ;;
esac

# ---------------------------------------------------------------------------
# 5. The shared data directory must exist and be writable.
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
    hint 'Re-run ./setup.sh on Linux to align the container user with yours,'
    hint 'or fix ownership on the host: sudo chown -R $(id -u):$(id -g) ./hermes-data'
fi

# ---------------------------------------------------------------------------
# 6. Optional capabilities — warnings only.
# ---------------------------------------------------------------------------
if is_set BRAVE_SEARCH_API_KEY || is_set TAVILY_API_KEY || is_set EXA_API_KEY \
    || is_set SEARXNG_URL || is_set FIRECRAWL_API_KEY || is_set PARALLEL_API_KEY; then
    pass 'Web search backend configured'
else
    warn 'No web search key set; the agent cannot search the web. Add one with ./setup.sh'
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
    printf 'Hermes was not started. The quickest fix is the guided setup:\n'
    printf '\n    %s./setup.sh%s\n\n' "$C_BOLD" "$C_OFF"
    exit 1
fi

printf '%sPreflight passed%s with %s warning(s). Starting Hermes...\n\n' \
    "$C_GREEN$C_BOLD" "$C_OFF" "$WARNINGS"
exit 0
