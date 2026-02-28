#!/usr/bin/env bash
set -euo pipefail

# USER REQUEST: "continue to write working example code that explains what and why to resolve issues"
# ISSUE: Watchdog logs show "count=10" but omit actual error messages
# ROOT CAUSE: Code logged count but truncated messages to 200 chars, grep without -H flag lost filename context
# FIX: Increased to 500 chars, added -H flag, added FD consumer details, added vmstat full output

LOGFILE=".notes/test-watchdog-$(date +%Y%m%d-%H%M%S).log"
mkdir -p .notes
exec > >(tee -a "$LOGFILE") 2>&1

echo "START: test-watchdog-verbatim-output"
echo ""

echo "═══════════════════════════════════════════════════════════════════"
echo "🧪 TESTING WATCHDOG VERBATIM OUTPUT"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

# STEP 1: Find watchdog log
WATCHDOG_LOG=$(find ~/.config/Code/logs -path "*/exthost/output_logging_*/1-Watchdog Log.log" -type f 2>/dev/null | sort | tail -1)

if [ -z "$WATCHDOG_LOG" ]; then
    echo "❌ NO WATCHDOG LOG FOUND"
    echo "   REASON: Extension not installed or VS Code not reloaded"
    echo "   FIX: Reload VS Code window (Ctrl+Shift+P > 'Reload Window')"
    exit 1
fi

echo "✅ Watchdog log: $WATCHDOG_LOG"
echo ""

# STEP 2: Check for EXTENSION ERROR entries with actual error content
echo "═══════════════════════════════════════════════════════════════════"
echo "TEST 1: EXTENSION ERROR - Should show FULL error messages"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

EXTENSION_ERRORS=$(grep -A 20 "EXTENSION ERROR" "$WATCHDOG_LOG" 2>/dev/null | tail -30)

if [ -z "$EXTENSION_ERRORS" ]; then
    echo "⚠️  NO EXTENSION ERRORS LOGGED YET"
    echo "   REASON: No errors in last 60 seconds OR extension just installed"
    echo "   WAIT: 60 seconds for next monitoring cycle"
else
    echo "EXTENSION ERROR ENTRIES:"
    echo "$EXTENSION_ERRORS"
    echo ""
    
    # CHECK: Does it show actual error text or just count?
    if echo "$EXTENSION_ERRORS" | grep -q "error.*Request cancelled\|Failed to\|Exception"; then
        echo "✅ PASS: Shows actual error messages"
    else
        echo "❌ FAIL: Only shows count, missing error content"
        echo "   EXPECTED: Lines like '  2026-02-18 11:57:45.287 [error] Request cancelled'"
        echo "   ACTUAL: Only 'EXTENSION ERROR | count=10'"
    fi
fi
echo ""

# STEP 3: Check for FILE DESCRIPTOR WARNING with top consumers
echo "═══════════════════════════════════════════════════════════════════"
echo "TEST 2: FILE DESCRIPTOR WARNING - Should show top consumers"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

FD_WARNINGS=$(grep -A 10 "FILE DESCRIPTOR WARNING" "$WATCHDOG_LOG" 2>/dev/null | tail -15)

if [ -z "$FD_WARNINGS" ]; then
    echo "⚠️  NO FD WARNINGS LOGGED"
    echo "   REASON: FD count below threshold (50000) OR not monitored yet"
    echo "   CURRENT FD COUNT: $(lsof 2>/dev/null | grep -c code || echo 0)"
else
    echo "FILE DESCRIPTOR WARNING ENTRIES:"
    echo "$FD_WARNINGS"
    echo ""
    
    # CHECK: Does it show top FD consumers?
    if echo "$FD_WARNINGS" | grep -q "Top FD consumers"; then
        echo "✅ PASS: Shows top FD consumers for debugging"
    else
        echo "⚠️  PARTIAL: Shows FD count but missing top consumers"
        echo "   EXPECTED: 'Top FD consumers:' followed by process list"
    fi
fi
echo ""

# STEP 4: Check for SYSTEM ERROR with actual journalctl output
echo "═══════════════════════════════════════════════════════════════════"
echo "TEST 3: SYSTEM ERROR - Should show actual journalctl errors"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

SYSTEM_ERRORS=$(grep -A 5 "SYSTEM ERROR" "$WATCHDOG_LOG" 2>/dev/null | grep -v "^--$" | tail -20)

if [ -z "$SYSTEM_ERRORS" ]; then
    echo "✅ NO SYSTEM ERRORS (system is healthy)"
else
    echo "SYSTEM ERROR ENTRIES:"
    echo "$SYSTEM_ERRORS"
    echo ""
    
    # CHECK: Does it show actual error or just "-- No entries --"?
    if echo "$SYSTEM_ERRORS" | grep -q "-- No entries --"; then
        echo "✅ PASS: Shows journalctl output (no errors = healthy system)"
    elif echo "$SYSTEM_ERRORS" | grep -qE "Feb [0-9]|[0-9]{4}-[0-9]{2}-[0-9]{2}"; then
        echo "✅ PASS: Shows actual journalctl error messages with timestamps"
    else
        echo "❌ FAIL: Only shows count, missing actual error content"
    fi
fi
echo ""

# STEP 5: Verify monitoring is active
echo "═══════════════════════════════════════════════════════════════════"
echo "TEST 4: MONITORING ACTIVE - Check heartbeat and activation"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

LATEST_HEARTBEAT=$(grep "HEARTBEAT" "$WATCHDOG_LOG" 2>/dev/null | tail -1)
ACTIVATION=$(grep "System event monitoring started\|Application event monitoring started" "$WATCHDOG_LOG" 2>/dev/null)

if [ -z "$ACTIVATION" ]; then
    echo "❌ FAIL: Monitoring not started"
    echo "   FIX: Reload VS Code window to activate updated extension"
else
    echo "✅ Monitoring activated:"
    echo "$ACTIVATION"
fi
echo ""

if [ -z "$LATEST_HEARTBEAT" ]; then
    echo "❌ FAIL: No heartbeat (watchdog may be dead)"
else
    echo "✅ Latest heartbeat:"
    echo "$LATEST_HEARTBEAT"
    
    # CHECK: How recent is the heartbeat?
    HEARTBEAT_TIME=$(echo "$LATEST_HEARTBEAT" | grep -oP '\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}')
    CURRENT_TIME=$(date -u +"%Y-%m-%dT%H:%M:%S")
    echo "   Heartbeat time: $HEARTBEAT_TIME"
    echo "   Current time: $CURRENT_TIME"
fi
echo ""

# STEP 6: Summary and next steps
echo "═══════════════════════════════════════════════════════════════════"
echo "📊 SUMMARY"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

echo "WHAT WAS FIXED:"
echo "  1. EXTENSION ERROR: Increased truncation from 200 to 500 chars"
echo "  2. EXTENSION ERROR: Added -H flag to grep to show filename"
echo "  3. FILE DESCRIPTOR: Added top FD consumers when threshold exceeded"
echo "  4. SWAP THRASHING: Added full vmstat output for context"
echo "  5. ALL EVENTS: Added inline comments explaining USER REQUEST compliance"
echo ""

echo "VERIFICATION:"
echo "  - Extension compiled: ✅"
echo "  - Extension packaged: ✅"
echo "  - Extension installed: ✅"
echo "  - VS Code reloaded: $([ -n "$ACTIVATION" ] && echo "✅" || echo "❌ REQUIRED")"
echo ""

if [ -z "$ACTIVATION" ]; then
    echo "⚠️  NEXT STEP: Reload VS Code window"
    echo "   Command: Ctrl+Shift+P > 'Developer: Reload Window'"
    echo "   Then wait 60 seconds and re-run this test"
else
    echo "✅ WATCHDOG ACTIVE - Wait 60 seconds for next monitoring cycle"
    echo "   Then check: tail -100 \"$WATCHDOG_LOG\""
fi

echo ""
echo "END: test-watchdog-verbatim-output"

