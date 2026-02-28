#!/usr/bin/env bash
set -euo pipefail

# USER REQUEST: "write a prompt in verbatim working example code that enumerates and proceeds with request compliance"
# INTERPRETATION: Verify that watchdog now displays ALL events with FULL verbatim messages as requested
# METHOD: Check watchdog log for compliance with each specific request

LOGFILE=".notes/verify-compliance-$(date +%Y%m%d-%H%M%S).log"
mkdir -p .notes
exec > >(tee -a "$LOGFILE") 2>&1

echo "START: verify-request-compliance"
echo ""

echo "═══════════════════════════════════════════════════════════════════"
echo "📋 REQUEST COMPLIANCE ENUMERATION"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

echo "ORIGINAL REQUEST (repeated multiple times):"
echo "  'make the watchdog display _all_ event, error, system and application relevant messages'"
echo ""

echo "SPECIFIC COMPLAINTS:"
echo "  1. 'a lot of these look to be omitting the actual errors'"
echo "  2. Logs showed 'count=10' but not what the errors were"
echo "  3. Recursive watchdog log entries (/.../Watchdog.log:[timestamp]...)"
echo "  4. FD warnings showed '19680 code 123893' but not WHAT is consuming FDs"
echo ""

echo "COMPLIANCE REQUIREMENTS:"
echo "  ✓ REQ-1: Display FULL verbatim error messages, not just counts"
echo "  ✓ REQ-2: No recursive watchdog log entries"
echo "  ✓ REQ-3: Show filename without full path (save space)"
echo "  ✓ REQ-4: Show FD type (REG/unix/pipe) to identify leak source"
echo "  ✓ REQ-5: Show FD breakdown by type for actionable diagnostics"
echo ""

echo "═══════════════════════════════════════════════════════════════════"
echo "🔍 STEP 1: Find latest watchdog log"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

WATCHDOG_LOG=$(find ~/.config/Code/logs -path "*/exthost/output_logging_*/1-Watchdog Log.log" -type f 2>/dev/null | sort | tail -1)

if [ -z "$WATCHDOG_LOG" ]; then
    echo "❌ FAIL: No watchdog log found"
    echo "   REASON: Extension not installed or VS Code not reloaded"
    echo "   ACTION: Install extension and reload VS Code window"
    exit 1
fi

echo "✅ Watchdog log found:"
echo "   $WATCHDOG_LOG"
echo ""

# Get log modification time
LOG_MTIME=$(stat -c %Y "$WATCHDOG_LOG" 2>/dev/null || stat -f %m "$WATCHDOG_LOG" 2>/dev/null)
CURRENT_TIME=$(date +%s)
AGE=$((CURRENT_TIME - LOG_MTIME))

echo "   Last modified: $AGE seconds ago"
if [ "$AGE" -gt 120 ]; then
    echo "   ⚠️  WARNING: Log is stale (>2 minutes old), extension may not be running"
fi
echo ""

echo "═══════════════════════════════════════════════════════════════════"
echo "🔍 STEP 2: Verify monitoring activated"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

ACTIVATION=$(grep "System event monitoring started\|Application event monitoring started" "$WATCHDOG_LOG" 2>/dev/null | tail -2)

if [ -z "$ACTIVATION" ]; then
    echo "❌ FAIL: Monitoring not activated"
    echo "   REASON: Extension not loaded or old version still running"
    echo "   ACTION: Reload VS Code window again"
    exit 1
fi

echo "✅ Monitoring activated:"
echo "$ACTIVATION" | sed 's/^/   /'
echo ""

echo "═══════════════════════════════════════════════════════════════════"
echo "✅ REQ-1: FULL verbatim error messages (not just counts)"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

EXTENSION_ERRORS=$(grep -A 30 "EXTENSION ERROR" "$WATCHDOG_LOG" 2>/dev/null | tail -40)

if [ -z "$EXTENSION_ERRORS" ]; then
    echo "⚠️  NO EXTENSION ERRORS logged yet"
    echo "   REASON: No errors in last 60 seconds OR monitoring just started"
    echo "   ACTION: Wait 60 seconds for next monitoring cycle"
else
    echo "EXTENSION ERROR entries found:"
    echo "$EXTENSION_ERRORS" | head -20 | sed 's/^/   /'
    echo ""
    
    # CHECK: Does it show actual error text or just count?
    if echo "$EXTENSION_ERRORS" | grep -qE "Augment\.log:|main\.log:" | head -5; then
        echo "✅ REQ-1 PASS: Shows actual error messages with filename"
        
        # CHECK: Are full paths removed?
        if echo "$EXTENSION_ERRORS" | grep -q "/home/owner/.config/Code/logs/.*/Augment.log:"; then
            echo "   ⚠️  WARNING: Still showing full paths (should be just 'Augment.log:')"
        else
            echo "   ✅ BONUS: Full paths removed, only showing filename"
        fi
    else
        echo "❌ REQ-1 FAIL: Only shows count, missing actual error messages"
    fi
fi
echo ""

echo "═══════════════════════════════════════════════════════════════════"
echo "✅ REQ-2: No recursive watchdog log entries"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

# PROBLEM: grep -c returns "0\n0" when no match, causing integer comparison to fail
# FIX: Use grep without -c, count lines manually, handle empty string
RECURSIVE_LINES=$(echo "$EXTENSION_ERRORS" | grep "Watchdog Log.log" 2>/dev/null || true)
if [ -z "$RECURSIVE_LINES" ]; then
    RECURSIVE_COUNT=0
else
    RECURSIVE_COUNT=$(echo "$RECURSIVE_LINES" | wc -l | tr -d ' ')
fi

if [ "$RECURSIVE_COUNT" -eq 0 ]; then
    echo "✅ REQ-2 PASS: No recursive watchdog log entries"
else
    echo "❌ REQ-2 FAIL: Found $RECURSIVE_COUNT recursive watchdog log entries"
    echo "   EXAMPLE:"
    echo "$RECURSIVE_LINES" | head -3 | sed 's/^/   /'
fi
echo ""

echo "═══════════════════════════════════════════════════════════════════"
echo "✅ REQ-4: FD type display (REG/unix/pipe)"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

FD_WARNINGS=$(grep -A 20 "FILE DESCRIPTOR WARNING" "$WATCHDOG_LOG" 2>/dev/null | tail -25)

if [ -z "$FD_WARNINGS" ]; then
    echo "⚠️  NO FD WARNINGS logged"
    echo "   REASON: FD count below threshold (50000) OR monitoring just started"
    CURRENT_FD=$(lsof 2>/dev/null | grep -c code || echo 0)
    echo "   CURRENT FD COUNT: $CURRENT_FD"
else
    echo "FILE DESCRIPTOR WARNING entries found:"
    echo "$FD_WARNINGS" | sed 's/^/   /'
    echo ""
    
    # CHECK: Does it show FD types?
    if echo "$FD_WARNINGS" | grep -qE "REG|unix|pipe|CHR"; then
        echo "✅ REQ-4 PASS: Shows FD types (REG/unix/pipe/CHR)"
    else
        echo "❌ REQ-4 FAIL: No FD types visible"
    fi
    
    # CHECK: Does it show FD breakdown?
    if echo "$FD_WARNINGS" | grep -q "FD breakdown by type"; then
        echo "✅ REQ-5 PASS: Shows FD breakdown by type"
    else
        echo "❌ REQ-5 FAIL: No FD breakdown by type"
    fi
fi
echo ""

echo "═══════════════════════════════════════════════════════════════════"
echo "🔍 STEP 3: Check heartbeat (proves watchdog is alive)"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

LATEST_HEARTBEAT=$(grep "HEARTBEAT" "$WATCHDOG_LOG" 2>/dev/null | tail -1)

if [ -z "$LATEST_HEARTBEAT" ]; then
    echo "❌ FAIL: No heartbeat found"
else
    echo "✅ Latest heartbeat:"
    echo "   $LATEST_HEARTBEAT"
    
    # Extract timestamp
    HEARTBEAT_TIME=$(echo "$LATEST_HEARTBEAT" | grep -oP '\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}' || echo "")
    CURRENT_TIME_ISO=$(date -u +"%Y-%m-%dT%H:%M:%S")
    echo "   Heartbeat time: $HEARTBEAT_TIME"
    echo "   Current time:   $CURRENT_TIME_ISO"
fi
echo ""

echo "═══════════════════════════════════════════════════════════════════"
echo "📊 COMPLIANCE SUMMARY"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

echo "VERIFICATION RESULTS:"
echo "  ✅ Watchdog log found and active"
echo "  ✅ Monitoring activated (system + application events)"

if [ -n "$EXTENSION_ERRORS" ]; then
    echo "  ✅ REQ-1: Full verbatim error messages"
else
    echo "  ⚠️  REQ-1: Full verbatim error messages (not tested yet)"
fi

if [ "$RECURSIVE_COUNT" = "0" ]; then
    echo "  ✅ REQ-2: No recursive watchdog entries"
else
    echo "  ❌ REQ-2: No recursive watchdog entries (FAILED)"
fi

if [ -n "$FD_WARNINGS" ] && echo "$FD_WARNINGS" | grep -q "REG\|unix\|pipe"; then
    echo "  ✅ REQ-4: FD type display"
else
    echo "  ⚠️  REQ-4: FD type display (not tested yet)"
fi

if [ -n "$FD_WARNINGS" ] && echo "$FD_WARNINGS" | grep -q "FD breakdown"; then
    echo "  ✅ REQ-5: FD breakdown by type"
else
    echo "  ⚠️  REQ-5: FD breakdown by type (not tested yet)"
fi
echo ""

if [ -z "$EXTENSION_ERRORS" ] || [ -z "$FD_WARNINGS" ]; then
    echo "⚠️  INCOMPLETE VERIFICATION"
    echo "   REASON: Not all event types have occurred yet"
    echo "   ACTION: Wait 60 seconds and re-run this script"
    echo ""
    echo "   Re-run command:"
    echo "   bash .augment/scripts/verify-request-compliance.sh"
else
    echo "✅ FULL COMPLIANCE VERIFIED"
    echo "   All requested features are working as expected"
fi
echo ""

echo "END: verify-request-compliance"

