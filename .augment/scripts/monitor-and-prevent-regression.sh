#!/usr/bin/env bash
set -euo pipefail

LOGFILE=".notes/monitor-regression-$(date +%Y%m%d-%H%M%S).log"
mkdir -p .notes
exec > >(tee -a "$LOGFILE") 2>&1

echo "START: monitor-and-prevent-regression"

BASELINE_MEM=$(ps aux | grep -E '/usr/share/code|/proc/self/ex' | grep -v grep | awk '{sum+=$6} END {print int(sum/1024)}')
echo "Baseline memory: ${BASELINE_MEM}MB"

while true; do
    echo ""
    echo "[$( date '+%Y-%m-%d %H:%M:%S')]"
    
    CURRENT_MEM=$(ps aux | grep -E '/usr/share/code|/proc/self/ex' | grep -v grep | awk '{sum+=$6} END {print int(sum/1024)}')
    CURRENT_PROCS=$(ps aux | grep -E '/usr/share/code|/proc/self/ex' | grep -v grep | wc -l)
    SWAP_MB=$(free -m | grep Swap | awk '{print $3}')
    
    DELTA=$((CURRENT_MEM - BASELINE_MEM))
    PERCENT=$(awk "BEGIN {printf \"%.1f\", ($DELTA/$BASELINE_MEM)*100}")
    
    echo "  Memory: ${CURRENT_MEM}MB (${DELTA:+$DELTA}MB ${PERCENT}% from baseline)"
    echo "  Processes: ${CURRENT_PROCS}"
    echo "  Swap: ${SWAP_MB}MB"
    
    # Check for regression
    if [ "$DELTA" -gt 500 ]; then
        echo "  🚨 REGRESSION DETECTED: +${DELTA}MB (+${PERCENT}%)"
        
        # Show what grew
        echo "  Top memory consumers:"
        ps aux | grep -E '/usr/share/code|/proc/self/ex' | grep -v grep | sort -k6 -rn | head -5 | awk '{printf "    PID %s: %dMB CPU:%s%%\n", $2, int($6/1024), $3}'
        
        # Check events
        journalctl --since "60 seconds ago" --no-pager 2>/dev/null | grep -i "error\|oom\|killed" | tail -3 || true
        
        # Auto-fix
        echo "  🔧 Preventing further regression..."
        ps aux | grep -E '/usr/share/code|/proc/self/ex' | grep -v grep | awk '$3 < 0.1 && $6 > 102400 {print $2}' | while read pid; do
            kill -9 "$pid" 2>/dev/null || true
        done
        
        # Update baseline
        BASELINE_MEM=$CURRENT_MEM
        echo "  Updated baseline: ${BASELINE_MEM}MB"
    fi
    
    sleep 30
done

