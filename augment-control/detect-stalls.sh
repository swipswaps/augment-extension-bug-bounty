#!/usr/bin/env bash
# Detect Stalls in Augment Extension

set -euo pipefail

echo "╔════════════════════════════════════════════════════════════════════════════╗"
echo "║                    AUGMENT STALL DETECTOR                                  ║"
echo "╚════════════════════════════════════════════════════════════════════════════╝"
echo ""

LATEST_LOG=$(ls -td ~/.config/Code/logs/*/ 2>/dev/null | head -1)

if [ -z "$LATEST_LOG" ]; then
    echo "❌ No VS Code logs found"
    exit 1
fi

echo "📁 Log directory: $LATEST_LOG"
echo ""

# 1. Check for UNRESPONSIVE warnings
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. EXTENSION UNRESPONSIVE WARNINGS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

RENDERER_LOG="${LATEST_LOG}window1/renderer.log"
if [ -f "$RENDERER_LOG" ]; then
    UNRESPONSIVE=$(grep "UNRESPONSIVE.*augment" "$RENDERER_LOG" 2>/dev/null || echo "")
    if [ -n "$UNRESPONSIVE" ]; then
        echo "⚠️  STALLS DETECTED:"
        echo "$UNRESPONSIVE" | while read -r line; do
            # Extract percentage and duration
            PERCENT=$(echo "$line" | grep -oP '\d+\.\d+%' || echo "unknown")
            DURATION=$(echo "$line" | grep -oP '\d+\.\d+ms' || echo "unknown")
            echo "   - Extension blocked event loop: $PERCENT of $DURATION"
        done
        echo ""
        echo "🔍 CPU profiles saved to /tmp/exthost-*.cpuprofile"
    else
        echo "✅ No unresponsive warnings"
    fi
else
    echo "⚠️  Renderer log not found"
fi
echo ""

# 2. Check for Request Cancelled errors
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "2. REQUEST CANCELLATION STORMS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

AUGMENT_LOG=$(find "$LATEST_LOG" -path "*/Augment.vscode-augment/Augment.log" 2>/dev/null | head -1)
if [ -f "$AUGMENT_LOG" ]; then
    CANCELLED_COUNT=$(grep -c "Request cancelled" "$AUGMENT_LOG" 2>/dev/null || echo "0")
    
    if [ "$CANCELLED_COUNT" -gt 0 ]; then
        echo "⚠️  CANCELLATION STORM DETECTED: $CANCELLED_COUNT occurrences"
        echo ""
        echo "Recent cancellations:"
        grep "Request cancelled" "$AUGMENT_LOG" 2>/dev/null | tail -5 | while read -r line; do
            TIMESTAMP=$(echo "$line" | grep -oP '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}' || echo "")
            echo "   - $TIMESTAMP"
        done
        echo ""
        echo "🔍 This indicates rapid abort() calls from webview"
    else
        echo "✅ No request cancellations"
    fi
else
    echo "⚠️  Augment log not found"
fi
echo ""

# 3. Check for terminal command timeouts
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "3. TERMINAL COMMAND TIMEOUTS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -f "$AUGMENT_LOG" ]; then
    TIMEOUT_COUNT=$(grep -c "Command timed out" "$AUGMENT_LOG" 2>/dev/null || echo "0")
    
    if [ "$TIMEOUT_COUNT" -gt 0 ]; then
        echo "⚠️  COMMAND TIMEOUTS DETECTED: $TIMEOUT_COUNT occurrences"
        echo ""
        grep "Command timed out" "$AUGMENT_LOG" 2>/dev/null | tail -5
    else
        echo "✅ No command timeouts"
    fi
fi
echo ""

# 4. Summary and diagnosis
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "DIAGNOSIS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ -f "$RENDERER_LOG" ]; then
    UNRESPONSIVE_COUNT=$(grep -c "UNRESPONSIVE.*augment" "$RENDERER_LOG" 2>/dev/null || echo "0")
    
    if [ "$UNRESPONSIVE_COUNT" -gt 0 ]; then
        echo "🔴 STALL CONFIRMED"
        echo ""
        echo "Root cause: Extension blocking event loop (96%+ CPU time)"
        echo "Symptoms:"
        echo "  - UI freezes for 4-5 seconds"
        echo "  - Tool calls get cancelled"
        echo "  - Rapid 'Request cancelled' errors"
        echo ""
        echo "Likely causes:"
        echo "  1. je(500) heuristic delay still present (check with ./detect-timeout-block.sh)"
        echo "  2. Synchronous operations in extension host"
        echo "  3. Webview → Extension communication bottleneck"
        echo ""
        echo "Next steps:"
        echo "  1. Verify patch applied: ./verify-augment-runtime.sh"
        echo "  2. Check active version: ./detect-active-version.sh"
        echo "  3. Re-patch if needed: ./patch-active-version.sh"
        echo "  4. Restart VS Code"
    else
        echo "✅ NO STALLS DETECTED"
    fi
fi

