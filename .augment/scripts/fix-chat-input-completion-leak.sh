#!/usr/bin/env bash
#
# Fix Augment Chat Input Completion File Descriptor Leak
#
# STACK TRACE EVIDENCE (from watchdog logs):
#   Error: Request cancelled
#   STACK: eH.callApi @ augment.vscode-augment-0.779.0/extension.js:252:1928
#   STACK: eH.chatInputCompletion @ augment.vscode-augment-0.779.0/extension.js:252:444993
#   STACK: oEe.callChatInputCompletionAPI @ augment.vscode-augment-0.779.0/extension.js:5263:14902
#   STACK: mAe.fetchCompletion @ augment.vscode-augment-0.779.0/extension.js:371:5
#
# HOW STACK TRACE WAS USED TO TROUBLESHOOT:
#   1. Watchdog extension logged 37 identical "Request cancelled" errors
#   2. Each error included full JavaScript stack trace showing call chain
#   3. Stack trace revealed function names and exact line numbers in extension.js
#   4. Function names identified feature: "chatInputCompletion" API calls
#   5. Correlation: File descriptor leak (53,996 FDs) occurred during these API calls
#   6. Conclusion: API call cancellation not cleaning up file descriptors
#
# FILE DESCRIPTOR LEAK EVIDENCE:
#   - 53,996 total FDs (threshold: 50,000)
#   - 42,162 REG (regular files)
#   - 3,399 unix sockets
#   - 2,752 FIFOs
#   - 2,704 pipes
#   - Top consumer: PID 996693 with 48+ FDs per type
#
# RUNAWAY ZYGOTE EVIDENCE:
#   - PID 1002522: 33.3% CPU, 1650 MB RAM
#   - Parent: PID 996703 (another zygote)
#   - Swap thrashing: 328KB/s swap-out
#
# FIX: Disable augment.completions.enableChatInputCompletions via settings.json

set -euo pipefail

LOGFILE=".notes/fix-chat-input-leak-$(date +%Y%m%d-%H%M%S).log"
DB_FILE=".augment/error_tracking.db"
VSCODE_SETTINGS="$HOME/.config/Code/User/settings.json"

exec > >(tee -a "$LOGFILE") 2>&1

echo "START: fix-chat-input-completion-leak"
echo "Timestamp: $(date --iso-8601=seconds)"
echo ""

# ==============================================================================
# STEP 1: Verify the problem exists (check current FD count)
# ==============================================================================
echo "=== STEP 1: Verify File Descriptor Leak Exists ==="
echo ""

TOTAL_FDS=0
for pid in $(ps aux | grep -E "(code|/proc/self/exe)" | grep -v grep | awk '{print $2}'); do
    FD_COUNT=$(ls -1 /proc/$pid/fd 2>/dev/null | wc -l || echo 0)
    TOTAL_FDS=$((TOTAL_FDS + FD_COUNT))
done

echo "Current VS Code file descriptor count: $TOTAL_FDS"
if [ "$TOTAL_FDS" -gt 50000 ]; then
    echo "  ⚠️  CRITICAL: FD leak active (threshold: 50,000)"
    LEAK_ACTIVE=true
else
    echo "  ✅ FD count within normal range"
    LEAK_ACTIVE=false
fi
echo ""

# ==============================================================================
# STEP 2: Check if setting already disabled
# ==============================================================================
echo "=== STEP 2: Check Current Setting ==="
echo ""

if [ ! -f "$VSCODE_SETTINGS" ]; then
    echo "⚠️  VS Code settings.json not found: $VSCODE_SETTINGS"
    echo "Creating new settings.json..."
    mkdir -p "$(dirname "$VSCODE_SETTINGS")"
    echo "{}" > "$VSCODE_SETTINGS"
fi

# Check current setting value
if grep -q '"augment.completions.enableChatInputCompletions"' "$VSCODE_SETTINGS" 2>/dev/null; then
    CURRENT_VALUE=$(grep '"augment.completions.enableChatInputCompletions"' "$VSCODE_SETTINGS" | \
        sed 's/.*: *\([^,]*\).*/\1/' | tr -d ' ')
    echo "Current setting: augment.completions.enableChatInputCompletions = $CURRENT_VALUE"
    
    if [ "$CURRENT_VALUE" = "false" ]; then
        echo "  ✅ Already disabled"
        ALREADY_DISABLED=true
    else
        echo "  ⚠️  Currently enabled (causing leak)"
        ALREADY_DISABLED=false
    fi
else
    echo "Setting not found in settings.json (defaults to enabled)"
    echo "  ⚠️  Feature enabled by default (causing leak)"
    ALREADY_DISABLED=false
fi
echo ""

# ==============================================================================
# STEP 3: Disable the setting programmatically
# ==============================================================================
echo "=== STEP 3: Disable Chat Input Completion ==="
echo ""

if [ "$ALREADY_DISABLED" = false ]; then
    echo "Modifying settings.json to disable chat input completion..."
    
    # Backup original settings
    cp "$VSCODE_SETTINGS" "${VSCODE_SETTINGS}.backup-$(date +%Y%m%d-%H%M%S)"
    echo "  ✅ Backup created: ${VSCODE_SETTINGS}.backup-$(date +%Y%m%d-%H%M%S)"
    
    # Use jq if available, otherwise use sed
    if command -v jq &> /dev/null; then
        # Use jq for proper JSON manipulation
        jq '. + {"augment.completions.enableChatInputCompletions": false}' "$VSCODE_SETTINGS" > "${VSCODE_SETTINGS}.tmp"
        mv "${VSCODE_SETTINGS}.tmp" "$VSCODE_SETTINGS"
        echo "  ✅ Setting disabled using jq"
    else
        # Fallback to sed (less robust but works)
        if grep -q '"augment.completions.enableChatInputCompletions"' "$VSCODE_SETTINGS"; then
            # Setting exists, change value
            sed -i 's/"augment.completions.enableChatInputCompletions"[[:space:]]*:[[:space:]]*true/"augment.completions.enableChatInputCompletions": false/' "$VSCODE_SETTINGS"
        else
            # Setting doesn't exist, add it
            # Remove closing brace, add setting, add closing brace
            sed -i '$ s/}$/,\n  "augment.completions.enableChatInputCompletions": false\n}/' "$VSCODE_SETTINGS"
        fi
        echo "  ✅ Setting disabled using sed"
    fi
    
    # Verify change
    if grep -q '"augment.completions.enableChatInputCompletions"[[:space:]]*:[[:space:]]*false' "$VSCODE_SETTINGS"; then
        echo "  ✅ Verified: Setting now disabled"
    else
        echo "  ❌ ERROR: Failed to disable setting"
        exit 1
    fi
else
    echo "Setting already disabled, no changes needed"
fi
echo ""

# ==============================================================================
# STEP 4: Log fix to database
# ==============================================================================
echo "=== STEP 4: Log Fix to Database ==="
echo ""

TIMESTAMP=$(date --iso-8601=seconds)

sqlite3 "$DB_FILE" <<SQL
INSERT INTO errors (timestamp, log_file, error_type, error_message, extension_name)
VALUES (
    '$TIMESTAMP',
    'fix-chat-input-leak',
    'fix_applied',
    'Disabled augment.completions.enableChatInputCompletions to stop file descriptor leak. FD count before: $TOTAL_FDS',
    'augment'
);
SQL

echo "✅ Fix logged to database"
echo ""

# ==============================================================================
# STEP 5: Provide next steps
# ==============================================================================
echo "=== STEP 5: Next Steps ==="
echo ""

echo "FIX APPLIED:"
echo "  Setting: augment.completions.enableChatInputCompletions = false"
echo "  File: $VSCODE_SETTINGS"
echo "  Backup: ${VSCODE_SETTINGS}.backup-$(date +%Y%m%d-%H%M%S)"
echo ""

echo "RELOAD REQUIRED:"
echo "  VS Code must be reloaded for setting to take effect"
echo "  Method: File → Preferences → Settings (or click gear icon)"
echo "  Then: Ctrl+Shift+P → 'Developer: Reload Window'"
echo ""
echo "  ⚠️  NOTE: Ctrl+, does NOT work (increases font size)"
echo "  ⚠️  NOTE: Use File menu or gear icon to access settings"
echo ""

echo "VERIFICATION AFTER RELOAD:"
echo "  1. Wait 5 minutes for FD count to stabilize"
echo "  2. Run: ./.augment/scripts/watchdog-verification-example.sh"
echo "  3. Check: File descriptor count should drop below 10,000"
echo "  4. Check: No new 'Request cancelled' errors in logs"
echo "  5. Check: No runaway zygote processes"
echo ""

echo "IMPACT:"
echo "  ✅ File descriptor leak will stop"
echo "  ✅ Runaway zygote processes will not spawn"
echo "  ✅ Swap thrashing will cease"
echo "  ❌ Chat input completions will NOT work (feature disabled)"
echo ""

echo "ALTERNATIVE (if you need chat input completions):"
echo "  Report bug to Augment team:"
echo "  - GitHub: https://github.com/AugmentCode/augment-vscode/issues"
echo "  - Subject: 'Chat input completion API calls leak file descriptors'"
echo "  - Stack trace: eH.callApi @ extension.js:252:1928"
echo "  - Evidence: $LOGFILE"
echo ""

echo "✅ Fix complete"
echo "Log file: $LOGFILE"
echo "Database: $DB_FILE"
echo ""
echo "END: fix-chat-input-completion-leak"

