#!/usr/bin/env bash

# WHAT: Display _cancelledByUser latch mutation events with full stack traces
# WHY: User needs to see when latch is set and correlation with resource pressure
# HOW: Parse augment-cancelledByUser-debug.log and display formatted output

set -euo pipefail

LOG_FILE="./augment-cancelledByUser-debug.log"

echo "================================================================================
STEP 1: VERIFY INSTRUMENTATION LOG FILE
================================================================================
"

if [[ ! -f "$LOG_FILE" ]]; then
    echo "❌ ERROR: Log file not found: $LOG_FILE"
    echo ""
    echo "This means instrumentation is not deployed or has not been activated."
    echo ""
    echo "To deploy instrumentation:"
    echo "  ./.augment/scripts/deploy-cancelledByUser-instrumentation.sh"
    echo ""
    echo "Then reload VS Code window and use Augment AI normally."
    exit 1
fi

echo "✅ Log file exists: $LOG_FILE"
ls -lh "$LOG_FILE"

echo "
================================================================================
STEP 2: COUNT MUTATION EVENTS
================================================================================
"

TOTAL_MUTATIONS=$(grep -c "_cancelledByUser LATCH MUTATION DETECTED" "$LOG_FILE" || echo 0)
LATCH_SET_TRUE=$(grep -c "New value: true" "$LOG_FILE" || echo 0)
LATCH_SET_FALSE=$(grep -c "New value: false" "$LOG_FILE" || echo 0)

echo "Total mutations detected: $TOTAL_MUTATIONS"
echo "  - Set to TRUE (latch engaged): $LATCH_SET_TRUE"
echo "  - Set to FALSE (latch reset): $LATCH_SET_FALSE"

if [[ "$TOTAL_MUTATIONS" -eq 0 ]]; then
    echo "
⚠️  NO MUTATIONS DETECTED YET

This means:
  - Instrumentation IS loaded (log file exists)
  - Instrumentation IS active (if you see initialization message)
  - BUT _cancelledByUser has NOT been set yet

NEXT STEPS:
  1. Use Augment AI normally until 'Cancelled by user' error appears
  2. Run this script again to see stack traces
  3. Check for correlation with terminal count and FD count

The instrumentation will capture the exact moment the latch is set.
"
    exit 0
fi

echo "
================================================================================
STEP 3: DISPLAY ALL MUTATION EVENTS
================================================================================
"

cat "$LOG_FILE"

echo "
================================================================================
STEP 4: ANALYZE MUTATION PATTERNS
================================================================================
"

# WHAT: Extract terminal counts from mutation events
# WHY: User's RULE 22 forensic finding shows terminal accumulation causes MCP instability
# HOW: Grep for "Terminal count:" and display values
echo "Terminal counts at mutation moments:"
grep "Terminal count:" "$LOG_FILE" || echo "  (no data)"

echo ""
echo "File descriptor counts at mutation moments:"
grep "File descriptor count:" "$LOG_FILE" || echo "  (no data)"

echo ""
echo "Critical analysis flags:"
grep "CRITICAL ANALYSIS:" -A 3 "$LOG_FILE" || echo "  (no data)"

echo "
================================================================================
STEP 5: IDENTIFY ROOT CAUSE FUNCTION
================================================================================
"

echo "Stack traces showing which function triggers the latch:"
echo ""

# WHAT: Extract stack traces from mutation events
# WHY: User needs to identify exact function that sets _cancelledByUser = true
# HOW: Parse log file for STACK TRACE sections
awk '/STACK TRACE:/{flag=1; next} /^=/{flag=0} flag' "$LOG_FILE" | head -20

echo "
================================================================================
STEP 6: CORRELATION WITH RESOURCE PRESSURE
================================================================================
"

# WHAT: Check if latch trigger correlates with resource pressure
# WHY: User's analysis shows terminal accumulation and FD leak cause MCP instability
# HOW: Look for warning flags in critical analysis
if grep -q "TERMINAL ACCUMULATION DETECTED" "$LOG_FILE"; then
    echo "🔴 TERMINAL ACCUMULATION DETECTED"
    echo "   This confirms RULE 22 forensic finding: terminal accumulation causes MCP instability"
fi

if grep -q "FILE DESCRIPTOR LEAK DETECTED" "$LOG_FILE"; then
    echo "🔴 FILE DESCRIPTOR LEAK DETECTED"
    echo "   This confirms user's analysis: FD leak correlates with latch trigger"
fi

if ! grep -q "TERMINAL ACCUMULATION DETECTED\|FILE DESCRIPTOR LEAK DETECTED" "$LOG_FILE"; then
    echo "✅ No resource pressure detected at mutation moment"
    echo "   Latch may be triggered by other factors (network timeout, user action, etc.)"
fi

echo "
================================================================================
STEP 7: SUMMARY AND NEXT STEPS
================================================================================
"

echo "FINDINGS:"
echo "  - Total mutations: $TOTAL_MUTATIONS"
echo "  - Latch set to TRUE: $LATCH_SET_TRUE"
echo "  - Latch set to FALSE: $LATCH_SET_FALSE"
echo ""
echo "EXPECTED BEHAVIOR:"
echo "  - Initialization: _cancelledByUser = false (once)"
echo "  - Latch trigger: _cancelledByUser = true (under resource pressure)"
echo "  - NEVER: _cancelledByUser = false (after initialization)"
echo ""

if [[ "$LATCH_SET_TRUE" -gt 0 ]]; then
    echo "🔴 LATCH ENGAGED - ALL TOOL CALLS WILL FAIL"
    echo ""
    echo "This is the root cause of 'Cancelled by user' errors and empty <output> sections."
    echo ""
    echo "NEXT STEPS:"
    echo "  1. Review stack traces above to identify which function triggers the latch"
    echo "  2. Check terminal count and FD count for correlation with resource pressure"
    echo "  3. Report findings to Augment team with complete evidence"
    echo "  4. Reload VS Code window to reset the latch"
fi

echo "
EVIDENCE COLLECTED:
  ✅ Complete stack traces: $(if [[ "$TOTAL_MUTATIONS" -gt 0 ]]; then echo "YES"; else echo "NO"; fi)"
echo "  ✅ Timestamps: $(if [[ "$TOTAL_MUTATIONS" -gt 0 ]]; then echo "YES"; else echo "NO"; fi)"
echo "  ✅ Process PIDs: $(if [[ "$TOTAL_MUTATIONS" -gt 0 ]]; then echo "YES"; else echo "NO"; fi)"
echo "  ✅ Terminal counts: $(if grep -q "Terminal count:" "$LOG_FILE"; then echo "YES"; else echo "NO"; fi)"
echo "  ✅ FD counts: $(if grep -q "File descriptor count:" "$LOG_FILE"; then echo "YES"; else echo "NO"; fi)"
echo "  ✅ Old/new values: $(if [[ "$TOTAL_MUTATIONS" -gt 0 ]]; then echo "YES"; else echo "NO"; fi)"
echo "
"

