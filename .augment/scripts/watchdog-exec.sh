#!/bin/bash
# Watchdog command wrapper - logs all output to watchdog database

WATCHDOG_DB="$HOME/.config/Code/User/globalStorage/prf-compliance.hidden-terminal-watchdog/watchdog-db.jsonl"

# Ensure database directory exists
mkdir -p "$(dirname "$WATCHDOG_DB")"

# Function to log to watchdog database
log_to_watchdog() {
    local message="$1"
    local type="${2:-info}"
    local timestamp=$(date -u +"%Y-%m-%dT%H:%M:%S.%3NZ")
    
    # Create JSON entry
    local entry=$(cat <<EOF
{"timestamp":"$timestamp","type":"$type","message":"$message","data":{"source":"watchdog-exec","command":"$*"}}
EOF
)
    
    echo "$entry" >> "$WATCHDOG_DB"
}

# Log command start
log_to_watchdog "[CMD-START] $*" "info"

# Execute command and capture output
{
    # Run command, capture both stdout and stderr
    "$@" 2>&1 | while IFS= read -r line; do
        # Log each line to watchdog
        log_to_watchdog "[CMD-OUTPUT] $line" "info"
        # Also print to terminal
        echo "$line"
    done
    
    # Capture exit code
    exit_code=${PIPESTATUS[0]}
    
    # Log command end
    log_to_watchdog "[CMD-END] Exit code: $exit_code" "info"
    
    exit $exit_code
}

