#!/bin/bash
# monitor-fd-leak.sh
# WHAT: Monitor file descriptor count every 5 seconds
# WHY: Track FD leak in real-time
# HOW: Loop lsof count, log to file

LOGFILE=".notes/fd-monitor-$(date +%Y%m%d-%H%M%S).log"

echo "Monitoring FD count (Ctrl+C to stop)..."
echo "Log file: $LOGFILE"
echo ""

while true; do
    TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
    FD_COUNT=$(lsof 2>/dev/null | wc -l)
    echo "$TIMESTAMP - FD count: $FD_COUNT" | tee -a "$LOGFILE"
    sleep 5
done
