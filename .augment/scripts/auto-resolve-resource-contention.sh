#!/usr/bin/env bash
# Auto-resolve resource contention with logging
set -euo pipefail

LOGFILE=".notes/auto-resolve-$(date +%Y%m%d-%H%M%S).log"
mkdir -p .notes
exec > >(tee -a "$LOGFILE") 2>&1

echo "START: auto-resolve-resource-contention"

while true; do
    echo ""
    echo "[$( date '+%Y-%m-%d %H:%M:%S')] Checking resource contention..."
    
    # Get current state
    VSCODE_MEM=$(ps aux | grep -E '/usr/share/code|/proc/self/ex' | grep -v grep | awk '{sum+=$6} END {print int(sum/1024)}')
    VSCODE_PROCS=$(ps aux | grep -E '/usr/share/code|/proc/self/ex' | grep -v grep | wc -l)
    FD_COUNT=$(lsof 2>/dev/null | grep -c code || echo "0")
    SWAP_MB=$(free -m | grep Swap | awk '{print $3}')
    
    echo "  VS Code: ${VSCODE_MEM}MB, ${VSCODE_PROCS} procs, ${FD_COUNT} FDs, Swap: ${SWAP_MB}MB"
    
    # Check for errors
    AUGMENT_ERRORS=$(grep -c "error\|Error\|ERROR" ~/.config/Code/logs/*/exthost/Augment.log 2>/dev/null | awk -F: '{sum+=$2} END {print sum}' || echo "0")
    if [ "$AUGMENT_ERRORS" -gt 0 ]; then
        echo "  ⚠️  Augment errors: ${AUGMENT_ERRORS}"
        tail -5 ~/.config/Code/logs/*/exthost/Augment.log 2>/dev/null | grep -i error | sed 's/^/    /'
    fi
    
    # Auto-resolve if threshold exceeded
    if [ "$VSCODE_MEM" -gt 4500 ] || [ "$FD_COUNT" -gt 60000 ] || [ "$SWAP_MB" -gt 1000 ]; then
        echo ""
        echo "  🔧 THRESHOLD EXCEEDED - AUTO-RESOLVING"
        echo "  Memory: ${VSCODE_MEM}MB (threshold: 4500MB)"
        echo "  FDs: ${FD_COUNT} (threshold: 60000)"
        echo "  Swap: ${SWAP_MB}MB (threshold: 1000MB)"
        echo ""
        
        # Kill idle processes
        echo "  Killing idle VS Code processes..."
        ps aux | grep -E '/usr/share/code|/proc/self/ex' | grep -v grep | awk '$3 < 0.1 && $6 > 102400 {print $2}' | while read pid; do
            echo "    Killing PID $pid"
            kill -9 "$pid" 2>/dev/null || true
        done
        
        # Clean caches
        echo "  Cleaning VS Code caches..."
        find ~/.config/Code/Cache -type f -mtime +1 -delete 2>/dev/null || true
        find ~/.config/Code/CachedData -type f -mtime +1 -delete 2>/dev/null || true
        
        # Clean old logs
        echo "  Cleaning old logs..."
        ls -t .notes/terminal-*.log 2>/dev/null | tail -n +11 | xargs -r rm -f
        ls -t .notes/auto-resolve-*.log 2>/dev/null | tail -n +6 | xargs -r rm -f
        
        # Reload VS Code window if still over threshold
        sleep 2
        VSCODE_MEM_AFTER=$(ps aux | grep -E '/usr/share/code|/proc/self/ex' | grep -v grep | awk '{sum+=$6} END {print int(sum/1024)}')
        if [ "$VSCODE_MEM_AFTER" -gt 4000 ]; then
            echo ""
            echo "  🔄 Memory still high (${VSCODE_MEM_AFTER}MB) - Reloading VS Code window..."
            # Send reload command to VS Code
            code --command workbench.action.reloadWindow 2>/dev/null || true
            sleep 5
        fi
        
        echo "  ✅ Auto-resolve complete"
    fi
    
    sleep 60
done

