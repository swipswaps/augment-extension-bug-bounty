#!/usr/bin/env bash
# Show all relevant logs for troubleshooting
set -euo pipefail

echo "START: show-logs"
echo "═══════════════════════════════════════════════════════════════════"
echo "📋 SYSTEM & APPLICATION LOGS"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

# 1. Recent system errors
echo "1. SYSTEM ERRORS (last 5 minutes):"
journalctl -p err --since "5 minutes ago" --no-pager 2>/dev/null | tail -10 || echo "  (no errors)"
echo ""

# 2. OOM events
echo "2. OOM EVENTS (last 30 minutes):"
journalctl --since "30 minutes ago" --no-pager 2>/dev/null | grep -i "oom\|killed\|out of memory" | tail -10 || echo "  (no OOM events)"
echo ""

# 3. Kernel errors
echo "3. KERNEL ERRORS (recent):"
dmesg -T 2>/dev/null | tail -50 | grep -iE "error|fail|oom|killed" | tail -10 || echo "  (no kernel errors)"
echo ""

# 4. VS Code extension errors
echo "4. VS CODE EXTENSION ERRORS:"
echo ""
echo "  Augment extension:"
tail -20 ~/.config/Code/logs/*/exthost/Augment.log 2>/dev/null | grep -i error || echo "    (no errors)"
echo ""
echo "  All extension errors (last 50 lines):"
find ~/.config/Code/logs -name "*.log" -type f -exec tail -50 {} \; 2>/dev/null | grep -i "error\|exception\|fail" | tail -15 || echo "    (no errors)"
echo ""

# 5. VS Code crashes
echo "5. VS CODE CRASHES (last 30 minutes):"
journalctl --since "30 minutes ago" --no-pager 2>/dev/null | grep -iE "code.*segfault|code.*crash|code.*core" | tail -10 || echo "  (no crashes)"
echo ""

# 6. Resource monitoring logs
echo "6. RESOURCE MONITORING LOGS:"
echo ""
if ls .notes/auto-resolve-*.log 1>/dev/null 2>&1; then
    echo "  Latest auto-resolve log:"
    tail -30 "$(ls -t .notes/auto-resolve-*.log | head -1)"
else
    echo "  (no auto-resolve logs)"
fi
echo ""

if ls .notes/resource-diagnosis-*.log 1>/dev/null 2>&1; then
    echo "  Latest diagnosis log:"
    tail -30 "$(ls -t .notes/resource-diagnosis-*.log | head -1)"
else
    echo "  (no diagnosis logs)"
fi
echo ""

# 7. Current state
echo "7. CURRENT STATE:"
VSCODE_MEM=$(ps aux | grep -E '/usr/share/code|/proc/self/ex' | grep -v grep | awk '{sum+=$6} END {print int(sum/1024)}')
VSCODE_PROCS=$(ps aux | grep -E '/usr/share/code|/proc/self/ex' | grep -v grep | wc -l)
FD_COUNT=$(lsof 2>/dev/null | grep -c code || echo "0")
echo "  VS Code: ${VSCODE_MEM}MB, ${VSCODE_PROCS} processes, ${FD_COUNT} file descriptors"
free -h | grep -E "Mem|Swap"
uptime
echo ""

echo "END: show-logs"

