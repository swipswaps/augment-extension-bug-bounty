#!/usr/bin/env bash
# Resource Watchdog - Production code for hidden-terminal-watchdog extension
# Monitors VS Code memory and auto-cleans when thresholds exceeded
# Integrates with existing watchdog infrastructure

set -euo pipefail

# Configuration
MEMORY_THRESHOLD_MB=4000
LOG_FILE_THRESHOLD=25
PROCESS_THRESHOLD=20
CHECK_INTERVAL=60  # seconds
LOGDIR=".notes"
DBFILE=".augment/resource_watchdog.db"

# Initialize database
init_db() {
    sqlite3 "$DBFILE" <<EOF
CREATE TABLE IF NOT EXISTS resource_checks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT NOT NULL,
    vscode_memory_mb INTEGER NOT NULL,
    total_memory_mb INTEGER NOT NULL,
    swap_mb INTEGER NOT NULL,
    load_avg REAL NOT NULL,
    process_count INTEGER NOT NULL,
    log_file_count INTEGER NOT NULL,
    action_taken TEXT,
    threshold_exceeded INTEGER DEFAULT 0
);

CREATE TABLE IF NOT EXISTS cleanup_actions (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT NOT NULL,
    action_type TEXT NOT NULL,
    files_deleted INTEGER DEFAULT 0,
    memory_freed_mb INTEGER DEFAULT 0,
    success INTEGER DEFAULT 1,
    error_message TEXT
);
EOF
}

# Get VS Code memory
get_vscode_memory() {
    ps aux | grep -E '/usr/share/code|/proc/self/ex' | grep -v grep | awk '{sum+=$6} END {print int(sum/1024)}' || echo "0"
}

# Get total memory
get_total_memory() {
    free -m | grep Mem | awk '{print $3}'
}

# Get swap
get_swap() {
    free -m | grep Swap | awk '{print $3}'
}

# Get load average (5-minute)
get_load() {
    uptime | awk -F'load average:' '{print $2}' | awk -F',' '{print $2}' | tr -d ' '
}

# Get process count
get_process_count() {
    ps aux | grep -E '/usr/share/code|/proc/self/ex' | grep -v grep | wc -l
}

# Get log file count
get_log_count() {
    ls -1 "$LOGDIR"/terminal-*.log 2>/dev/null | wc -l || echo "0"
}

# Cleanup old logs
cleanup_logs() {
    local before_count=$(get_log_count)
    local before_size=$(du -sm "$LOGDIR"/terminal-*.log 2>/dev/null | awk '{sum+=$1} END {print sum}' || echo "0")
    
    # Keep only 20 most recent
    ls -t "$LOGDIR"/terminal-*.log 2>/dev/null | tail -n +21 | xargs -r rm -f
    
    local after_count=$(get_log_count)
    local after_size=$(du -sm "$LOGDIR"/terminal-*.log 2>/dev/null | awk '{sum+=$1} END {print sum}' || echo "0")
    local freed=$((before_size - after_size))
    local deleted=$((before_count - after_count))
    
    sqlite3 "$DBFILE" <<EOF
INSERT INTO cleanup_actions (timestamp, action_type, files_deleted, memory_freed_mb, success)
VALUES (datetime('now'), 'log_cleanup', $deleted, $freed, 1);
EOF
    
    echo "$deleted:$freed"
}

# Kill idle extension processes
kill_idle_processes() {
    local killed=0
    
    # Find processes with 0% CPU for > 30 minutes
    while read -r pid cpu time; do
        if [[ "$cpu" == "0.0" ]] && [[ "$time" =~ ^[0-9]+:[3-9][0-9]|^[1-9][0-9]+: ]]; then
            kill -15 "$pid" 2>/dev/null && ((killed++)) || true
        fi
    done < <(ps aux | grep -E '/usr/share/code|/proc/self/ex' | grep -v grep | awk '{print $2, $3, $10}')
    
    sqlite3 "$DBFILE" <<EOF
INSERT INTO cleanup_actions (timestamp, action_type, files_deleted, success)
VALUES (datetime('now'), 'kill_idle_processes', $killed, 1);
EOF
    
    echo "$killed"
}

# Check and act
check_resources() {
    local vscode_mem=$(get_vscode_memory)
    local total_mem=$(get_total_memory)
    local swap=$(get_swap)
    local load=$(get_load)
    local proc_count=$(get_process_count)
    local log_count=$(get_log_count)
    local action=""
    local threshold_exceeded=0
    
    # Check thresholds
    if [ "$vscode_mem" -gt "$MEMORY_THRESHOLD_MB" ]; then
        threshold_exceeded=1
        action="memory_exceeded"
        
        # Cleanup logs first
        local cleanup_result=$(cleanup_logs)
        local deleted=$(echo "$cleanup_result" | cut -d: -f1)
        local freed=$(echo "$cleanup_result" | cut -d: -f2)
        
        # Kill idle processes
        local killed=$(kill_idle_processes)
        
        action="cleaned_${deleted}_logs_freed_${freed}MB_killed_${killed}_processes"
        
        # If still over threshold, recommend reload
        local new_mem=$(get_vscode_memory)
        if [ "$new_mem" -gt "$MEMORY_THRESHOLD_MB" ]; then
            action="${action}_RELOAD_RECOMMENDED"
            echo "⚠️  RELOAD RECOMMENDED: Memory still at ${new_mem}MB after cleanup" >&2
        fi
    elif [ "$log_count" -gt "$LOG_FILE_THRESHOLD" ]; then
        threshold_exceeded=1
        action="log_threshold_exceeded"
        cleanup_logs >/dev/null
        action="cleaned_logs"
    elif [ "$proc_count" -gt "$PROCESS_THRESHOLD" ]; then
        threshold_exceeded=1
        action="process_threshold_exceeded"
        kill_idle_processes >/dev/null
        action="killed_idle_processes"
    fi
    
    # Log to database
    sqlite3 "$DBFILE" <<EOF
INSERT INTO resource_checks (timestamp, vscode_memory_mb, total_memory_mb, swap_mb, load_avg, process_count, log_file_count, action_taken, threshold_exceeded)
VALUES (datetime('now'), $vscode_mem, $total_mem, $swap, $load, $proc_count, $log_count, '$action', $threshold_exceeded);
EOF
    
    # Output for monitoring
    echo "$(date +%Y%m%d-%H%M%S)|MEM:${vscode_mem}MB|PROC:${proc_count}|LOGS:${log_count}|ACTION:${action}"
}

# Main loop
main() {
    init_db
    
    if [ "${1:-}" = "--once" ]; then
        check_resources
        exit 0
    fi
    
    echo "Resource Watchdog started (PID: $$)"
    echo "Checking every ${CHECK_INTERVAL}s"
    echo "Thresholds: Memory=${MEMORY_THRESHOLD_MB}MB, Logs=${LOG_FILE_THRESHOLD}, Processes=${PROCESS_THRESHOLD}"
    
    while true; do
        check_resources
        sleep "$CHECK_INTERVAL"
    done
}

main "$@"

