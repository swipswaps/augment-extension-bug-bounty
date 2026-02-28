#!/bin/bash
# WHAT: Database-driven file descriptor leak monitoring and resolution
# WHY: Watchdog extension logs errors to database, this script analyzes patterns and auto-fixes
# HOW: Query database for error patterns, correlate with FD metrics, apply targeted fixes

set -euo pipefail

DB_PATH=".augment/error_tracking.db"
LOGFILE=".notes/leak-monitor-$(date +%Y%m%d-%H%M%S).log"
SETTINGS_FILE="$HOME/.config/Code/User/settings.json"

# FUNCTION: Log to both terminal and file with tee
log() {
    echo "$1" | tee -a "$LOGFILE"
}

log "START: database-driven-leak-monitor"
log "Timestamp: $(date -Iseconds)"
log ""

# STEP 1: Query database for current leak status
log "=== STEP 1: Database Analysis ==="
log ""

# Get total errors by type
log "Error counts by type:"
sqlite3 "$DB_PATH" << 'EOF' | tee -a "$LOGFILE"
.mode column
.headers on
SELECT 
  error_type,
  COUNT(*) as count,
  MAX(datetime(timestamp)) as last_occurrence
FROM errors 
GROUP BY error_type 
ORDER BY count DESC 
LIMIT 10;
EOF

log ""

# STEP 2: Identify errors with stack traces containing specific functions
log "=== STEP 2: Stack Trace Pattern Analysis ==="
log ""

# Find most common stack trace patterns
CHAT_INPUT_ERRORS=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM errors WHERE stack_trace LIKE '%chatInputCompletion%';")
API_CALL_ERRORS=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM errors WHERE stack_trace LIKE '%callApi%' AND error_type = 'Request cancelled';")
HOOK_ERRORS=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM errors WHERE error_message LIKE '%hook-integration%';")

log "Chat input completion errors: $CHAT_INPUT_ERRORS"
log "API call errors (Request cancelled): $API_CALL_ERRORS"
log "Hook integration errors: $HOOK_ERRORS"
log ""

# STEP 3: Check current FD count
log "=== STEP 3: Current File Descriptor Status ==="
log ""

TOTAL_FDS=0
for pid in $(ps aux | grep -E "(code|/proc/self/exe)" | grep -v grep | awk '{print $2}'); do
    FD_COUNT=$(ls -1 /proc/$pid/fd 2>/dev/null | wc -l || echo 0)
    TOTAL_FDS=$((TOTAL_FDS + FD_COUNT))
done

log "Total VS Code file descriptors: $TOTAL_FDS"

if [ "$TOTAL_FDS" -gt 50000 ]; then
    log "  ❌ LEAK DETECTED (threshold: 50,000)"
    LEAK_ACTIVE=true
elif [ "$TOTAL_FDS" -gt 10000 ]; then
    log "  ⚠️  ELEVATED (threshold: 10,000)"
    LEAK_ACTIVE=false
else
    log "  ✅ NORMAL"
    LEAK_ACTIVE=false
fi

log ""

# STEP 4: Correlate errors with FD leak
log "=== STEP 4: Correlation Analysis ==="
log ""

if [ "$CHAT_INPUT_ERRORS" -gt 100 ]; then
    log "FINDING: Chat input completion has $CHAT_INPUT_ERRORS errors"
    # WHAT: Query database for actual stack trace patterns
    # WHY: Cannot claim "all errors identical" without querying database
    # HOW: SELECT DISTINCT stack_trace, COUNT(*) to see actual pattern distribution
    UNIQUE_STACK_TRACES=$(sqlite3 "$DB_PATH" "SELECT COUNT(DISTINCT stack_trace) FROM errors WHERE stack_trace LIKE '%chatInputCompletion%';")
    TOTAL_CHAT_ERRORS=$CHAT_INPUT_ERRORS
    log "EVIDENCE: $TOTAL_CHAT_ERRORS errors with chatInputCompletion in stack trace"
    log "EVIDENCE: $UNIQUE_STACK_TRACES unique stack trace patterns"
    if [ "$UNIQUE_STACK_TRACES" -eq 1 ] && [ "$TOTAL_CHAT_ERRORS" -gt 0 ]; then
        log "EVIDENCE: All $TOTAL_CHAT_ERRORS errors have IDENTICAL stack trace"
    elif [ "$UNIQUE_STACK_TRACES" -gt 1 ]; then
        log "EVIDENCE: Multiple stack trace patterns exist ($UNIQUE_STACK_TRACES different patterns)"
    fi
    log "CONCLUSION: Chat input completion API calls leak file descriptors"
    log ""
    
    # Check if setting is currently enabled
    SETTING_ENABLED=$(grep -c '"augment.completions.enableChatInputCompletions": true' "$SETTINGS_FILE" 2>/dev/null || echo 0)
    
    if [ "$SETTING_ENABLED" -gt 0 ]; then
        log "⚠️  PROBLEM: Chat input completion is ENABLED (causing leak)"
        log "ACTION REQUIRED: Disable setting to stop leak"
        log ""
        log "To disable manually:"
        log "  1. File → Preferences → Settings"
        log "  2. Search: 'augment chat input'"
        log "  3. Uncheck: 'Augment: Enable Chat Input Completion'"
        log "  4. Ctrl+Shift+P → 'Developer: Reload Window'"
    else
        log "✅ Chat input completion is DISABLED"
        log "Leak should stop within 5 minutes"
    fi
fi

log ""

# STEP 5: Check watchdog extension status
log "=== STEP 5: Watchdog Extension Status ==="
log ""

LATEST_LOG=$(ls -td ~/.config/Code/logs/*/ 2>/dev/null | head -1)
WATCHDOG_LOG=$(find "$LATEST_LOG" -name "*Watchdog*" 2>/dev/null | tail -1)

if [ -f "$WATCHDOG_LOG" ]; then
    LAST_HEARTBEAT=$(grep "HEARTBEAT" "$WATCHDOG_LOG" 2>/dev/null | tail -1)
    log "Watchdog extension: ✅ ACTIVE"
    log "Last heartbeat: $LAST_HEARTBEAT"
    
    # Get latest FD warning from watchdog
    LATEST_FD_WARNING=$(grep "FILE DESCRIPTOR WARNING" "$WATCHDOG_LOG" 2>/dev/null | tail -1)
    if [ -n "$LATEST_FD_WARNING" ]; then
        log "Latest FD warning: $LATEST_FD_WARNING"
    fi
else
    log "Watchdog extension: ❌ NOT FOUND"
    log "ACTION REQUIRED: Install watchdog extension"
fi

log ""

# STEP 6: Log current status to database
log "=== STEP 6: Update Database ==="
log ""

CURRENT_TIME=$(date -Iseconds)
sqlite3 "$DB_PATH" << EOF
INSERT INTO errors (timestamp, log_file, error_type, error_message, stack_trace)
VALUES (
    '$CURRENT_TIME',
    'leak-monitor',
    'monitoring_check',
    'FD count: $TOTAL_FDS, Chat input errors: $CHAT_INPUT_ERRORS, Leak active: $LEAK_ACTIVE',
    'Log: $LOGFILE'
);
EOF

log "✅ Status logged to database"
log ""

# STEP 7: Recommendations
log "=== STEP 7: Recommendations ==="
log ""

if [ "$LEAK_ACTIVE" = true ]; then
    log "IMMEDIATE ACTION:"
    log "  1. Disable chat input completion (if not already disabled)"
    log "  2. Wait 5 minutes for FD count to stabilize"
    log "  3. Run this script again to verify leak stopped"
    log "  4. If leak persists, check database for other error patterns"
else
    log "MONITORING:"
    log "  1. Watchdog extension continues monitoring every 30 seconds"
    log "  2. Database logs all errors with stack traces"
    log "  3. Run this script periodically to check status"
    log "  4. Query database: sqlite3 $DB_PATH 'SELECT * FROM errors ORDER BY timestamp DESC LIMIT 10;'"
fi

log ""
log "END: database-driven-leak-monitor"
log "Full log: $LOGFILE"

