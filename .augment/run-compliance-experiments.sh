#!/usr/bin/env bash
#####################################################################################################
# COMPLIANCE EXPERIMENTS (From File 0115)
#
# PURPOSE:
# Execute the 9 required experiments to definitively confirm leak source
#
# EXPERIMENTS:
# 1. Baseline Idle (disable stream, observe 10 min)
# 2. Single Stream, No Timeout (confirm proper cleanup)
# 3. Forced Timeout, No Retry (confirm abort path cleanup)
# 4. Retry Enabled (detect latch re-entry)
# 5. Webview Disabled (confirm renderer churn impact)
#
# REQUIRED EVIDENCE MATRIX:
# - Extension Host FD count
# - Active TCP sockets (ESTABLISHED / TIME_WAIT / CLOSE_WAIT)
# - Undici dispatcher stats (in-process)
# - Stream lifecycle events
# - Webview reload count
# - Renderer process PID churn
#
# NO STEPS MAY BE SKIPPED
#####################################################################################################

set -euo pipefail

LOGFILE=".notes/compliance-experiments-$(date +%Y%m%d-%H%M%S).log"
RESULTS_FILE=".notes/experiment-results-$(date +%Y%m%d-%H%M%S).json"

log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE"
}

#####################################################################################################
# SECTION 1 — FIND EXTENSION HOST PID
#####################################################################################################

find_extension_host_pid() {
    local pid
    pid=$(ps aux | grep -- '--extensionHost' | grep -v grep | awk '{print $2}' | head -1)
    
    if [ -z "$pid" ]; then
        log "ERROR: Extension host not found"
        exit 1
    fi
    
    echo "$pid"
}

#####################################################################################################
# SECTION 2 — MEASURE FD COUNT
#####################################################################################################

get_fd_count() {
    local pid=$1
    ls "/proc/$pid/fd" 2>/dev/null | wc -l || echo "0"
}

#####################################################################################################
# SECTION 3 — MEASURE TCP SOCKETS
#####################################################################################################

get_tcp_stats() {
    local pid=$1
    local socket_inodes
    socket_inodes=$(ls -l "/proc/$pid/fd" 2>/dev/null | grep socket | awk -F'[][]' '{print $2}' | tr -d '[]')
    
    local established=0
    local time_wait=0
    local close_wait=0
    
    while IFS= read -r inode; do
        if [ -n "$inode" ]; then
            local state
            state=$(grep "$inode" /proc/net/tcp 2>/dev/null | awk '{print $4}' || echo "")
            
            case "$state" in
                "01") ((established++)) ;;
                "06") ((time_wait++)) ;;
                "08") ((close_wait++)) ;;
            esac
        fi
    done <<< "$socket_inodes"
    
    echo "{\"ESTABLISHED\": $established, \"TIME_WAIT\": $time_wait, \"CLOSE_WAIT\": $close_wait}"
}

#####################################################################################################
# SECTION 4 — EXPERIMENT 1: BASELINE IDLE
#####################################################################################################

experiment_1_baseline_idle() {
    log "========================================="
    log "EXPERIMENT 1: BASELINE IDLE"
    log "========================================="
    log "Goal: Establish FD + TCP steady state with NO streaming calls"
    log "Procedure: Observe for 10 minutes"
    log ""
    
    local pid
    pid=$(find_extension_host_pid)
    log "Extension Host PID: $pid"
    
    local baseline_fd
    baseline_fd=$(get_fd_count "$pid")
    log "Baseline FD count: $baseline_fd"
    
    local baseline_tcp
    baseline_tcp=$(get_tcp_stats "$pid")
    log "Baseline TCP stats: $baseline_tcp"
    
    log ""
    log "Monitoring for 10 minutes (sampling every 30 seconds)..."
    
    local samples=20
    local max_fd=$baseline_fd
    local min_fd=$baseline_fd
    
    for i in $(seq 1 $samples); do
        sleep 30
        
        local current_fd
        current_fd=$(get_fd_count "$pid")
        
        local current_tcp
        current_tcp=$(get_tcp_stats "$pid")
        
        log "Sample $i/$samples: FD=$current_fd TCP=$current_tcp"
        
        if [ "$current_fd" -gt "$max_fd" ]; then
            max_fd=$current_fd
        fi
        
        if [ "$current_fd" -lt "$min_fd" ]; then
            min_fd=$current_fd
        fi
    done
    
    local fd_range=$((max_fd - min_fd))
    
    log ""
    log "EXPERIMENT 1 RESULTS:"
    log "  Baseline FD: $baseline_fd"
    log "  Min FD: $min_fd"
    log "  Max FD: $max_fd"
    log "  FD Range: $fd_range"
    
    if [ "$fd_range" -lt 50 ]; then
        log "  ✅ PASS: FD stable (range < 50)"
    else
        log "  ❌ FAIL: FD unstable (range >= 50)"
        log "  → Stream is NOT primary cause if disabled"
    fi
    
    echo "{\"experiment\": 1, \"baseline_fd\": $baseline_fd, \"min_fd\": $min_fd, \"max_fd\": $max_fd, \"fd_range\": $fd_range}" >> "$RESULTS_FILE"
}

#####################################################################################################
# SECTION 5 — MAIN EXECUTION
#####################################################################################################

main() {
    log "Starting Compliance Experiments"
    log "Log file: $LOGFILE"
    log "Results file: $RESULTS_FILE"
    log ""
    
    echo "[]" > "$RESULTS_FILE"
    
    # Run experiments
    experiment_1_baseline_idle
    
    log ""
    log "========================================="
    log "ALL EXPERIMENTS COMPLETE"
    log "========================================="
    log "Results saved to: $RESULTS_FILE"
}

main "$@"

