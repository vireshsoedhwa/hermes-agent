#!/bin/sh
# Reset the Hermes Agent data folder and optionally .env.
#
#   ./reset.sh          Stop container, clear hermes-data, keep .env
#   ./reset.sh --full   Also delete .env for a complete clean slate
set -eu

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

note()  { printf '%s%s%s\n' "$C_DIM" "$1" "$C_OFF"; }
ok()    { printf '%s  ok%s %s\n' "$C_GREEN" "$C_OFF" "$1"; }
warn()  { printf '%swarn%s %s\n' "$C_YELLOW" "$C_OFF" "$1"; }
die()   { printf '\n%serror%s %s\n\n' "$C_RED" "$C_OFF" "$1" >&2; exit 1; }

ask_yes_no() {
    while :; do
        if [ "$2" = y ]; then
            printf '%s %s[Y/n]%s: ' "$1" "$C_DIM" "$C_OFF"
        else
            printf '%s %s[y/N]%s: ' "$1" "$C_DIM" "$C_OFF"
        fi
        IFS= read -r _yn || _yn=''
        _yn=$(printf '%s' "$_yn" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
        [ -n "$_yn" ] || _yn="$2"
        case "$_yn" in
            y|Y|yes|YES|Yes) return 0 ;;
            n|N|no|NO|No)    return 1 ;;
            *) printf '%sPlease answer y or n.%s\n' "$C_YELLOW" "$C_OFF" ;;
        esac
    done
}

FULL_RESET=0
case "${1:-}" in
    --full) FULL_RESET=1 ;;
    --help|-h) printf 'Usage: ./reset.sh [--full]\n\n  No flag:  clear hermes-data, keep .env\n  --full:   also delete .env\n'; exit 0 ;;
    '') ;;
    *) die "Unknown option: $1. Usage: ./reset.sh [--full]" ;;
esac

printf '\n%s================================================================%s\n' "$C_BOLD" "$C_OFF"
printf '%s  Hermes Agent - reset%s\n' "$C_BOLD" "$C_OFF"
printf '%s================================================================%s\n\n' "$C_BOLD" "$C_OFF"

# Determine the data directory from .env if it exists, otherwise default.
DATA_DIR='./hermes-data'
if [ -f .env ]; then
    _dir=$(grep '^HERMES_DATA_DIR=' .env 2>/dev/null | sed 's/^HERMES_DATA_DIR=//' | tr -d '"' || true)
    [ -n "$_dir" ] && DATA_DIR="$_dir"
fi

# Stop the container first.
if command -v docker >/dev/null 2>&1; then
    note 'Stopping Hermes...'
    docker compose down 2>/dev/null && ok 'Container stopped' || note 'No running container found'
else
    warn 'Docker not found — skipping container shutdown'
fi

printf '\n'

# Warn about what will be deleted.
if [ "$FULL_RESET" -eq 1 ]; then
    warn 'Full reset: this will delete ALL data AND your .env configuration.'
    warn "  Data:   $DATA_DIR/*"
    warn '  Config: .env'
else
    warn "This will delete ALL data in $DATA_DIR/*"
    note 'Your .env (API keys, provider settings) will be kept.'
fi

printf '\n'
if ! ask_yes_no 'Are you sure? This cannot be undone.' n; then
    note 'Cancelled. Nothing was changed.'
    printf '\n'
    exit 0
fi

printf '\n'

# Clear the data directory.
if [ -d "$DATA_DIR" ]; then
    find "$DATA_DIR" -mindepth 1 -not -name '.gitkeep' -delete 2>/dev/null || true
    ok "Cleared $DATA_DIR"
else
    note "$DATA_DIR does not exist — nothing to clear"
fi

# Full reset: also remove .env.
if [ "$FULL_RESET" -eq 1 ] && [ -f .env ]; then
    rm -f .env
    ok 'Deleted .env'
fi

printf '\n'
if [ "$FULL_RESET" -eq 1 ]; then
    printf '%sReset complete.%s Run %s./setup.sh%s to start fresh.\n\n' "$C_GREEN$C_BOLD" "$C_OFF" "$C_BOLD" "$C_OFF"
else
    printf '%sReset complete.%s Your .env is intact — run %sdocker compose up -d%s to restart.\n' "$C_GREEN$C_BOLD" "$C_OFF" "$C_BOLD" "$C_OFF"
    note 'Or re-run ./setup.sh to change your configuration.\n'
fi
