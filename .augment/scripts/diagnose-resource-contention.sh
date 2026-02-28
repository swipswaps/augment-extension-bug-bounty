#!/usr/bin/env bash
# Diagnose resource contention - one-shot comprehensive analysis
set -euo pipefail

LOGFILE=".notes/resource-diagnosis-$(date +%Y%m%d-%H%M%S).log"
mkdir -p .notes

# Start logging with tee (visible to user)
exec > >(tee -a "$LOGFILE") 2>&1

echo "START: diagnose-resource-contention"
echo "═══════════════════════════════════════════════════════════════════"
echo "🔍 RESOURCE CONTENTION DIAGNOSIS"
echo "═══════════════════════════════════════════════════════════════════"
echo "Timestamp: $(date '+%Y-%m-%d %H:%M:%S')"
echo "Log file: $LOGFILE"
echo ""

# 1. Current VS Code state
echo "1. VS CODE CURRENT STATE:"
echo "---"
ps aux | grep -E '/usr/share/code|/proc/self/ex' | grep -v grep | sort -k6 -rn | head -15 | awk '{printf "  PID %s: %dMB CPU:%s%% STAT:%s CMD:%s\n", $2, int($6/1024), $3, $8, $11}'
VSCODE_TOTAL=$(ps aux | grep -E '/usr/share/code|/proc/self/ex' | grep -v grep | awk '{sum+=$6} END {print int(sum/1024)}')
VSCODE_COUNT=$(ps aux | grep -E '/usr/share/code|/proc/self/ex' | grep -v grep | wc -l)
echo ""
echo "  TOTAL MEMORY: ${VSCODE_TOTAL}MB"
echo "  PROCESS COUNT: ${VSCODE_COUNT}"
echo ""

# 2. System memory state
echo "2. SYSTEM MEMORY STATE:"
echo "---"
free -h
echo ""
vmstat 1 3 | tail -2
echo ""

# 3. Recent system errors (last 15 minutes)
echo "3. SYSTEM ERRORS (last 15 minutes):"
echo "---"
journalctl -p err --since "15 minutes ago" --no-pager 2>/dev/null | tail -20 || echo "  (no errors)"
echo ""

# 4. OOM events (last 15 minutes)
echo "4. OOM EVENTS (last 15 minutes):"
echo "---"
journalctl --since "15 minutes ago" --no-pager 2>/dev/null | grep -i "oom\|killed\|out of memory" | tail -10 || echo "  (no OOM events)"
echo ""

# 5. Kernel errors (last 100 lines)
echo "5. KERNEL ERRORS (recent):"
echo "---"
dmesg -T 2>/dev/null | tail -100 | grep -iE "error|fail|oom|killed|segfault" | tail -10 || echo "  (no kernel errors)"
echo ""

# 6. VS Code crashes (last 15 minutes)
echo "6. VS CODE CRASHES (last 15 minutes):"
echo "---"
journalctl --since "15 minutes ago" --no-pager 2>/dev/null | grep -iE "code.*segfault|code.*crash|code.*core dump" | tail -10 || echo "  (no crashes)"
echo ""

# 7. File descriptor usage
echo "7. FILE DESCRIPTOR USAGE:"
echo "---"
FD_TOTAL=$(lsof 2>/dev/null | wc -l || echo "0")
FD_CODE=$(lsof 2>/dev/null | grep -c code || echo "0")
FD_LIMIT=$(ulimit -n)
echo "  Total open files: ${FD_TOTAL}"
echo "  VS Code open files: ${FD_CODE}"
echo "  System limit: ${FD_LIMIT}"
echo "  Usage: $(awk "BEGIN {printf \"%.1f%%\", ($FD_TOTAL/$FD_LIMIT)*100}")"
echo ""

# 8. Swap activity
echo "8. SWAP ACTIVITY:"
echo "---"
SWAP_USED=$(free -m | grep Swap | awk '{print $3}')
SWAP_TOTAL=$(free -m | grep Swap | awk '{print $2}')
echo "  Swap used: ${SWAP_USED}MB / ${SWAP_TOTAL}MB"
vmstat 1 5 | tail -3
echo ""

# 9. VS Code extension logs (errors)
echo "9. VS CODE EXTENSION ERRORS (last 15 minutes):"
echo "---"
find ~/.config/Code -name "*.log" -mmin -15 2>/dev/null | while read logfile; do
    ERROR_COUNT=$(grep -ic "error\|exception\|fail" "$logfile" 2>/dev/null || echo "0")
    if [ "$ERROR_COUNT" -gt 0 ]; then
        echo "  $(basename "$logfile"): ${ERROR_COUNT} errors"
        grep -i "error\|exception\|fail" "$logfile" 2>/dev/null | tail -3 | sed 's/^/    /'
        echo ""
    fi
done || echo "  (no extension errors)"
echo ""

# 10. Process tree (VS Code hierarchy)
echo "10. VS CODE PROCESS TREE:"
echo "---"
pstree -p $(pgrep -f "/usr/share/code/code" | head -1) 2>/dev/null | head -20 || echo "  (unable to generate tree)"
echo ""

# 11. Top memory consumers (all processes)
echo "11. TOP 10 MEMORY CONSUMERS (all processes):"
echo "---"
ps aux | sort -k6 -rn | head -10 | awk '{printf "  PID %s: %dMB CPU:%s%% %s\n", $2, int($6/1024), $3, $11}'
echo ""

# 12. Recommendations
echo "═══════════════════════════════════════════════════════════════════"
echo "🔧 RECOMMENDATIONS:"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

if [ "$VSCODE_TOTAL" -gt 4000 ]; then
    echo "⚠️  VS Code memory (${VSCODE_TOTAL}MB) exceeds 4000MB threshold"
    echo "   → Kill idle processes or reload VS Code window"
fi

if [ "$VSCODE_COUNT" -gt 30 ]; then
    echo "⚠️  VS Code process count (${VSCODE_COUNT}) exceeds 30 threshold"
    echo "   → Check for zombie processes or extension host leaks"
fi

if [ "$FD_CODE" -gt 50000 ]; then
    echo "⚠️  File descriptor count (${FD_CODE}) exceeds 50000 threshold"
    echo "   → Check for file watcher leaks or log file accumulation"
fi

if [ "$SWAP_USED" -gt 500 ]; then
    echo "⚠️  Swap usage (${SWAP_USED}MB) indicates memory pressure"
    echo "   → Close applications or add more RAM"
fi

echo ""
echo "END: diagnose-resource-contention"

