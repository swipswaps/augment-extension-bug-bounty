#!/usr/bin/env bash
# Transparent Resource Monitor - Shows ACTUAL memory in visible terminal
# No hidden databases, no false claims, only what user can see

set -euo pipefail

LOGDIR=".notes"
INTERVAL="${1:-60}"  # Default 60 seconds

echo "═══════════════════════════════════════════════════════════════════"
echo "🔍 TRANSPARENT RESOURCE MONITOR"
echo "═══════════════════════════════════════════════════════════════════"
echo ""
echo "Monitoring every ${INTERVAL} seconds"
echo "Press Ctrl+C to stop"
echo ""
echo "Timestamp          | VS Code MB | Total GB | Load Avg | Logs | Procs"
echo "-------------------+------------+----------+----------+------+-------"

while true; do
    # Get VS Code memory (visible calculation)
    VSCODE_MB=$(ps aux | grep -E '/usr/share/code|/proc/self/ex' | grep -v grep | awk '{sum+=$6} END {print int(sum/1024)}')
    
    # Get total memory from free (visible)
    TOTAL_GB=$(free -h | grep Mem | awk '{print $3}')
    
    # Get load average (visible)
    LOAD=$(uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $2}' | tr -d ' ')
    
    # Get log count (visible)
    LOG_COUNT=$(ls -1 "$LOGDIR"/terminal-*.log 2>/dev/null | wc -l || echo "0")
    
    # Get process count (visible)
    PROC_COUNT=$(ps aux | grep -E '/usr/share/code|/proc/self/ex' | grep -v grep | wc -l)
    
    # Print to terminal (visible to user)
    printf "%s | %10s | %8s | %8s | %4s | %5s\n" \
        "$(date '+%Y-%m-%d %H:%M:%S')" \
        "${VSCODE_MB}" \
        "${TOTAL_GB}" \
        "${LOAD}" \
        "${LOG_COUNT}" \
        "${PROC_COUNT}"
    
    # Also show top 5 memory hogs (visible)
    if [ $((VSCODE_MB)) -gt 4000 ]; then
        echo ""
        echo "⚠️  MEMORY OVER 4000MB - Top 5 processes:"
        ps aux | grep -E '/usr/share/code|/proc/self/ex' | grep -v grep | sort -k6 -rn | head -5 | awk '{printf "  PID %s: %dMB - %s\n", $2, int($6/1024), $11}'
        echo ""
        echo "Timestamp          | VS Code MB | Total GB | Load Avg | Logs | Procs"
        echo "-------------------+------------+----------+----------+------+-------"
    fi
    
    sleep "$INTERVAL"
done

