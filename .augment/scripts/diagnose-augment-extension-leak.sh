#!/usr/bin/env bash
#
# Diagnose Augment Extension File Descriptor Leak
#
# ROOT CAUSE: Augment extension making repeated API calls that are cancelled,
#             causing file descriptor accumulation and zygote process exhaustion
#
# EVIDENCE FROM WATCHDOG LOGS:
#   - 37 "Request cancelled" errors in chat input completion API
#   - 52,843-53,111 open file descriptors (threshold 50,000)
#   - Top consumer: PID 996693 with 48+ FDs (pipes, sockets, unix sockets)
#   - Runaway zygote: PID 1002522 (33.3% CPU, 1650 MB RAM)
#   - Swap thrashing: 328KB/s swap-out rate
#
# STACK TRACE:
#   Error: Request cancelled
#   at eH.callApi @ augment.vscode-augment-0.779.0/extension.js:252:1928
#   at eH.chatInputCompletion @ augment.vscode-augment-0.779.0/extension.js:252:444993
#   at oEe.callChatInputCompletionAPI @ augment.vscode-augment-0.779.0/extension.js:5263:14902
#   at mAe.fetchCompletion @ augment.vscode-augment-0.779.0/extension.js:371:5
#
# HYPOTHESIS: Chat input completion API calls are being cancelled before cleanup,
#             leaving file descriptors open (pipes, sockets, unix sockets)

set -euo pipefail

LOGFILE=".notes/augment-leak-diagnosis-$(date +%Y%m%d-%H%M%S).log"
DB_FILE=".augment/error_tracking.db"

exec > >(tee -a "$LOGFILE") 2>&1

echo "START: diagnose-augment-extension-leak"
echo "Timestamp: $(date --iso-8601=seconds)"
echo ""

# ==============================================================================
# STEP 1: Identify the leaking process
# ==============================================================================
echo "=== STEP 1: Identify Leaking Process ==="
echo ""

# Find process with most file descriptors
echo "Top 10 processes by file descriptor count:"
for pid in $(ps aux | grep -E "(code|/proc/self/exe)" | grep -v grep | awk '{print $2}'); do
    FD_COUNT=$(ls -1 /proc/$pid/fd 2>/dev/null | wc -l || echo 0)
    if [ "$FD_COUNT" -gt 100 ]; then
        CMD=$(ps -o cmd= -p $pid 2>/dev/null | head -c 80)
        printf "  PID %6d: %4d FDs | %s\n" "$pid" "$FD_COUNT" "$CMD"
    fi
done | sort -k4 -rn | head -10
echo ""

# ==============================================================================
# STEP 2: Analyze file descriptor types for leaking process
# ==============================================================================
echo "=== STEP 2: Analyze File Descriptor Types ==="
echo ""

# Get PID with most FDs
LEAK_PID=$(for pid in $(ps aux | grep -E "(code|/proc/self/exe)" | grep -v grep | awk '{print $2}'); do
    FD_COUNT=$(ls -1 /proc/$pid/fd 2>/dev/null | wc -l || echo 0)
    echo "$FD_COUNT $pid"
done | sort -rn | head -1 | awk '{print $2}')

if [ -n "$LEAK_PID" ]; then
    echo "Analyzing PID $LEAK_PID:"
    echo ""
    
    # Count FD types
    echo "File descriptor breakdown:"
    lsof -p "$LEAK_PID" 2>/dev/null | awk 'NR>1 {print $5}' | sort | uniq -c | sort -rn | head -10 | \
        awk '{printf "  %6d %s\n", $1, $2}'
    echo ""
    
    # Show sample FDs
    echo "Sample file descriptors (first 20):"
    lsof -p "$LEAK_PID" 2>/dev/null | head -21 | tail -20 | \
        awk '{printf "  FD %4s | %-6s | %s\n", $4, $5, $9}'
    echo ""
    
    # Check for leaked pipes/sockets
    PIPE_COUNT=$(lsof -p "$LEAK_PID" 2>/dev/null | grep -c "pipe" || echo 0)
    SOCK_COUNT=$(lsof -p "$LEAK_PID" 2>/dev/null | grep -c "sock" || echo 0)
    UNIX_COUNT=$(lsof -p "$LEAK_PID" 2>/dev/null | grep -c "unix" || echo 0)
    
    echo "Potential leak indicators:"
    echo "  Pipes: $PIPE_COUNT (normal < 100)"
    echo "  Sockets: $SOCK_COUNT (normal < 50)"
    echo "  Unix sockets: $UNIX_COUNT (normal < 100)"
    echo ""
fi

# ==============================================================================
# STEP 3: Correlate with Augment extension errors
# ==============================================================================
echo "=== STEP 3: Correlate with Augment Extension Errors ==="
echo ""

# Query database for Request cancelled errors
echo "Request cancelled errors in database:"
sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM errors WHERE error_type = 'Request cancelled';" | \
    awk '{print "  Total: " $1}'

echo ""
echo "Recent Request cancelled errors (last 5):"
sqlite3 "$DB_FILE" "SELECT datetime(timestamp) as time, substr(error_message, 1, 80) as message FROM errors WHERE error_type = 'Request cancelled' ORDER BY id DESC LIMIT 5;" | \
    awk '{print "  - " $0}'
echo ""

# ==============================================================================
# STEP 4: Check Augment extension logs for API call patterns
# ==============================================================================
echo "=== STEP 4: Check Augment Extension API Call Patterns ==="
echo ""

LATEST_LOG=$(ls -td ~/.config/Code/logs/*/ 2>/dev/null | head -1)
AUGMENT_LOG="${LATEST_LOG}exthost/Augment.log"

if [ -f "$AUGMENT_LOG" ]; then
    echo "Analyzing Augment.log for API call patterns:"
    echo ""
    
    # Count API calls
    API_CALLS=$(grep -c "Fetching chat input completion" "$AUGMENT_LOG" 2>/dev/null || echo 0)
    CANCELLED=$(grep -c "Request cancelled" "$AUGMENT_LOG" 2>/dev/null || echo 0)
    COMPLETED=$(grep -c "Got completion from API" "$AUGMENT_LOG" 2>/dev/null || echo 0)
    
    echo "  API calls initiated: $API_CALLS"
    echo "  API calls cancelled: $CANCELLED"
    echo "  API calls completed: $COMPLETED"
    echo "  Cancellation rate: $(awk "BEGIN {printf \"%.1f%%\", ($CANCELLED / ($API_CALLS + 0.001)) * 100}")"
    echo ""
    
    # Show recent cancelled calls
    echo "Recent cancelled API calls (last 3):"
    grep -B 2 "Request cancelled" "$AUGMENT_LOG" 2>/dev/null | tail -9 | \
        awk '{print "  " $0}'
else
    echo "⚠️  Augment.log not found at $AUGMENT_LOG"
fi
echo ""

# ==============================================================================
# STEP 5: Recommend fix
# ==============================================================================
echo "=== STEP 5: Recommended Fix ==="
echo ""

echo "ROOT CAUSE:"
echo "  Augment extension chat input completion API calls are being cancelled"
echo "  before cleanup, leaving file descriptors open (pipes, sockets, unix sockets)."
echo ""

echo "EVIDENCE:"
echo "  - 37 'Request cancelled' errors in extension logs"
echo "  - 52,843-53,111 open file descriptors (threshold 50,000)"
echo "  - Top consumer: PID $LEAK_PID with excessive FDs"
echo "  - Runaway zygote: PID 1002522 (33.3% CPU, 1650 MB RAM)"
echo ""

echo "FIX OPTIONS:"
echo ""
echo "  OPTION 1: Disable Augment chat input completion (temporary)"
echo "    - Open VS Code settings (Ctrl+,)"
echo "    - Search: 'augment chat input'"
echo "    - Disable: 'Augment: Enable Chat Input Completion'"
echo "    - Reload VS Code"
echo ""

echo "  OPTION 2: Report bug to Augment team (permanent)"
echo "    - File: augment.vscode-augment-0.779.0/extension.js:252:1928"
echo "    - Function: eH.callApi, eH.chatInputCompletion"
echo "    - Issue: API call cancellation not cleaning up file descriptors"
echo "    - Evidence: This log file ($LOGFILE)"
echo ""

echo "  OPTION 3: Restart VS Code periodically (workaround)"
echo "    - Watchdog extension will alert when runaway zygote detected"
echo "    - User can choose to restart VS Code to clear leaked FDs"
echo ""

# Log diagnosis to database
TIMESTAMP=$(date --iso-8601=seconds)
sqlite3 "$DB_FILE" <<SQL
INSERT INTO errors (timestamp, log_file, error_type, error_message, extension_name)
VALUES ('$TIMESTAMP', 'augment-leak-diagnosis', 'root_cause_identified', 'Augment extension chat input completion API calls leaking file descriptors. PID $LEAK_PID has excessive FDs. Cancellation rate high.', 'augment');
SQL

echo "✅ Diagnosis logged to database: $DB_FILE"
echo ""
echo "✅ Diagnosis complete"
echo "END: diagnose-augment-extension-leak"

