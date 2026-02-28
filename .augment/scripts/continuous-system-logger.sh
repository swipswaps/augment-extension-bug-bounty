#!/usr/bin/env bash
# Continuous system logger - logs ALL relevant messages to resolve resource contention
set -euo pipefail

LOGFILE=".notes/system-monitor-$(date +%Y%m%d-%H%M%S).log"
mkdir -p .notes

# Start logging with tee (visible to user)
exec > >(tee -a "$LOGFILE") 2>&1

echo "START: continuous-system-logger"
echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
echo "Log file: $LOGFILE"
echo "Press Ctrl+C to stop"
echo ""

while true; do
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    echo "═══════════════════════════════════════════════════════════════════"
    echo "[$TIMESTAMP] SYSTEM STATUS"
    echo "═══════════════════════════════════════════════════════════════════"
    
    # VS Code memory and processes
    echo ""
    echo "VS CODE PROCESSES:"
    ps aux | grep -E '/usr/share/code|/proc/self/ex' | grep -v grep | awk '{printf "  PID %s: %dMB CPU:%s%% %s\n", $2, int($6/1024), $3, $11}' | head -10
    VSCODE_TOTAL=$(ps aux | grep -E '/usr/share/code|/proc/self/ex' | grep -v grep | awk '{sum+=$6} END {print int(sum/1024)}')
    VSCODE_COUNT=$(ps aux | grep -E '/usr/share/code|/proc/self/ex' | grep -v grep | wc -l)
    echo "  TOTAL: ${VSCODE_TOTAL}MB across ${VSCODE_COUNT} processes"
    
    # System memory
    echo ""
    echo "SYSTEM MEMORY:"
    free -h | grep -E "Mem|Swap"
    
    # Load average
    echo ""
    echo "LOAD AVERAGE:"
    uptime
    
    # Recent errors from journalctl
    echo ""
    echo "SYSTEM ERRORS (last 60 seconds):"
    journalctl -p err --since "60 seconds ago" --no-pager 2>/dev/null | tail -5 || echo "  (no errors)"
    
    # OOM events
    echo ""
    echo "OOM EVENTS (last 60 seconds):"
    journalctl --since "60 seconds ago" --no-pager 2>/dev/null | grep -i "oom\|killed" | tail -3 || echo "  (no OOM events)"
    
    # Kernel errors
    echo ""
    echo "KERNEL ERRORS (last 60 seconds):"
    dmesg -T 2>/dev/null | tail -100 | grep -i "error\|fail\|oom" | tail -3 || echo "  (no kernel errors)"
    
    # Swap activity
    echo ""
    echo "SWAP ACTIVITY:"
    vmstat 1 2 | tail -1 | awk '{printf "  swap-in: %s KB/s, swap-out: %s KB/s\n", $7, $8}'
    
    # File descriptors
    echo ""
    echo "FILE DESCRIPTORS:"
    FD_COUNT=$(lsof 2>/dev/null | grep -c code || echo "0")
    echo "  VS Code: ${FD_COUNT} open files"
    
    # VS Code extension logs (errors only)
    echo ""
    echo "VS CODE EXTENSION ERRORS (last 60 seconds):"
    find ~/.config/Code -name "*.log" -mmin -1 2>/dev/null | while read logfile; do
        if grep -i "error\|exception\|fail" "$logfile" 2>/dev/null | tail -2 | grep -q .; then
            echo "  $(basename "$logfile"):"
            grep -i "error\|exception\|fail" "$logfile" 2>/dev/null | tail -2 | sed 's/^/    /'
        fi
    done || echo "  (no extension errors)"
    
    # Alert if threshold exceeded
    echo ""
    if [ "$VSCODE_TOTAL" -gt 4000 ]; then
        echo "⚠️  ALERT: VS Code memory ${VSCODE_TOTAL}MB exceeds 4000MB threshold"
    fi
    if [ "$VSCODE_COUNT" -gt 30 ]; then
        echo "⚠️  ALERT: VS Code process count ${VSCODE_COUNT} exceeds 30 threshold"
    fi
    if [ "$FD_COUNT" -gt 60000 ]; then
        echo "⚠️  ALERT: File descriptor count ${FD_COUNT} exceeds 60000 threshold"
    fi
    
    echo ""
    sleep 30
done

