#!/usr/bin/env bash
###############################################################################
# EMERGENCY ZYGOTE KILLER
#
# PURPOSE:
#   Immediately kill runaway zygote processes to prevent system crash
#
# USAGE:
#   ./.augment/emergency-zygote-killer.sh
###############################################################################

set -euo pipefail

LOGFILE=".notes/zygote-killer-$(date +%Y%m%d-%H%M%S).log"

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE"
}

log "========================================================================"
log "EMERGENCY ZYGOTE KILLER STARTING"
log "========================================================================"

# Find all zygote processes
ZYGOTES=$(ps aux | grep "[c]ode --type=zygote" || true)

if [ -z "$ZYGOTES" ]; then
  log "No zygote processes found"
  exit 0
fi

log "Found zygote processes:"
echo "$ZYGOTES" | while read -r line; do
  log "  $line"
done

# Kill zygotes with CPU > 20% or MEM > 1000 MB
echo "$ZYGOTES" | while read -r user pid cpu mem vsz rss tty stat start time cmd; do
  # Extract numeric values
  cpu_val=$(echo "$cpu" | sed 's/%//')
  mem_mb=$(echo "$mem" | awk '{print int($1 * 7740 / 100)}')  # Assuming 7.74GB total RAM
  
  log ""
  log "Checking PID $pid: CPU=${cpu}% MEM=${mem_mb}MB"
  
  # Check if CPU > 20% OR MEM > 1000MB
  if (( $(echo "$cpu_val > 20" | bc -l) )) || (( mem_mb > 1000 )); then
    log "⚠ KILLING runaway zygote PID $pid (CPU=${cpu}% MEM=${mem_mb}MB)"
    
    # Try graceful kill first
    if kill -TERM "$pid" 2>/dev/null; then
      log "  Sent SIGTERM to PID $pid"
      sleep 2
      
      # Check if still alive
      if ps -p "$pid" > /dev/null 2>&1; then
        log "  PID $pid still alive, sending SIGKILL"
        kill -KILL "$pid" 2>/dev/null || true
      else
        log "  PID $pid terminated gracefully"
      fi
    else
      log "  Failed to kill PID $pid (may already be dead)"
    fi
  else
    log "✓ PID $pid is within normal limits"
  fi
done

log ""
log "========================================================================"
log "ZYGOTE KILLER COMPLETE"
log "========================================================================"
log ""
log "Remaining zygote processes:"
ps aux | grep "[c]ode --type=zygote" | while read -r line; do
  log "  $line"
done || log "  (none)"
log ""
log "NEXT STEPS:"
log "1. Reload VS Code window to activate lifecycle fixes"
log "2. Monitor zygote count: watch -n 10 'ps aux | grep \"[c]ode --type=zygote\" | wc -l'"
log "3. If zygotes respawn, the root cause is still active"
log ""

