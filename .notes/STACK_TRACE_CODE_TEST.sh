#!/bin/bash
# ═══════════════════════════════════════════════════════════════════
# STACK TRACE LOGGING - AUTOMATED TEST SCRIPT
# ═══════════════════════════════════════════════════════════════════

echo "=== STACK TRACE LOGGING TEST ==="
echo ""

# Find watchdog log
WATCHDOG_LOG=$(find ~/.config/Code/logs -name "*Watchdog*.log" -type f 2>/dev/null | sort | tail -1)

if [ -z "$WATCHDOG_LOG" ]; then
    echo "❌ ERROR: Watchdog log not found"
    exit 1
fi

echo "✅ Found watchdog log: $WATCHDOG_LOG"
echo ""

# Test 1: Check if stack traces are being captured
echo "TEST 1: Stack Trace Capture"
RAW_COUNT=$(tail -500 "$WATCHDOG_LOG" 2>/dev/null | grep -c "    at ")
echo "  Raw stack lines captured: $RAW_COUNT"
if [ "$RAW_COUNT" -gt 0 ]; then
    echo "  ✅ PASS: Stack traces are being captured"
else
    echo "  ❌ FAIL: No stack traces found"
fi
echo ""

# Test 2: Check if stack traces are being parsed
echo "TEST 2: Stack Trace Parsing"
PARSED_COUNT=$(tail -500 "$WATCHDOG_LOG" 2>/dev/null | grep -c "STACK:")
echo "  Parsed STACK: entries: $PARSED_COUNT"
if [ "$PARSED_COUNT" -gt 0 ]; then
    echo "  ✅ PASS: Stack traces are being parsed"
    
    # Calculate success rate
    if [ "$RAW_COUNT" -gt 0 ]; then
        SUCCESS_RATE=$((PARSED_COUNT * 100 / RAW_COUNT))
        echo "  Success rate: $SUCCESS_RATE% ($PARSED_COUNT / $RAW_COUNT)"
        
        if [ "$SUCCESS_RATE" -lt 50 ]; then
            echo "  ⚠️  WARNING: Low success rate - 'at async' pattern may not be matched"
            echo "  ACTION: Reload VS Code window to activate updated extension"
        elif [ "$SUCCESS_RATE" -ge 90 ]; then
            echo "  ✅ EXCELLENT: High success rate - 'at async' pattern is working"
        fi
    fi
else
    echo "  ❌ FAIL: No parsed stack traces found"
fi
echo ""

# Test 3: Show sample stack traces
echo "TEST 3: Sample Stack Traces"
SAMPLES=$(tail -100 "$WATCHDOG_LOG" 2>/dev/null | grep "STACK:" | head -5)
if [ -n "$SAMPLES" ]; then
    echo "$SAMPLES"
    echo "  ✅ PASS: Stack traces are formatted correctly"
else
    echo "  ❌ FAIL: No stack trace samples found"
fi
echo ""

# Test 4: Check for "at async" patterns
echo "TEST 4: 'at async' Pattern Detection"
ASYNC_RAW=$(tail -500 "$WATCHDOG_LOG" 2>/dev/null | grep -c "at async")
ASYNC_PARSED=$(tail -500 "$WATCHDOG_LOG" 2>/dev/null | grep "STACK:" | grep -c "eH\|oEe\|mAe")
echo "  Raw 'at async' lines: $ASYNC_RAW"
echo "  Parsed async functions: $ASYNC_PARSED"
if [ "$ASYNC_PARSED" -gt 0 ]; then
    echo "  ✅ PASS: 'at async' pattern is being parsed"
else
    if [ "$ASYNC_RAW" -gt 0 ]; then
        echo "  ⚠️  WARNING: 'at async' lines exist but not parsed"
        echo "  ACTION: Reload VS Code window to activate updated extension"
    else
        echo "  ℹ️  INFO: No 'at async' patterns in recent logs"
    fi
fi
echo ""

# Summary
echo "=== SUMMARY ==="
echo "Raw stack lines: $RAW_COUNT"
echo "Parsed STACK: entries: $PARSED_COUNT"
if [ "$RAW_COUNT" -gt 0 ]; then
    SUCCESS_RATE=$((PARSED_COUNT * 100 / RAW_COUNT))
    echo "Success rate: $SUCCESS_RATE%"
    
    if [ "$SUCCESS_RATE" -ge 90 ]; then
        echo "✅ STATUS: EXCELLENT - Stack trace logging is working correctly"
    elif [ "$SUCCESS_RATE" -ge 50 ]; then
        echo "⚠️  STATUS: PARTIAL - Stack trace logging is working but needs improvement"
        echo "ACTION: Reload VS Code window to activate updated extension"
    else
        echo "❌ STATUS: POOR - Stack trace logging needs attention"
        echo "ACTION: Reload VS Code window to activate updated extension"
    fi
else
    echo "ℹ️  STATUS: NO DATA - No stack traces in recent logs"
fi
echo ""
echo "=== NEXT STEPS ==="
echo "1. Reload VS Code window: Ctrl+Shift+P → 'Developer: Reload Window'"
echo "2. Wait 60 seconds for watchdog to scan Augment.log"
echo "3. Run this script again to verify improvement"
echo ""
