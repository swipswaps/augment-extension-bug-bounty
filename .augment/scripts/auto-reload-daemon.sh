#!/usr/bin/env bash
###############################################################################
# AUTO-RELOAD DAEMON
#
# PURPOSE:
#   Automatically reload VS Code when file descriptor leak exceeds threshold
#
# DESIGN:
#   - Monitors FD count every 60 seconds
#   - Triggers reload when FD > 55,000 for 2 consecutive checks
#   - Saves workspace state before reload
#   - Logs all interventions
#
# USAGE:
#   ./.augment/scripts/auto-reload-daemon.sh [OPTIONS]
#
# OPTIONS:
#   --test-detection    Test FD detection logic only
#   --dry-run           Simulate reload without actually restarting
#   --once              Run single check and exit
#   --threshold N       Set FD threshold (default: 55000)
#   --interval N        Set check interval in seconds (default: 60)
#
###############################################################################

set -euo pipefail

# Configuration
FD_THRESHOLD=${FD_THRESHOLD:-55000}
CHECK_INTERVAL=${CHECK_INTERVAL:-60}
LOGFILE=".notes/auto-reload-daemon.log"
DBFILE=".augment/error_tracking.db"
DISABLE_FLAG=".augment/.disable-auto-reload"

# Modes
TEST_DETECTION=false
DRY_RUN=false
RUN_ONCE=false

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --test-detection)
            TEST_DETECTION=true
            shift
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --once)
            RUN_ONCE=true
            shift
            ;;
        --threshold)
            FD_THRESHOLD="$2"
            shift 2
            ;;
        --interval)
            CHECK_INTERVAL="$2"
            shift 2
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Logging function
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE"
}

# Get current FD count for VS Code processes
get_fd_count() {
    lsof 2>/dev/null | grep -c "code" 2>/dev/null || echo "0"
}

# Check if daemon is disabled
is_disabled() {
    [[ -f "$DISABLE_FLAG" ]]
}

# Save intervention to database
log_intervention() {
    local fd_count=$1
    local action=$2
    
    if [[ -f "$DBFILE" ]]; then
        sqlite3 "$DBFILE" "INSERT INTO errors (timestamp, error_type, error_message, context) VALUES (datetime('now'), 'auto_reload_intervention', 'FD count: $fd_count', '$action');" 2>/dev/null || true
    fi
}

# Reload VS Code
reload_vscode() {
    local fd_count=$1
    
    log "🔄 TRIGGERING AUTO-RELOAD (FD count: $fd_count)"
    log_intervention "$fd_count" "reload_triggered"
    
    if $DRY_RUN; then
        log "🧪 DRY-RUN: Would reload VS Code now"
        return 0
    fi
    
    # Find VS Code process
    local vscode_pid=$(pgrep -f "code.*--type=renderer" | head -1)
    
    if [[ -z "$vscode_pid" ]]; then
        log "⚠️  No VS Code process found"
        return 1
    fi
    
    log "📝 Saving workspace state..."
    # Send SIGUSR1 to trigger workspace save (if supported)
    kill -USR1 "$vscode_pid" 2>/dev/null || true
    sleep 2
    
    log "🛑 Stopping VS Code (PID: $vscode_pid)..."
    # Graceful shutdown
    pkill -TERM -f "code.*--type" 2>/dev/null || true
    
    # Wait for clean shutdown (max 10 seconds)
    for i in {1..10}; do
        if ! pgrep -f "code.*--type" >/dev/null 2>&1; then
            log "✅ VS Code stopped cleanly"
            break
        fi
        sleep 1
    done
    
    # Force kill if still running
    if pgrep -f "code.*--type" >/dev/null 2>&1; then
        log "⚠️  Force killing VS Code..."
        pkill -KILL -f "code.*--type" 2>/dev/null || true
        sleep 2
    fi
    
    log "🚀 Restarting VS Code..."
    # Restart VS Code in background
    nohup code . >/dev/null 2>&1 &
    
    log "✅ Auto-reload complete"
    log_intervention "$fd_count" "reload_complete"
}

# Main monitoring loop
monitor_fd_count() {
    local consecutive_high=0
    
    log "🚀 Auto-reload daemon started"
    log "   Threshold: $FD_THRESHOLD FDs"
    log "   Interval: $CHECK_INTERVAL seconds"
    log "   Disable flag: $DISABLE_FLAG"
    
    while true; do
        # Check if disabled
        if is_disabled; then
            log "⏸️  Daemon disabled (remove $DISABLE_FLAG to re-enable)"
            sleep "$CHECK_INTERVAL"
            continue
        fi
        
        # Get current FD count
        local fd_count
        fd_count=$(get_fd_count)
        
        if [[ "$fd_count" -gt "$FD_THRESHOLD" ]]; then
            consecutive_high=$((consecutive_high + 1))
            log "⚠️  FD count: $fd_count (threshold: $FD_THRESHOLD, consecutive: $consecutive_high)"
            
            # Trigger reload after 2 consecutive high readings
            if [[ $consecutive_high -ge 2 ]]; then
                reload_vscode "$fd_count"
                consecutive_high=0
                
                # Wait longer after reload
                sleep $((CHECK_INTERVAL * 3))
            fi
        else
            if [[ $consecutive_high -gt 0 ]]; then
                log "✅ FD count normalized: $fd_count"
            fi
            consecutive_high=0
        fi
        
        if $RUN_ONCE; then
            log "🏁 Single check complete (FD count: $fd_count)"
            break
        fi
        
        sleep "$CHECK_INTERVAL"
    done
}

# Test detection mode
if $TEST_DETECTION; then
    log "🧪 TEST MODE: FD Detection"
    fd_count=$(get_fd_count)
    log "Current FD count: $fd_count"
    log "Threshold: $FD_THRESHOLD"
    
    if [[ "$fd_count" -gt "$FD_THRESHOLD" ]]; then
        log "✅ Would trigger reload (FD count exceeds threshold)"
    else
        log "✅ No action needed (FD count below threshold)"
    fi
    exit 0
fi

# Start monitoring
monitor_fd_count

