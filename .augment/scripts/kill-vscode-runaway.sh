#!/usr/bin/env bash
#
# Kill VS Code Runaway Processes - Continuous Monitoring
#
# PURPOSE:
# - Monitor VS Code processes every 5 seconds
# - Kill any process with CPU > 5% OR memory > 400MB
# - Prevent runaway processes from accumulating
# - Run in background until stopped
#
# USAGE:
#   ./.augment/scripts/kill-vscode-runaway.sh &
#   # To stop: pkill -f kill-vscode-runaway.sh
#
# CRITICAL: Your system keeps spawning runaway processes
# - PID 836369: 41.7% CPU, 1044MB RAM (zygote CRITICAL)
# - PID 836263: 29.5% CPU,  598MB RAM (zygote HIGH)
# - PID 836282: 28.1% CPU,  429MB RAM (utility HIGH)
# - Load: 1.21 (improved but still spawning)
# - Swap: 794MB (memory pressure)

set -euo pipefail

LOGFILE=".notes/kill-vscode-runaway-$(date +%Y%m%d-%H%M%S).log"

# Log function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE"
}

log "=== VS Code Runaway Process Killer Started ==="
log "CPU threshold: 5%"
log "Memory threshold: 400MB"
log "Check interval: 5 seconds"
log "Log file: $LOGFILE"
log ""

# Counter for killed processes
TOTAL_KILLED=0

while true; do
    # Get current timestamp
    TIMESTAMP=$(date +'%H:%M:%S')
    
    # Find runaway processes (CPU > 5% OR memory > 400MB)
    # Exclude main VS Code process (PID with lowest number)
    RUNAWAY_PIDS=$(ps aux | grep -E "(code|/proc/self/exe)" | grep -v grep | \
                   awk '$3 > 5.0 || $6 > 400000 {print $2, $3, int($6/1024), $11}' | \
                   sort -n | tail -n +2)  # Skip first (main process)
    
    if [ -n "$RUNAWAY_PIDS" ]; then
        log "[$TIMESTAMP] Runaway processes detected:"
        
        echo "$RUNAWAY_PIDS" | while read pid cpu mem cmd; do
            log "  PID $pid: ${cpu}% CPU, ${mem}MB - $cmd"
            
            # Send SIGTERM first (graceful)
            if kill -15 "$pid" 2>/dev/null; then
                log "    ✓ SIGTERM sent to PID $pid"
                TOTAL_KILLED=$((TOTAL_KILLED + 1))
            else
                log "    ✗ Failed to send SIGTERM to PID $pid (already dead?)"
            fi
        done
        
        # Wait 2 seconds for graceful shutdown
        sleep 2
        
        # Force kill if still alive
        echo "$RUNAWAY_PIDS" | while read pid cpu mem cmd; do
            if ps -p "$pid" > /dev/null 2>&1; then
                log "  PID $pid still alive, sending SIGKILL..."
                if kill -9 "$pid" 2>/dev/null; then
                    log "    ✓ SIGKILL sent to PID $pid"
                else
                    log "    ✗ Failed to send SIGKILL to PID $pid"
                fi
            fi
        done
        
        log ""
    else
        # No runaway processes, just log heartbeat every 60 seconds
        SECONDS_SINCE_START=$(($(date +%s) - START_TIME))
        if [ $((SECONDS_SINCE_START % 60)) -eq 0 ]; then
            log "[$TIMESTAMP] Heartbeat: No runaway processes. Total killed: $TOTAL_KILLED"
        fi
    fi
    
    # Wait 5 seconds before next check
    sleep 5
done

