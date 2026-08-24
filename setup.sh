#!/bin/sh
# Interactive first-run setup for the Hermes Agent Docker deployment.
#
# Asks a short series of questions and writes the answers to `.env`, so the
# user never has to hand-edit a configuration file. Safe to re-run at any
# time: the existing `.env` is backed up before being replaced.
set -eu

ENV_FILE=.env
EXAMPLE_FILE=.env.example

if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_BOLD=$(printf '\033[1m')
    C_DIM=$(printf '\033[2m')
    C_CYAN=$(printf '\033[36m')
    C_GREEN=$(printf '\033[32m')
    C_YELLOW=$(printf '\033[33m')
    C_RED=$(printf '\033[31m')
    C_OFF=$(printf '\033[0m')
else
    C_BOLD='' C_DIM='' C_CYAN='' C_GREEN='' C_YELLOW='' C_RED='' C_OFF=''
fi

# ---------------------------------------------------------------------------
# Presentation helpers
# ---------------------------------------------------------------------------
STEP_NUM=0
TOTAL_STEPS=6

step() {
    STEP_NUM=$((STEP_NUM + 1))
    printf '\n%s[%s/%s] %s%s\n' "$C_CYAN$C_BOLD" "$STEP_NUM" "$TOTAL_STEPS" "$1" "$C_OFF"
    printf '%s%s%s\n' "$C_DIM" '--------------------------------------------------------------' "$C_OFF"
}

note()    { printf '%s%s%s\n' "$C_DIM" "$1" "$C_OFF"; }
ok()      { printf '%s  ok%s %s\n' "$C_GREEN" "$C_OFF" "$1"; }
warn()    { printf '%swarn%s %s\n' "$C_YELLOW" "$C_OFF" "$1"; }
die()     { printf '\n%serror%s %s\n\n' "$C_RED" "$C_OFF" "$1" >&2; exit 1; }

# Trim leading/trailing whitespace from $1.
trim() {
    printf '%s' "$1" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

# Show a secret as ****last4 so the user can confirm a paste without exposing it.
mask() {
    _m_len=${#1}
    if [ "$_m_len" -le 4 ]; then
        printf '****'
    else
        printf '%s%s' '****' "$(printf '%s' "$1" | tail -c 4)"
    fi
}

# ask_secret "Prompt" -> sets ANSWER. Input is hidden while typing.
ask_secret() {
    printf '%s' "$1"
    _saved_stty=''
    if [ -t 0 ]; then
        _saved_stty=$(stty -g 2>/dev/null || true)
        stty -echo 2>/dev/null || true
    fi
    IFS= read -r ANSWER || ANSWER=''
    if [ -n "$_saved_stty" ]; then
        stty "$_saved_stty" 2>/dev/null || true
    fi
    printf '\n'
    ANSWER=$(trim "$ANSWER")
}

# ask_text "Prompt" "default" -> sets ANSWER
ask_text() {
    if [ -n "$2" ]; then
        printf '%s %s[%s]%s: ' "$1" "$C_DIM" "$2" "$C_OFF"
    else
        printf '%s: ' "$1"
    fi
    IFS= read -r ANSWER || ANSWER=''
    ANSWER=$(trim "$ANSWER")
    [ -n "$ANSWER" ] || ANSWER="$2"
}

# ask_yes_no "Prompt" "y|n" -> returns 0 for yes, 1 for no
ask_yes_no() {
    while :; do
        if [ "$2" = y ]; then
            printf '%s %s[Y/n]%s: ' "$1" "$C_DIM" "$C_OFF"
        else
            printf '%s %s[y/N]%s: ' "$1" "$C_DIM" "$C_OFF"
        fi
        IFS= read -r _yn || _yn=''
        _yn=$(trim "$_yn")
        [ -n "$_yn" ] || _yn="$2"
        case "$_yn" in
            y|Y|yes|YES|Yes) return 0 ;;
            n|N|no|NO|No)    return 1 ;;
            *) printf '%sPlease answer y or n.%s\n' "$C_YELLOW" "$C_OFF" ;;
        esac
    done
}

# ask_choice max -> sets CHOICE to a number in 1..max
ask_choice() {
    while :; do
        printf 'Enter a number %s[1-%s]%s: ' "$C_DIM" "$1" "$C_OFF"
        IFS= read -r CHOICE || CHOICE=''
        CHOICE=$(trim "$CHOICE")
        case "$CHOICE" in
            ''|*[!0-9]*) ;;
            *) if [ "$CHOICE" -ge 1 ] && [ "$CHOICE" -le "$1" ]; then return 0; fi ;;
        esac
        printf '%sPlease enter a number between 1 and %s.%s\n' "$C_YELLOW" "$1" "$C_OFF"
    done
}

# ---------------------------------------------------------------------------
# Banner
# ---------------------------------------------------------------------------
printf '\n%s================================================================%s\n' "$C_BOLD" "$C_OFF"
printf '%s  Hermes Agent - setup%s\n' "$C_BOLD" "$C_OFF"
printf '%s================================================================%s\n' "$C_BOLD" "$C_OFF"
note 'Answer a few questions and this writes your .env for you.'
note 'Press Enter to accept the [default] shown in brackets.'

[ -f "$EXAMPLE_FILE" ] || die "$EXAMPLE_FILE not found. Run this from the repository root."

if ! command -v docker >/dev/null 2>&1; then
    printf '\n'
    die 'Docker is required but was not found on your PATH.

    Install Docker Desktop from https://docker.com, then re-run ./setup.sh'
fi

if [ -f "$ENV_FILE" ]; then
    printf '\n'
    warn "An existing $ENV_FILE was found."
    if ! ask_yes_no 'Reconfigure from scratch? (a timestamped backup will be kept)' n; then
        note 'Keeping your existing configuration. Nothing changed.'
        printf '\nStart Hermes with: %sdocker compose up -d%s\n\n' "$C_BOLD" "$C_OFF"
        exit 0
    fi
    BACKUP="$ENV_FILE.backup.$(date +%Y%m%d-%H%M%S)"
    cp "$ENV_FILE" "$BACKUP"
    ok "Backed up to $BACKUP"
fi

# ---------------------------------------------------------------------------
# Step 1 - LLM provider
# ---------------------------------------------------------------------------
step 'Choose your AI model provider'
note 'Hermes needs one provider to think. Ollama Cloud is the easiest start:'
note 'hosted open models, no GPU required, generous free tier.'
printf '\n'
printf '  1) Ollama Cloud   %shosted open models, no GPU needed%s\n'  "$C_DIM" "$C_OFF"
printf '  2) OpenRouter     %sone key, 300+ models from every lab%s\n' "$C_DIM" "$C_OFF"
printf '  3) Anthropic      %sClaude models, direct%s\n'              "$C_DIM" "$C_OFF"
printf '  4) OpenAI         %sGPT models, direct%s\n'                 "$C_DIM" "$C_OFF"
printf '  5) Google Gemini  %sfree tier available%s\n'                "$C_DIM" "$C_OFF"
printf '  6) Groq           %svery fast inference%s\n'                "$C_DIM" "$C_OFF"
printf '  7) DeepSeek       %slow cost%s\n'                           "$C_DIM" "$C_OFF"
printf '  8) xAI (Grok)     %s%s\n'                                   "$C_DIM" "$C_OFF"
printf '\n'
ask_choice 8

case "$CHOICE" in
    1) PROVIDER=ollama-cloud; KEY_VAR=OLLAMA_API_KEY;     KEY_URL='https://ollama.com/settings/keys'
       DEFAULT_MODEL='gpt-oss:120b' ;;
    2) PROVIDER=openrouter;   KEY_VAR=OPENROUTER_API_KEY; KEY_URL='https://openrouter.ai/keys'
       DEFAULT_MODEL='anthropic/claude-sonnet-4.6' ;;
    3) PROVIDER=anthropic;    KEY_VAR=ANTHROPIC_API_KEY;  KEY_URL='https://console.anthropic.com/settings/keys'
       DEFAULT_MODEL='claude-sonnet-4-6' ;;
    4) PROVIDER=openai;       KEY_VAR=OPENAI_API_KEY;     KEY_URL='https://platform.openai.com/api-keys'
       DEFAULT_MODEL='gpt-5.5' ;;
    5) PROVIDER=gemini;       KEY_VAR=GOOGLE_API_KEY;     KEY_URL='https://aistudio.google.com/app/apikey'
       DEFAULT_MODEL='gemini-2.5-flash' ;;
    6) PROVIDER=groq;         KEY_VAR=GROQ_API_KEY;       KEY_URL='https://console.groq.com/keys'
       DEFAULT_MODEL='llama-3.3-70b-versatile' ;;
    7) PROVIDER=deepseek;     KEY_VAR=DEEPSEEK_API_KEY;   KEY_URL='https://platform.deepseek.com/api_keys'
       DEFAULT_MODEL='deepseek-chat' ;;
    8) PROVIDER=xai;          KEY_VAR=XAI_API_KEY;        KEY_URL='https://console.x.ai'
       DEFAULT_MODEL='grok-4' ;;
esac
MODEL="$DEFAULT_MODEL"

printf '\n'
note "Get a $KEY_VAR here:"
printf '  %s%s%s\n\n' "$C_CYAN" "$KEY_URL" "$C_OFF"

while :; do
    ask_secret "Paste your $KEY_VAR (hidden): "
    PROVIDER_KEY="$ANSWER"
    if [ -z "$PROVIDER_KEY" ]; then
        warn 'A provider key is required - Hermes cannot run without one.'
        continue
    fi
    if [ "${#PROVIDER_KEY}" -lt 8 ]; then
        warn "That looks too short (${#PROVIDER_KEY} characters). Please check and paste again."
        continue
    fi
    break
done
ok "$KEY_VAR set to $(mask "$PROVIDER_KEY")"

# ---------------------------------------------------------------------------
# Step 2 - API server key and external access
# ---------------------------------------------------------------------------
step 'API server key'
note 'Hermes runs an OpenAI-compatible API on port 8642. The dashboard needs'
note 'it internally, so it always runs — but it binds to 127.0.0.1 by default,'
note 'meaning external apps cannot reach it. You can optionally expose it.'
printf '\n'
note 'A dashboard login password is also generated — the web UI requires'
note 'auth when binding to 0.0.0.0 (needed for Docker port publishing).'
printf '\n'

# Always generate a key — the gateway refuses to start the API server without one.
API_KEY=''
if command -v openssl >/dev/null 2>&1; then
    API_KEY=$(openssl rand -hex 32 2>/dev/null || true)
fi
if [ -z "$API_KEY" ] && [ -r /dev/urandom ]; then
    API_KEY=$(od -An -tx1 -N32 /dev/urandom 2>/dev/null | tr -d ' \n' || true)
fi
if [ -z "$API_KEY" ]; then
    warn 'Could not generate a key automatically.'
    while :; do
        ask_secret 'Enter an API key of at least 16 characters (hidden): '
        API_KEY="$ANSWER"
        [ "${#API_KEY}" -ge 16 ] && break
        warn 'Too short - please use at least 16 characters.'
    done
fi
ok "Generated a ${#API_KEY}-character API server key"
note 'API server is loopback-only (127.0.0.1). The dashboard and CLI work normally.'
note 'To expose it externally, set HERMES_API_SERVER_HOST=0.0.0.0 in .env.'

API_HOST=127.0.0.1

# Generate a random dashboard password (16 chars, alphanumeric).
DASH_PASS=''
if command -v openssl >/dev/null 2>&1; then
    DASH_PASS=$(openssl rand -base64 12 2>/dev/null | tr -d '/+=' | head -c 16 || true)
fi
if [ -z "$DASH_PASS" ] && [ -r /dev/urandom ]; then
    DASH_PASS=$(od -An -tu1 -N12 /dev/urandom 2>/dev/null | tr -d ' ' | head -c 16 || true)
fi
if [ -z "$DASH_PASS" ]; then
    DASH_PASS="hermes$(date +%s)"
fi
ok "Generated dashboard password: $DASH_PASS"
note 'You will need this to log in at http://localhost:9119'
note 'Re-run ./setup.sh to regenerate it.'

# ---------------------------------------------------------------------------
# Step 3 - Web search (optional)
# ---------------------------------------------------------------------------
step 'Web search (optional)'
note 'Without this the agent cannot look things up online. Brave has a free tier.'
printf '\n'
printf '  1) Brave Search   %sfree tier - recommended%s\n' "$C_DIM" "$C_OFF"
printf '  2) Tavily         %sbuilt for LLMs%s\n'          "$C_DIM" "$C_OFF"
printf '  3) Exa            %ssemantic search%s\n'         "$C_DIM" "$C_OFF"
printf '  4) %sSkip for now%s\n'                           "$C_DIM" "$C_OFF"
printf '\n'
ask_choice 4

SEARCH_VAR='' SEARCH_KEY=''
case "$CHOICE" in
    1) SEARCH_VAR=BRAVE_SEARCH_API_KEY; SEARCH_URL='https://brave.com/search/api/' ;;
    2) SEARCH_VAR=TAVILY_API_KEY;       SEARCH_URL='https://app.tavily.com/home' ;;
    3) SEARCH_VAR=EXA_API_KEY;          SEARCH_URL='https://exa.ai' ;;
    4) note 'Skipped. Add a search key later by re-running ./setup.sh' ;;
esac

if [ -n "$SEARCH_VAR" ]; then
    printf '\n'
    note "Get a $SEARCH_VAR here:"
    printf '  %s%s%s\n\n' "$C_CYAN" "$SEARCH_URL" "$C_OFF"
    ask_secret "Paste your $SEARCH_VAR (hidden, Enter to skip): "
    SEARCH_KEY="$ANSWER"
    if [ -n "$SEARCH_KEY" ]; then
        ok "$SEARCH_VAR set to $(mask "$SEARCH_KEY")"
    else
        note 'Skipped.'
        SEARCH_VAR=''
    fi
fi

# ---------------------------------------------------------------------------
# Step 4 - Chat platform (optional)
# ---------------------------------------------------------------------------
step 'Chat platform (optional)'
note 'Message Hermes from your phone. You can always use the web dashboard instead.'
printf '\n'
printf '  1) Telegram  %screate a bot with @BotFather%s\n' "$C_DIM" "$C_OFF"
printf '  2) Discord   %s%s\n'                             "$C_DIM" "$C_OFF"
printf '  3) Slack     %s%s\n'                             "$C_DIM" "$C_OFF"
printf '  4) %sSkip - use the dashboard at localhost:9119%s\n' "$C_DIM" "$C_OFF"
printf '\n'
ask_choice 4

CHAT_VAR='' CHAT_KEY=''
case "$CHOICE" in
    1) CHAT_VAR=TELEGRAM_BOT_TOKEN; CHAT_URL='https://t.me/BotFather' ;;
    2) CHAT_VAR=DISCORD_BOT_TOKEN;  CHAT_URL='https://discord.com/developers/applications' ;;
    3) CHAT_VAR=SLACK_BOT_TOKEN;    CHAT_URL='https://api.slack.com/apps' ;;
    4) note 'Skipped. The web dashboard and API server are always available.' ;;
esac

if [ -n "$CHAT_VAR" ]; then
    printf '\n'
    note "Create your bot and get a $CHAT_VAR here:"
    printf '  %s%s%s\n\n' "$C_CYAN" "$CHAT_URL" "$C_OFF"
    ask_secret "Paste your $CHAT_VAR (hidden, Enter to skip): "
    CHAT_KEY="$ANSWER"
    if [ -n "$CHAT_KEY" ]; then
        ok "$CHAT_VAR set to $(mask "$CHAT_KEY")"
    else
        note 'Skipped.'
        CHAT_VAR=''
    fi
fi

# ---------------------------------------------------------------------------
# Step 5 - Data folder
# ---------------------------------------------------------------------------
step 'Where should Hermes keep its data?'
note 'One folder holds everything: config, chat history, memory, learned skills'
note 'and logs. Back up this folder and you have backed up your whole agent.'
printf '\n'
ask_text 'Data folder' './hermes-data'
DATA_DIR="$ANSWER"

if [ ! -d "$DATA_DIR" ]; then
    if ask_yes_no "$DATA_DIR does not exist. Create it?" y; then
        mkdir -p "$DATA_DIR" || die "Could not create $DATA_DIR"
        ok "Created $DATA_DIR"
    fi
else
    ok "Using $DATA_DIR"
fi

# On Linux, align the container user with the host user so the shared folder
# stays editable. Docker Desktop on macOS/Windows handles this already.
UID_LINE='# HERMES_UID=1000'
GID_LINE='# HERMES_GID=1000'
if [ "$(uname -s)" = Linux ] && command -v id >/dev/null 2>&1; then
    UID_LINE="HERMES_UID=$(id -u)"
    GID_LINE="HERMES_GID=$(id -g)"
    note "Linux detected - matching container user to yours ($(id -u):$(id -g))."
fi

# ---------------------------------------------------------------------------
# Write dashboard basic_auth into config.yaml
# ---------------------------------------------------------------------------
# The dashboard refuses to bind to 0.0.0.0 without an auth provider.
# We generate a scrypt hash using the Hermes container's Python and inject
# it into config.yaml so the dashboard starts cleanly on first boot.
CONFIG_FILE="$DATA_DIR/config.yaml"
if command -v docker >/dev/null 2>&1; then
    note 'Generating dashboard password hash...'
    DASH_HASH=$(docker run --rm --entrypoint python nousresearch/hermes-agent:latest \
        -c "from plugins.dashboard_auth.basic import hash_password; print(hash_password('$DASH_PASS'))" \
        2>/dev/null || true)
    if [ -n "$DASH_HASH" ]; then
        if [ -f "$CONFIG_FILE" ]; then
            # Remove any existing dashboard: block and append fresh one.
            # Use sed to delete from 'dashboard:' to the next top-level key.
            sed -i.bak '/^dashboard:/,/^[^ #]/{/^dashboard:/d; /^  basic_auth:/d; /^    username:/d; /^    password_hash:/d; /^$/d;}' "$CONFIG_FILE" 2>/dev/null || true
        fi
        {
            printf '\ndashboard:\n'
            printf '  basic_auth:\n'
            printf '    username: admin\n'
            printf '    password_hash: "%s"\n' "$DASH_HASH"
        } >> "$CONFIG_FILE"
        ok 'Dashboard auth configured in config.yaml'
    else
        warn 'Could not generate password hash (Docker failed).'
        warn "Add this to $CONFIG_FILE manually:"
        printf '  dashboard:\n'
        printf '    basic_auth:\n'
        printf '      username: admin\n'
        printf '      password_hash: <run docker to generate hash for password: %s>\n' "$DASH_PASS"
    fi
else
    warn 'Docker not found — cannot generate dashboard password hash.'
    warn "After installing Docker, run ./setup.sh again, or manually add to $CONFIG_FILE:"
    printf '  dashboard:\n'
    printf '    basic_auth:\n'
    printf '      username: admin\n'
    printf '      password_hash: <generated by Hermes container>\n'
fi

# ---------------------------------------------------------------------------
# Write .env
# ---------------------------------------------------------------------------
printf '\n%s%s%s\n' "$C_DIM" '--------------------------------------------------------------' "$C_OFF"

emit_key() {
    # emit_key VAR VALUE  -> always writes the line, value may be empty
    printf '%s=%s\n' "$1" "$2"
}

{
    printf '# Generated by ./setup.sh on %s\n' "$(date '+%Y-%m-%d %H:%M:%S')"
    printf '# Re-run ./setup.sh at any time to change these answers.\n'
    printf '# Reference for every supported option: .env.example\n\n'

    printf '# --- API server (OpenAI-compatible endpoint on port 8642) -----------\n'
    printf '# Loopback by default. Set HERMES_API_SERVER_HOST=0.0.0.0 to expose.\n'
    emit_key HERMES_API_SERVER_HOST "$API_HOST"
    emit_key HERMES_API_SERVER_KEY "$API_KEY"
    printf '\n'

    printf '# --- Model ----------------------------------------------------------\n'
    emit_key HERMES_INFERENCE_PROVIDER "$PROVIDER"
    emit_key HERMES_DEFAULT_MODEL "$MODEL"
    printf '\n'

    printf '# --- Provider credentials -------------------------------------------\n'
    for v in OLLAMA_API_KEY OPENROUTER_API_KEY ANTHROPIC_API_KEY OPENAI_API_KEY \
             GOOGLE_API_KEY GROQ_API_KEY DEEPSEEK_API_KEY XAI_API_KEY; do
        if [ "$v" = "$KEY_VAR" ]; then
            emit_key "$v" "$PROVIDER_KEY"
        else
            emit_key "$v" ''
        fi
    done
    printf '\n'

    printf '# --- Web search -----------------------------------------------------\n'
    for v in BRAVE_SEARCH_API_KEY TAVILY_API_KEY EXA_API_KEY; do
        if [ "$v" = "$SEARCH_VAR" ]; then
            emit_key "$v" "$SEARCH_KEY"
        else
            emit_key "$v" ''
        fi
    done
    printf '\n'

    printf '# --- Chat platforms -------------------------------------------------\n'
    for v in TELEGRAM_BOT_TOKEN DISCORD_BOT_TOKEN SLACK_BOT_TOKEN; do
        if [ "$v" = "$CHAT_VAR" ]; then
            emit_key "$v" "$CHAT_KEY"
        else
            emit_key "$v" ''
        fi
    done
    printf '\n'

    printf '# --- Voice / transcription (optional) -------------------------------\n'
    emit_key ELEVENLABS_API_KEY ''
    printf '\n'

    printf '# --- Storage --------------------------------------------------------\n'
    emit_key HERMES_DATA_DIR "$DATA_DIR"
    printf '\n'

    printf '# --- Linux file ownership -------------------------------------------\n'
    printf '%s\n' "$UID_LINE"
    printf '%s\n' "$GID_LINE"
} > "$ENV_FILE"

chmod 600 "$ENV_FILE" 2>/dev/null || true
ok "Wrote $ENV_FILE (permissions 600, and it is gitignored)"

# ---------------------------------------------------------------------------
# Summary and launch
# ---------------------------------------------------------------------------
printf '\n%s================================================================%s\n' "$C_BOLD" "$C_OFF"
printf '%s  Setup complete%s\n' "$C_GREEN$C_BOLD" "$C_OFF"
printf '%s================================================================%s\n\n' "$C_BOLD" "$C_OFF"
printf '  Provider     %s\n' "$PROVIDER"
printf '  Model        %s (change via dashboard)\n' "$MODEL"
if [ "$API_HOST" = "0.0.0.0" ]; then
    printf '  API server   port 8642 (external)\n'
else
    printf '  API server   port 8642 (loopback only)\n'
fi
printf '  Dashboard   %shttp://localhost:9119%s\n' "$C_CYAN" "$C_OFF"
printf '  Login       %sadmin / %s%s\n' "$C_BOLD" "$DASH_PASS" "$C_OFF"
printf '  Web search   %s\n' "${SEARCH_VAR:-none}"
printf '  Chat         %s\n' "${CHAT_VAR:-dashboard only}"
printf '  Data folder  %s\n' "$DATA_DIR"

printf '\n'
if ask_yes_no 'Start Hermes now?' y; then
    printf '\n'
    note 'Running: docker compose up -d'
    printf '\n'
    if docker compose up -d; then
        printf '\n%sHermes is starting.%s\n\n' "$C_GREEN$C_BOLD" "$C_OFF"
        printf '  Dashboard  %shttp://localhost:9119%s\n' "$C_CYAN" "$C_OFF"
        printf '  Login      %sadmin / %s%s\n' "$C_BOLD" "$DASH_PASS" "$C_OFF"
        if [ "$API_HOST" = "0.0.0.0" ]; then
            printf '  API        %shttp://localhost:8642/v1%s\n' "$C_CYAN" "$C_OFF"
        fi
        printf '  Logs       %sdocker compose logs -f%s\n' "$C_BOLD" "$C_OFF"
        printf '  Terminal   %sdocker exec -it hermes hermes%s\n\n' "$C_BOLD" "$C_OFF"
    else
        printf '\n'
        die 'Startup failed. Read the preflight output above, then re-run ./setup.sh or docker compose up -d'
    fi
else
    printf '\nStart it whenever you are ready: %sdocker compose up -d%s\n\n' "$C_BOLD" "$C_OFF"
fi
