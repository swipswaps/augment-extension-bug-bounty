#!/usr/bin/env bash
# Comprehensive system monitoring using ALL available tools
# NOT just htop snapshots

set -euo pipefail

LOGDIR=".notes"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
REPORT="$LOGDIR/comprehensive-monitor-$TIMESTAMP.log"

echo "═══════════════════════════════════════════════════════════════════" | tee "$REPORT"
echo "🔍 COMPREHENSIVE SYSTEM MONITORING" | tee -a "$REPORT"
echo "═══════════════════════════════════════════════════════════════════" | tee -a "$REPORT"
echo "" | tee -a "$REPORT"
echo "Timestamp: $(date)" | tee -a "$REPORT"
echo "Report: $REPORT" | tee -a "$REPORT"
echo "" | tee -a "$REPORT"

# 1. Current VS Code Memory
echo "1️⃣ VS CODE MEMORY (current snapshot):" | tee -a "$REPORT"
ps aux | grep -E '/usr/share/code|/proc/self/ex' | grep -v grep | awk '{print "  PID", $2, ":", $6/1024, "MB -", $11}' | tee -a "$REPORT"
VSCODE_MEM=$(ps aux | grep -E '/usr/share/code|/proc/self/ex' | grep -v grep | awk '{sum+=$6} END {print int(sum/1024)}')
echo "  TOTAL: ${VSCODE_MEM}MB" | tee -a "$REPORT"
echo "" | tee -a "$REPORT"

# 2. System Memory
echo "2️⃣ SYSTEM MEMORY:" | tee -a "$REPORT"
free -h | tee -a "$REPORT"
echo "" | tee -a "$REPORT"

# 3. Load Average
echo "3️⃣ LOAD AVERAGE:" | tee -a "$REPORT"
uptime | tee -a "$REPORT"
echo "" | tee -a "$REPORT"

# 4. OOM Killer Events
echo "4️⃣ OOM KILLER EVENTS (last 30 min):" | tee -a "$REPORT"
journalctl --since "30 minutes ago" 2>/dev/null | grep -i "oom\|killed" | tail -10 | tee -a "$REPORT" || echo "  No OOM events" | tee -a "$REPORT"
echo "" | tee -a "$REPORT"

# 5. VS Code Crashes
echo "5️⃣ VS CODE CRASHES (last 30 min):" | tee -a "$REPORT"
journalctl --since "30 minutes ago" 2>/dev/null | grep -i "code.*segfault\|code.*crash\|code.*core dump" | tail -10 | tee -a "$REPORT" || echo "  No crashes detected" | tee -a "$REPORT"
echo "" | tee -a "$REPORT"

# 6. Kernel Memory Events
echo "6️⃣ KERNEL MEMORY EVENTS (last 100 lines):" | tee -a "$REPORT"
dmesg -T 2>/dev/null | tail -100 | grep -i "memory\|oom\|killed" | tail -10 | tee -a "$REPORT" || echo "  No kernel memory events" | tee -a "$REPORT"
echo "" | tee -a "$REPORT"

# 7. Swap Activity
echo "7️⃣ SWAP ACTIVITY (5 samples, 1 sec interval):" | tee -a "$REPORT"
vmstat 1 5 | tee -a "$REPORT"
echo "" | tee -a "$REPORT"

# 8. File Descriptor Count
echo "8️⃣ FILE DESCRIPTOR COUNT:" | tee -a "$REPORT"
FD_COUNT=$(lsof 2>/dev/null | grep -E '/usr/share/code|/proc/self/ex' | wc -l || echo "0")
echo "  VS Code file descriptors: $FD_COUNT" | tee -a "$REPORT"
echo "" | tee -a "$REPORT"

# 9. Process Count
echo "9️⃣ PROCESS COUNT:" | tee -a "$REPORT"
PROC_COUNT=$(ps aux | grep -E '/usr/share/code|/proc/self/ex' | grep -v grep | wc -l)
echo "  VS Code processes: $PROC_COUNT" | tee -a "$REPORT"
echo "" | tee -a "$REPORT"

# 10. Log File Accumulation
echo "🔟 LOG FILE ACCUMULATION:" | tee -a "$REPORT"
LOG_COUNT=$(ls -1 .notes/terminal-*.log 2>/dev/null | wc -l || echo "0")
LOG_SIZE=$(du -sh .notes/terminal-*.log 2>/dev/null | tail -1 | awk '{print $1}' || echo "0")
echo "  Terminal logs: $LOG_COUNT files, $LOG_SIZE total" | tee -a "$REPORT"
echo "" | tee -a "$REPORT"

# 11. Recent System Errors
echo "1️⃣1️⃣ RECENT SYSTEM ERRORS (last 30 min):" | tee -a "$REPORT"
journalctl -p err --since "30 minutes ago" 2>/dev/null | tail -20 | tee -a "$REPORT" || echo "  No recent errors" | tee -a "$REPORT"
echo "" | tee -a "$REPORT"

# 12. Memory Trend (if baseline exists)
echo "1️⃣2️⃣ MEMORY TREND ANALYSIS:" | tee -a "$REPORT"
if [ -f .notes/vscode-memory-baseline.txt ]; then
  BASELINE=$(cat .notes/vscode-memory-baseline.txt)
  DIFF=$((VSCODE_MEM - BASELINE))
  DIFF_PCT=$(awk "BEGIN {printf \"%.1f\", ($DIFF/$BASELINE)*100}")
  echo "  Baseline: ${BASELINE}MB" | tee -a "$REPORT"
  echo "  Current: ${VSCODE_MEM}MB" | tee -a "$REPORT"
  echo "  Change: ${DIFF}MB (${DIFF_PCT}%)" | tee -a "$REPORT"
  
  if [ $DIFF -gt 500 ]; then
    echo "  🚨 REGRESSION DETECTED: +${DIFF}MB" | tee -a "$REPORT"
  elif [ $DIFF -lt -500 ]; then
    echo "  ✅ IMPROVEMENT: ${DIFF}MB" | tee -a "$REPORT"
  else
    echo "  ✅ STABLE (within 500MB)" | tee -a "$REPORT"
  fi
else
  echo "  No baseline set. Setting baseline to ${VSCODE_MEM}MB" | tee -a "$REPORT"
  echo "$VSCODE_MEM" > .notes/vscode-memory-baseline.txt
fi
echo "" | tee -a "$REPORT"

echo "═══════════════════════════════════════════════════════════════════" | tee -a "$REPORT"
echo "✅ COMPREHENSIVE MONITORING COMPLETE" | tee -a "$REPORT"
echo "═══════════════════════════════════════════════════════════════════" | tee -a "$REPORT"
echo "" | tee -a "$REPORT"
echo "Report saved to: $REPORT" | tee -a "$REPORT"

exit 0

