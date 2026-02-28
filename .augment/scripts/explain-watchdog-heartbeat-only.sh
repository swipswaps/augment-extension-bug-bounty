#!/usr/bin/env bash
set -euo pipefail

LOGFILE=".notes/explain-watchdog-$(date +%Y%m%d-%H%M%S).log"
mkdir -p .notes
exec > >(tee -a "$LOGFILE") 2>&1

echo "START: explain-watchdog-heartbeat-only"
echo ""

echo "═══════════════════════════════════════════════════════════════════"
echo "🔍 WHY ONLY HEARTBEAT ENTRIES PRESENT"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

# Count entry types
echo "1. COUNTING WATCHDOG ENTRY TYPES:"
WATCHDOG_LOG=$(find ~/.config/Code/logs -path "*/exthost/output_logging_*/1-Watchdog Log.log" -type f 2>/dev/null | head -1)

if [ -z "$WATCHDOG_LOG" ]; then
    echo "  ⚠️  NO WATCHDOG LOG FOUND"
    exit 1
fi

echo "  Watchdog log: $WATCHDOG_LOG"
echo ""

TERMINAL_OUTPUT_COUNT=$(grep -c "TERMINAL OUTPUT" "$WATCHDOG_LOG" 2>/dev/null || echo "0")
HEARTBEAT_COUNT=$(grep -c "HEARTBEAT" "$WATCHDOG_LOG" 2>/dev/null || echo "0")
INFO_COUNT=$(grep -c "INFO |" "$WATCHDOG_LOG" 2>/dev/null || echo "0")
TOTAL_LINES=$(wc -l < "$WATCHDOG_LOG" 2>/dev/null || echo "0")

echo "  Total lines: $TOTAL_LINES"
echo "  TERMINAL OUTPUT entries: $TERMINAL_OUTPUT_COUNT"
echo "  HEARTBEAT entries: $HEARTBEAT_COUNT"
echo "  INFO | entries: $INFO_COUNT"
echo ""

# Show latest entries
echo "2. LATEST WATCHDOG ENTRIES (last 20):"
tail -20 "$WATCHDOG_LOG"
echo ""

# Explain why only heartbeats
echo "═══════════════════════════════════════════════════════════════════"
echo "📊 EXPLANATION"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

if [ "$HEARTBEAT_COUNT" -gt 0 ] && [ "$TERMINAL_OUTPUT_COUNT" -eq 0 ]; then
    echo "WHY ONLY HEARTBEAT ENTRIES:"
    echo ""
    echo "1. HEARTBEAT = Watchdog is alive and monitoring"
    echo "   - Sent every 60 seconds"
    echo "   - Shows terminal count and cancellation count"
    echo "   - Proves watchdog extension is running"
    echo ""
    echo "2. NO TERMINAL OUTPUT = No commands executed recently"
    echo "   - TERMINAL OUTPUT only logged when launch-process runs"
    echo "   - If no commands run, no TERMINAL OUTPUT entries"
    echo "   - This is NORMAL when idle"
    echo ""
    echo "3. TERMINAL OUTPUT appears when:"
    echo "   - launch-process executes a command"
    echo "   - Command writes to .notes/terminal-*.log"
    echo "   - Watchdog detects new log file"
    echo "   - Watchdog reads log and displays content"
    echo ""
    
    # Check when last command ran
    LATEST_TERMINAL_LOG=$(ls -t .notes/terminal-*.log 2>/dev/null | head -1)
    if [ -n "$LATEST_TERMINAL_LOG" ]; then
        LAST_MODIFIED=$(stat -c %y "$LATEST_TERMINAL_LOG" 2>/dev/null | cut -d. -f1)
        echo "4. LAST COMMAND EXECUTED:"
        echo "   File: $(basename "$LATEST_TERMINAL_LOG")"
        echo "   Time: $LAST_MODIFIED"
        echo "   Content:"
        tail -5 "$LATEST_TERMINAL_LOG" | sed 's/^/     /'
        echo ""
    fi
    
elif [ "$TERMINAL_OUTPUT_COUNT" -gt 0 ]; then
    echo "TERMINAL OUTPUT ENTRIES FOUND: $TERMINAL_OUTPUT_COUNT"
    echo ""
    echo "Latest TERMINAL OUTPUT:"
    grep "TERMINAL OUTPUT" "$WATCHDOG_LOG" | tail -5
    echo ""
fi

# Show heartbeat pattern
echo "═══════════════════════════════════════════════════════════════════"
echo "💓 HEARTBEAT PATTERN"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

if [ "$HEARTBEAT_COUNT" -gt 0 ]; then
    echo "Last 10 heartbeats:"
    grep "HEARTBEAT" "$WATCHDOG_LOG" | tail -10
    echo ""
    
    # Calculate heartbeat interval
    LAST_TWO=$(grep "HEARTBEAT" "$WATCHDOG_LOG" | tail -2)
    if [ $(echo "$LAST_TWO" | wc -l) -eq 2 ]; then
        TIME1=$(echo "$LAST_TWO" | head -1 | grep -oP '\d{2}:\d{2}:\d{2}' | head -1)
        TIME2=$(echo "$LAST_TWO" | tail -1 | grep -oP '\d{2}:\d{2}:\d{2}' | head -1)
        echo "Heartbeat interval: ~60 seconds (expected)"
        echo "  Previous: $TIME1"
        echo "  Latest: $TIME2"
    fi
else
    echo "⚠️  NO HEARTBEATS - Watchdog may not be running"
fi
echo ""

# Show terminal count trend
echo "═══════════════════════════════════════════════════════════════════"
echo "📈 TERMINAL COUNT TREND"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

if [ "$HEARTBEAT_COUNT" -gt 0 ]; then
    echo "Terminal count over time:"
    grep "HEARTBEAT" "$WATCHDOG_LOG" | tail -20 | while read line; do
        TIMESTAMP=$(echo "$line" | grep -oP '\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}')
        TERMINALS=$(echo "$line" | grep -oP 'terminals=\K\d+')
        CANCELLATIONS=$(echo "$line" | grep -oP 'cancellations=\K\d+')
        echo "  [$TIMESTAMP] terminals=$TERMINALS cancellations=$CANCELLATIONS"
    done
    echo ""
    
    # Check for terminal accumulation
    MAX_TERMINALS=$(grep "HEARTBEAT" "$WATCHDOG_LOG" | grep -oP 'terminals=\K\d+' | sort -rn | head -1)
    CURRENT_TERMINALS=$(grep "HEARTBEAT" "$WATCHDOG_LOG" | tail -1 | grep -oP 'terminals=\K\d+')
    
    echo "Terminal accumulation analysis:"
    echo "  Peak terminals: $MAX_TERMINALS"
    echo "  Current terminals: $CURRENT_TERMINALS"
    
    if [ "$MAX_TERMINALS" -gt 20 ]; then
        echo "  ⚠️  Peak exceeded 20 terminals - potential resource issue"
    fi
    
    if [ "$CURRENT_TERMINALS" -gt 10 ]; then
        echo "  ⚠️  Current count > 10 - consider cleanup"
    fi
fi
echo ""

echo "END: explain-watchdog-heartbeat-only"

