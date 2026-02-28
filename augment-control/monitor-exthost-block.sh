#!/usr/bin/env bash
# Monitor Extension Host Event Loop Blocking
# Detects when extension host CPU usage exceeds threshold

set -euo pipefail

THRESHOLD=90
LOG_FILE="$HOME/.edc/exthost-monitor.log"
mkdir -p "$(dirname "$LOG_FILE")"

echo "╔════════════════════════════════════════════════════════════════════════════╗"
echo "║                    EXTENSION HOST MONITOR                                  ║"
echo "╚════════════════════════════════════════════════════════════════════════════╝"
echo ""

# Find extension host process
PID=$(pgrep -f "extensionHost" | head -1)

if [ -z "$PID" ]; then
    echo "❌ Extension host process not found"
    echo ""
    echo "Is VS Code running?"
    exit 1
fi

echo "✅ Monitoring extension host PID: $PID"
echo "⚠️  Threshold: ${THRESHOLD}% CPU"
echo "📝 Logging to: $LOG_FILE"
echo ""
echo "Press Ctrl+C to stop"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

BLOCK_COUNT=0

while true; do
    # Check if process still exists
    if ! kill -0 "$PID" 2>/dev/null; then
        echo ""
        echo "⚠️  Extension host process terminated"
        break
    fi
    
    # Get CPU usage
    CPU=$(ps -p "$PID" -o %cpu= 2>/dev/null | awk '{print int($1)}' || echo "0")
    
    if [ "$CPU" -gt "$THRESHOLD" ]; then
        TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
        BLOCK_COUNT=$((BLOCK_COUNT + 1))
        
        echo "🔴 $TIMESTAMP - BLOCKING: ${CPU}% CPU (event #$BLOCK_COUNT)"
        echo "$TIMESTAMP|PID=$PID|CPU=${CPU}%|BLOCK_EVENT=$BLOCK_COUNT" >> "$LOG_FILE"
        
        # Check if Augment extension is the culprit
        AUGMENT_PID=$(pgrep -f "augment.vscode-augment" 2>/dev/null || echo "")
        if [ -n "$AUGMENT_PID" ]; then
            echo "   └─ Augment extension active"
        fi
    else
        # Show normal status every 5 seconds
        if [ $((SECONDS % 5)) -eq 0 ]; then
            echo "✅ $(date '+%H:%M:%S') - Normal: ${CPU}% CPU"
        fi
    fi
    
    sleep 1
done

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "SUMMARY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Total blocking events: $BLOCK_COUNT"
echo "Log file: $LOG_FILE"

