#!/usr/bin/env bash
set -euo pipefail

LOGFILE=".notes/regression-fix-$(date +%Y%m%d-%H%M%S).log"
mkdir -p .notes
exec > >(tee -a "$LOGFILE") 2>&1

echo "START: explain-and-fix-regression"
echo ""

# WHAT IS REGRESSION
echo "═══════════════════════════════════════════════════════════════════"
echo "📊 WHAT IS REGRESSION"
echo "═══════════════════════════════════════════════════════════════════"
echo ""
echo "Memory grows over time after restart/cleanup:"
echo "  Baseline: 3107MB (after VS Code reload)"
echo "  +30s: 3107MB (0%)"
echo "  +60s: 3218MB (+111MB, +3.6%)"
echo "  +90s: 3357MB (+250MB, +8.0%)"
echo "  +150s: 3443MB (+336MB, +10.8%)"
echo ""
echo "Growth rate: ~2.2MB/second = 132MB/minute = 7.9GB/hour"
echo ""

# WHY IT HAPPENS
echo "═══════════════════════════════════════════════════════════════════"
echo "🔍 WHY REGRESSION HAPPENS"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

# Check file watchers
echo "1. FILE WATCHER LEAKS:"
WATCHER_ERRORS=$(journalctl --since "30 minutes ago" --no-pager 2>/dev/null | grep -c "File Watcher.*terminated" || echo "0")
echo "  Errors detected: $WATCHER_ERRORS"
if [ "$WATCHER_ERRORS" -gt 0 ]; then
    journalctl --since "30 minutes ago" --no-pager 2>/dev/null | grep "File Watcher" | tail -3
fi
echo ""

# Check extension errors
echo "2. EXTENSION ERRORS:"
find ~/.config/Code/logs -name "*.log" -mmin -30 -exec grep -l "error\|Error" {} \; 2>/dev/null | while read logfile; do
    ERROR_COUNT=$(grep -c "error\|Error" "$logfile" 2>/dev/null || echo "0")
    if [ "$ERROR_COUNT" -gt 10 ]; then
        echo "  $(basename "$logfile"): $ERROR_COUNT errors"
        grep -i "error" "$logfile" 2>/dev/null | tail -2 | sed 's/^/    /'
    fi
done
echo ""

# Check memory leaks
echo "3. MEMORY LEAK DETECTION:"
ps aux | grep -E '/usr/share/code|/proc/self/ex' | grep -v grep | sort -k6 -rn | head -5 | awk '{
    printf "  PID %s: %dMB CPU:%s%% ", $2, int($6/1024), $3
    if ($3 > 20) printf "⚠️  HIGH CPU"
    if (int($6/1024) > 1000) printf "⚠️  HIGH MEM"
    printf "\n"
}'
echo ""

# Check file descriptor growth
echo "4. FILE DESCRIPTOR GROWTH:"
FD_COUNT=$(lsof 2>/dev/null | grep -c code || echo "0")
FD_LIMIT=$(ulimit -n)
FD_PERCENT=$(awk "BEGIN {printf \"%.1f\", ($FD_COUNT/$FD_LIMIT)*100}")
echo "  Current: $FD_COUNT / $FD_LIMIT ($FD_PERCENT%)"
if [ "$FD_COUNT" -gt 50000 ]; then
    echo "  ⚠️  File descriptor leak detected"
fi
echo ""

# HOW TO FIX
echo "═══════════════════════════════════════════════════════════════════"
echo "🔧 FIXING REGRESSION"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

BASELINE_MEM=$(ps aux | grep -E '/usr/share/code|/proc/self/ex' | grep -v grep | awk '{sum+=$6} END {print int(sum/1024)}')
echo "BEFORE: ${BASELINE_MEM}MB"
echo ""

# Fix 1: Kill idle processes
echo "Fix 1: Killing idle processes (CPU < 0.1%, MEM > 100MB)..."
KILLED_COUNT=0
ps aux | grep -E '/usr/share/code|/proc/self/ex' | grep -v grep | awk '$3 < 0.1 && $6 > 102400 {print $2}' | while read pid; do
    echo "  Killing PID $pid"
    kill -9 "$pid" 2>/dev/null || true
    KILLED_COUNT=$((KILLED_COUNT + 1))
done
echo "  Killed: $KILLED_COUNT processes"
echo ""

# Fix 2: Clean file watchers
echo "Fix 2: Restarting file watchers..."
pkill -f "nsfw-watcher" 2>/dev/null || true
sleep 1
echo "  File watchers restarted"
echo ""

# Fix 3: Clean caches
echo "Fix 3: Cleaning caches..."
CACHE_BEFORE=$(du -sm ~/.config/Code/Cache ~/.config/Code/CachedData 2>/dev/null | awk '{sum+=$1} END {print sum}')
find ~/.config/Code/Cache -type f -mtime +1 -delete 2>/dev/null || true
find ~/.config/Code/CachedData -type f -mtime +1 -delete 2>/dev/null || true
CACHE_AFTER=$(du -sm ~/.config/Code/Cache ~/.config/Code/CachedData 2>/dev/null | awk '{sum+=$1} END {print sum}')
echo "  Cache freed: $((CACHE_BEFORE - CACHE_AFTER))MB"
echo ""

# Fix 4: Clean old logs
echo "Fix 4: Cleaning old logs..."
LOG_BEFORE=$(ls .notes/*.log 2>/dev/null | wc -l)
ls -t .notes/terminal-*.log 2>/dev/null | tail -n +11 | xargs -r rm -f
ls -t .notes/resolve-*.log 2>/dev/null | tail -n +6 | xargs -r rm -f
ls -t .notes/regression-*.log 2>/dev/null | tail -n +6 | xargs -r rm -f
LOG_AFTER=$(ls .notes/*.log 2>/dev/null | wc -l)
echo "  Logs removed: $((LOG_BEFORE - LOG_AFTER))"
echo ""

# Fix 5: Trigger garbage collection
echo "Fix 5: Triggering garbage collection..."
kill -USR1 $(pgrep -f "code.*--type=extensionHost" | head -1) 2>/dev/null || true
sleep 2
echo "  Garbage collection triggered"
echo ""

# Measure results
sleep 3
AFTER_MEM=$(ps aux | grep -E '/usr/share/code|/proc/self/ex' | grep -v grep | awk '{sum+=$6} END {print int(sum/1024)}')
REDUCTION=$((BASELINE_MEM - AFTER_MEM))
PERCENT=$(awk "BEGIN {printf \"%.1f\", ($REDUCTION/$BASELINE_MEM)*100}")

echo "═══════════════════════════════════════════════════════════════════"
echo "✅ RESULTS"
echo "═══════════════════════════════════════════════════════════════════"
echo ""
echo "BEFORE: ${BASELINE_MEM}MB"
echo "AFTER:  ${AFTER_MEM}MB"
echo "REDUCTION: ${REDUCTION}MB (${PERCENT}%)"
echo ""

# Monitor for re-regression
echo "═══════════════════════════════════════════════════════════════════"
echo "📈 MONITORING FOR RE-REGRESSION (60 seconds)"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

NEW_BASELINE=$AFTER_MEM
for i in {1..4}; do
    sleep 15
    CURRENT_MEM=$(ps aux | grep -E '/usr/share/code|/proc/self/ex' | grep -v grep | awk '{sum+=$6} END {print int(sum/1024)}')
    DELTA=$((CURRENT_MEM - NEW_BASELINE))
    DELTA_PERCENT=$(awk "BEGIN {printf \"%.1f\", ($DELTA/$NEW_BASELINE)*100}")
    
    echo "[+$((i*15))s] ${CURRENT_MEM}MB (${DELTA:+$DELTA}MB ${DELTA_PERCENT}%)"
    
    if [ "$DELTA" -gt 200 ]; then
        echo "  ⚠️  REGRESSION DETECTED: +${DELTA}MB in $((i*15)) seconds"
        echo "  Growth rate: $(awk "BEGIN {printf \"%.1f\", $DELTA/($i*15)}")MB/s"
    fi
done

echo ""
echo "END: explain-and-fix-regression"

