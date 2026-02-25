#!/usr/bin/env bash

# monitor-fd-leak-realtime.sh
# Real-time monitoring to correlate FD growth with AbortErrors

LOGFILE=".notes/fd-leak-monitor-$(date +%Y%m%d-%H%M%S).log"

echo "=========================================="
echo "REAL-TIME FD LEAK MONITOR"
echo "=========================================="
echo "Logging to: $LOGFILE"
echo "Press Ctrl+C to stop"
echo ""

# Get baseline
BASELINE_FD=$(lsof 2>/dev/null | grep -c code)
BASELINE_TIME=$(date +%s)

echo "[$(date -Iseconds)] BASELINE: $BASELINE_FD FDs" | tee -a "$LOGFILE"

# Monitor VS Code logs for AbortErrors in real-time
tail -f ~/.config/Code/logs/*/exthost/output_logging_*/1-Augment.log 2>/dev/null | while read -r line; do
    if echo "$line" | grep -q "AbortError\|getRemoteAgentOverviewsStream\|This operation was aborted"; then
        CURRENT_FD=$(lsof 2>/dev/null | grep -c code)
        CURRENT_TIME=$(date +%s)
        ELAPSED=$((CURRENT_TIME - BASELINE_TIME))
        GROWTH=$((CURRENT_FD - BASELINE_FD))
        RATE=$(echo "scale=2; $GROWTH / ($ELAPSED / 60.0)" | bc 2>/dev/null || echo "N/A")
        
        echo "[$(date -Iseconds)] AbortError detected! FD=$CURRENT_FD (+$GROWTH) Rate=${RATE}/min" | tee -a "$LOGFILE"
        echo "  Log: $line" | tee -a "$LOGFILE"
    fi
done &

TAIL_PID=$!

# Also monitor FD count every 10 seconds
while true; do
    sleep 10
    CURRENT_FD=$(lsof 2>/dev/null | grep -c code)
    CURRENT_TIME=$(date +%s)
    ELAPSED=$((CURRENT_TIME - BASELINE_TIME))
    GROWTH=$((CURRENT_FD - BASELINE_FD))
    RATE=$(echo "scale=2; $GROWTH / ($ELAPSED / 60.0)" | bc 2>/dev/null || echo "N/A")
    
    echo "[$(date -Iseconds)] FD=$CURRENT_FD (+$GROWTH from baseline) Rate=${RATE}/min Elapsed=${ELAPSED}s" | tee -a "$LOGFILE"
    
    # Check for runaway zygotes
    ZYGOTES=$(ps aux | grep -E "code.*zygote" | grep -v grep | awk '{if ($3 > 5.0) printf "PID %s: CPU %.1f%% ", $2, $3}')
    if [ -n "$ZYGOTES" ]; then
        echo "[$(date -Iseconds)] RUNAWAY ZYGOTES: $ZYGOTES" | tee -a "$LOGFILE"
    fi
    
    # Alert if growth is rapid
    if [ "$GROWTH" -gt 1000 ]; then
        echo "[$(date -Iseconds)] ⚠️  ALERT: FD growth exceeds 1000! Consider reloading VS Code" | tee -a "$LOGFILE"
    fi
done

# Cleanup on exit
trap "kill $TAIL_PID 2>/dev/null; echo 'Monitor stopped'; exit" INT TERM

