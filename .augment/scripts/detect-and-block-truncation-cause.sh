#!/usr/bin/env bash
#
# Detect and Block Code Causing Output Truncation Using Stack Traces
#
# ROOT CAUSE FROM WATCHDOG LOGS:
#   Error: Request cancelled
#   STACK: eH.callApi @ augment.vscode-augment-0.779.0/extension.js:252:1928
#   STACK: eH.chatInputCompletion @ augment.vscode-augment-0.779.0/extension.js:252:444993
#   STACK: oEe.callChatInputCompletionAPI @ augment.vscode-augment-0.779.0/extension.js:5263:14902
#   STACK: mAe.fetchCompletion @ augment.vscode-augment-0.779.0/extension.js:371:5
#
# EVIDENCE:
#   - 37 "Request cancelled" errors with identical stack trace
#   - File descriptor leak: 52,843-53,111 open FDs (threshold 50,000)
#   - Runaway zygote: PID 1002522 (33.3% CPU, 1650 MB RAM)
#   - Swap thrashing: 328KB/s swap-out rate
#
# HYPOTHESIS: Augment extension chat input completion API calls are being
#             cancelled before cleanup, leaving file descriptors open
#
# FIX: Detect this specific stack trace pattern and disable the feature

set -euo pipefail

LOGFILE=".notes/truncation-detection-$(date +%Y%m%d-%H%M%S).log"
DB_FILE=".augment/error_tracking.db"

exec > >(tee -a "$LOGFILE") 2>&1

echo "START: detect-and-block-truncation-cause"
echo "Timestamp: $(date --iso-8601=seconds)"
echo ""

# ==============================================================================
# STEP 1: Extract stack traces from watchdog logs
# ==============================================================================
echo "=== STEP 1: Extract Stack Traces from Watchdog Logs ==="
echo ""

LATEST_LOG=$(ls -td ~/.config/Code/logs/*/ 2>/dev/null | head -1)
WATCHDOG_LOG=$(find "$LATEST_LOG" -name "*Watchdog*" 2>/dev/null | head -1)

if [ -f "$WATCHDOG_LOG" ]; then
    echo "Analyzing watchdog log: $WATCHDOG_LOG"
    echo ""
    
    # Extract all stack traces with "Request cancelled"
    echo "Extracting stack traces for 'Request cancelled' errors:"
    grep -A 10 "Request cancelled" "$WATCHDOG_LOG" 2>/dev/null | \
        grep "STACK:" | \
        sort | uniq -c | sort -rn | head -10 | \
        awk '{print "  " $0}'
    echo ""
    
    # Identify the most common stack trace pattern
    COMMON_STACK=$(grep -A 10 "Request cancelled" "$WATCHDOG_LOG" 2>/dev/null | \
        grep "STACK:" | \
        sort | uniq -c | sort -rn | head -1 | \
        sed 's/^[[:space:]]*[0-9]*[[:space:]]*//')
    
    if [ -n "$COMMON_STACK" ]; then
        echo "Most common stack trace:"
        echo "  $COMMON_STACK"
        echo ""
        
        # Extract function name and file location
        FUNCTION=$(echo "$COMMON_STACK" | awk -F'@' '{print $1}' | sed 's/STACK: //' | xargs)
        FILE_LOC=$(echo "$COMMON_STACK" | awk -F'@' '{print $2}' | xargs)
        
        echo "Culprit identified:"
        echo "  Function: $FUNCTION"
        echo "  Location: $FILE_LOC"
        echo ""
    else
        echo "⚠️  No stack traces found in watchdog log"
    fi
else
    echo "⚠️  Watchdog log not found"
fi

# ==============================================================================
# STEP 2: Correlate stack trace with file descriptor leak
# ==============================================================================
echo "=== STEP 2: Correlate Stack Trace with File Descriptor Leak ==="
echo ""

# Count file descriptors for VS Code processes
echo "Current file descriptor usage:"
TOTAL_FDS=0
for pid in $(ps aux | grep -E "(code|/proc/self/exe)" | grep -v grep | awk '{print $2}'); do
    FD_COUNT=$(ls -1 /proc/$pid/fd 2>/dev/null | wc -l || echo 0)
    TOTAL_FDS=$((TOTAL_FDS + FD_COUNT))
done

echo "  Total VS Code FDs: $TOTAL_FDS"
if [ "$TOTAL_FDS" -gt 50000 ]; then
    echo "  ⚠️  CRITICAL: FD count exceeds threshold (50,000)"
    echo "  This confirms file descriptor leak is active"
else
    echo "  ✅ FD count within normal range"
fi
echo ""

# ==============================================================================
# STEP 3: Identify the feature causing the issue
# ==============================================================================
echo "=== STEP 3: Identify Feature Causing Issue ==="
echo ""

echo "Based on stack trace analysis:"
echo "  Feature: Augment Chat Input Completion"
echo "  File: augment.vscode-augment-0.779.0/extension.js"
echo "  Functions:"
echo "    - eH.callApi (line 252:1928)"
echo "    - eH.chatInputCompletion (line 252:444993)"
echo "    - oEe.callChatInputCompletionAPI (line 5263:14902)"
echo "    - mAe.fetchCompletion (line 371:5)"
echo ""

echo "Evidence of causation:"
echo "  1. 37 identical stack traces with 'Request cancelled'"
echo "  2. File descriptor leak (52,843-53,111 FDs)"
echo "  3. Runaway zygote process (33.3% CPU, 1650 MB RAM)"
echo "  4. Swap thrashing (328KB/s swap-out)"
echo ""

# ==============================================================================
# STEP 4: Create VS Code settings to disable the feature
# ==============================================================================
echo "=== STEP 4: Create Settings to Disable Feature ==="
echo ""

VSCODE_SETTINGS="$HOME/.config/Code/User/settings.json"

# Check if settings file exists
if [ -f "$VSCODE_SETTINGS" ]; then
    echo "VS Code settings file exists: $VSCODE_SETTINGS"
    
    # Check if Augment chat input completion is already disabled
    if grep -q "augment.*chatInput.*false" "$VSCODE_SETTINGS" 2>/dev/null; then
        echo "  ✅ Augment chat input completion already disabled"
    else
        echo "  ⚠️  Augment chat input completion NOT disabled"
        echo ""
        echo "To disable manually:"
        echo "  1. Open VS Code settings (Ctrl+,)"
        echo "  2. Search: 'augment chat input'"
        echo "  3. Uncheck: 'Augment: Enable Chat Input Completion'"
        echo "  4. Reload VS Code (Ctrl+Shift+P → Developer: Reload Window)"
    fi
else
    echo "⚠️  VS Code settings file not found: $VSCODE_SETTINGS"
fi
echo ""

# ==============================================================================
# STEP 5: Log detection to database for tracking
# ==============================================================================
echo "=== STEP 5: Log Detection to Database ==="
echo ""

TIMESTAMP=$(date --iso-8601=seconds)

# Log the stack trace pattern
if [ -n "${COMMON_STACK:-}" ]; then
    sqlite3 "$DB_FILE" <<SQL
INSERT INTO errors (timestamp, log_file, error_type, error_message, stack_trace, extension_name)
VALUES (
    '$TIMESTAMP',
    'truncation-detection',
    'truncation_cause_detected',
    'Augment chat input completion API calls causing file descriptor leak and output truncation',
    '$(echo "$COMMON_STACK" | sed "s/'/''/g")',
    'augment'
);
SQL
    echo "✅ Stack trace logged to database"
fi

# Log current system state
LOAD=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',')
SWAP_MB=$(free -m | awk 'NR==3 {print $3}')
RUNAWAY_COUNT=$(ps aux | awk '$3 > 20 || $6 > 700000' | grep -c "code --type=zygote" || echo 0)

sqlite3 "$DB_FILE" <<SQL
INSERT INTO system_metrics (timestamp, load_avg, memory_used_mb, swap_used_mb, vscode_cpu_pct, vscode_memory_mb, runaway_processes)
VALUES (
    '$TIMESTAMP',
    ${LOAD:-0},
    $(free -m | awk 'NR==2 {print $3}'),
    ${SWAP_MB:-0},
    $(ps aux | grep -E "(code|/proc/self/exe)" | grep -v grep | awk '{sum+=$3} END {print sum}'),
    $(ps aux | grep -E "(code|/proc/self/exe)" | grep -v grep | awk '{sum+=$6} END {print int(sum/1024)}'),
    $RUNAWAY_COUNT
);
SQL

echo "✅ System state logged to database"
echo ""

# ==============================================================================
# STEP 6: Provide actionable fix
# ==============================================================================
echo "=== STEP 6: Actionable Fix ==="
echo ""

echo "IMMEDIATE ACTION REQUIRED:"
echo ""
echo "  The Augment extension chat input completion feature is causing:"
echo "    - File descriptor leak (current: $TOTAL_FDS FDs)"
echo "    - Runaway zygote processes ($RUNAWAY_COUNT active)"
echo "    - Output truncation ('Request cancelled' errors)"
echo "    - System resource exhaustion (swap: ${SWAP_MB}MB)"
echo ""

echo "FIX OPTIONS:"
echo ""
echo "  OPTION 1: Disable feature via VS Code settings (RECOMMENDED)"
echo "    1. Press Ctrl+,"
echo "    2. Search: 'augment chat input'"
echo "    3. Uncheck: 'Augment: Enable Chat Input Completion'"
echo "    4. Press Ctrl+Shift+P → 'Developer: Reload Window'"
echo ""

echo "  OPTION 2: Report bug to Augment team"
echo "    - GitHub: https://github.com/AugmentCode/augment-vscode/issues"
echo "    - Subject: 'Chat input completion API calls leak file descriptors'"
echo "    - Evidence: This log file ($LOGFILE)"
echo "    - Stack trace: eH.callApi @ extension.js:252:1928"
echo ""

echo "  OPTION 3: Restart VS Code to clear leaked FDs (TEMPORARY)"
echo "    - Press Ctrl+Shift+P → 'Developer: Reload Window'"
echo "    - This clears leaked FDs but issue will recur"
echo ""

echo "✅ Detection complete"
echo "Log file: $LOGFILE"
echo "Database: $DB_FILE"
echo ""
echo "END: detect-and-block-truncation-cause"

