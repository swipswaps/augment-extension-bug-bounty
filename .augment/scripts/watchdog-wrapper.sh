#!/bin/bash
# Watchdog wrapper - Captures all command output to watchdog database
# Usage: bash watchdog-wrapper.sh <command> [args...]

WATCHDOG_DB="$HOME/.config/Code/User/globalStorage/prf-compliance.hidden-terminal-watchdog/watchdog-db.jsonl"
mkdir -p "$(dirname "$WATCHDOG_DB")"

# Function to log to watchdog database
log_watchdog() {
    local msg="$1"
    local type="${2:-info}"
    local ts=$(date -u +"%Y-%m-%dT%H:%M:%S.000Z")
    echo "{\"timestamp\":\"$ts\",\"type\":\"$type\",\"message\":\"$msg\",\"data\":{\"source\":\"wrapper\"}}" >> "$WATCHDOG_DB"
}

# Log command start
log_watchdog "[CMD-START] $*" "info"

# Execute command and capture output line by line
"$@" 2>&1 | while IFS= read -r line; do
    log_watchdog "[OUTPUT] $line" "info"
    echo "$line"
done

# Capture exit code
exit_code=${PIPESTATUS[0]}
log_watchdog "[CMD-END] Exit: $exit_code" "info"
exit $exit_code

