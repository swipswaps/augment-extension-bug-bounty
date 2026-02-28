#!/usr/bin/env bash
set -euo pipefail

LOGFILE=".notes/resolve-contention-$(date +%Y%m%d-%H%M%S).log"
mkdir -p .notes
exec > >(tee -a "$LOGFILE") 2>&1

echo "START: resolve-contention-with-events"

while true; do
    echo ""
    echo "[$( date '+%Y-%m-%d %H:%M:%S')] EVENT CORRELATION CHECK"
    
    # Get current state
    VSCODE_MEM=$(ps aux | grep -E '/usr/share/code|/proc/self/ex' | grep -v grep | awk '{sum+=$6} END {print int(sum/1024)}')
    VSCODE_PROCS=$(ps aux | grep -E '/usr/share/code|/proc/self/ex' | grep -v grep | wc -l)
    FD_COUNT=$(lsof 2>/dev/null | grep -c code || echo "0")
    SWAP_MB=$(free -m | grep Swap | awk '{print $3}')
    LOAD=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',')
    
    echo "  State: ${VSCODE_MEM}MB, ${VSCODE_PROCS} procs, ${FD_COUNT} FDs, ${SWAP_MB}MB swap, load ${LOAD}"
    
    # Check OOM events
    OOM_EVENTS=$(journalctl --since "60 seconds ago" --no-pager 2>/dev/null | grep -ic "oom\|killed" || echo "0")
    if [ "$OOM_EVENTS" -gt 0 ]; then
        echo "  🚨 OOM EVENTS DETECTED: $OOM_EVENTS"
        journalctl --since "60 seconds ago" --no-pager 2>/dev/null | grep -i "oom\|killed" | tail -5
    fi
    
    # Check VS Code crashes
    CRASH_EVENTS=$(journalctl --since "60 seconds ago" --no-pager 2>/dev/null | grep -ic "code.*segfault\|code.*crash" || echo "0")
    if [ "$CRASH_EVENTS" -gt 0 ]; then
        echo "  💥 CRASH EVENTS DETECTED: $CRASH_EVENTS"
        journalctl --since "60 seconds ago" --no-pager 2>/dev/null | grep -i "code.*segfault\|code.*crash" | tail -5
    fi
    
    # Check kernel errors
    KERNEL_ERRORS=$(dmesg -T 2>/dev/null | tail -50 | grep -ic "error\|fail\|oom" || echo "0")
    if [ "$KERNEL_ERRORS" -gt 0 ]; then
        echo "  ⚠️  KERNEL ERRORS: $KERNEL_ERRORS"
        dmesg -T 2>/dev/null | tail -50 | grep -iE "error|fail|oom" | tail -3
    fi
    
    # Check swap thrashing
    SWAP_IN=$(vmstat 1 2 | tail -1 | awk '{print $7}')
    SWAP_OUT=$(vmstat 1 2 | tail -1 | awk '{print $8}')
    if [ "$SWAP_IN" -gt 100 ] || [ "$SWAP_OUT" -gt 100 ]; then
        echo "  💿 SWAP THRASHING: in=${SWAP_IN}KB/s out=${SWAP_OUT}KB/s"
    fi
    
    # Check extension errors
    EXT_ERRORS=$(find ~/.config/Code/logs -name "*.log" -mmin -1 -exec grep -ic "error\|exception" {} \; 2>/dev/null | awk '{sum+=$1} END {print sum}' || echo "0")
    if [ "$EXT_ERRORS" -gt 5 ]; then
        echo "  🔌 EXTENSION ERRORS: $EXT_ERRORS in last minute"
        find ~/.config/Code/logs -name "*.log" -mmin -1 -exec grep -i "error\|exception" {} \; 2>/dev/null | tail -3
    fi
    
    # Auto-resolve based on events + thresholds
    SHOULD_RESOLVE=0
    
    if [ "$VSCODE_MEM" -gt 4500 ]; then
        echo "  ⚠️  Memory threshold exceeded: ${VSCODE_MEM}MB > 4500MB"
        SHOULD_RESOLVE=1
    fi
    
    if [ "$OOM_EVENTS" -gt 0 ]; then
        echo "  ⚠️  OOM events detected"
        SHOULD_RESOLVE=1
    fi
    
    if [ "$CRASH_EVENTS" -gt 0 ]; then
        echo "  ⚠️  Crash events detected"
        SHOULD_RESOLVE=1
    fi
    
    if [ "$FD_COUNT" -gt 60000 ]; then
        echo "  ⚠️  File descriptor threshold exceeded: ${FD_COUNT} > 60000"
        SHOULD_RESOLVE=1
    fi
    
    if [ "$SHOULD_RESOLVE" -eq 1 ]; then
        echo ""
        echo "  🔧 AUTO-RESOLVING RESOURCE CONTENTION"
        
        # Kill idle processes
        ps aux | grep -E '/usr/share/code|/proc/self/ex' | grep -v grep | awk '$3 < 0.1 && $6 > 102400 {print $2}' | while read pid; do
            echo "    Killing idle PID $pid"
            kill -9 "$pid" 2>/dev/null || true
        done
        
        # Clean caches
        find ~/.config/Code/Cache -type f -mtime +1 -delete 2>/dev/null || true
        find ~/.config/Code/CachedData -type f -mtime +1 -delete 2>/dev/null || true
        echo "    Cleaned caches"
        
        # Clean logs
        ls -t .notes/terminal-*.log 2>/dev/null | tail -n +11 | xargs -r rm -f
        echo "    Cleaned old logs"
        
        sleep 2
        
        # Check if still over threshold
        VSCODE_MEM_AFTER=$(ps aux | grep -E '/usr/share/code|/proc/self/ex' | grep -v grep | awk '{sum+=$6} END {print int(sum/1024)}')
        if [ "$VSCODE_MEM_AFTER" -gt 4000 ]; then
            echo "    Memory still high: ${VSCODE_MEM_AFTER}MB"
            echo "    Reloading VS Code window..."
            code --command workbench.action.reloadWindow 2>/dev/null || true
            sleep 10
        fi
        
        echo "  ✅ Resolution complete"
    fi
    
    sleep 30
done

