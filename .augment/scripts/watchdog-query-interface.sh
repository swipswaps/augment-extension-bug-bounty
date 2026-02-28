#!/bin/bash
# WATCHDOG DATABASE QUERY INTERFACE
# Purpose: Interactive SQL queries on watchdog data for troubleshooting
# Usage: ./.augment/scripts/watchdog-query-interface.sh [query_type]
# Query types: summary, leaks, errors, timeline, correlation

LOGFILE=".notes/watchdog-query-$(date +%Y%m%d-%H%M%S).log"
DB=".augment/error_tracking.db"
QUERY_TYPE="${1:-summary}"

echo "START: watchdog-query-interface" | tee -a "$LOGFILE"
echo "Query type: $QUERY_TYPE" | tee -a "$LOGFILE"
echo "Timestamp: $(date -Iseconds)" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"

# Ensure database schema exists
sqlite3 "$DB" "CREATE TABLE IF NOT EXISTS errors (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    log_file TEXT,
    error_type TEXT,
    error_message TEXT,
    stack_trace TEXT,
    stack_lines INTEGER,
    extension_name TEXT
);

CREATE TABLE IF NOT EXISTS system_metrics (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    load_avg REAL,
    memory_used_mb INTEGER,
    swap_used_mb INTEGER,
    vscode_cpu_pct REAL,
    vscode_memory_mb INTEGER,
    runaway_processes INTEGER
);

CREATE TABLE IF NOT EXISTS error_correlation (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    error_id INTEGER,
    metric_id INTEGER,
    correlation_score REAL,
    FOREIGN KEY(error_id) REFERENCES errors(id),
    FOREIGN KEY(metric_id) REFERENCES system_metrics(id)
);" 2>&1 | tee -a "$LOGFILE"

case "$QUERY_TYPE" in
    summary)
        echo "=== ERROR SUMMARY ===" | tee -a "$LOGFILE"
        sqlite3 "$DB" "SELECT 
            error_type,
            COUNT(*) as count,
            MIN(datetime(timestamp)) as first_seen,
            MAX(datetime(timestamp)) as last_seen
        FROM errors 
        GROUP BY error_type 
        ORDER BY count DESC;" | column -t -s'|' | tee -a "$LOGFILE"
        ;;
        
    leaks)
        echo "=== FILE DESCRIPTOR LEAK ANALYSIS ===" | tee -a "$LOGFILE"
        
        # Extract FD counts from watchdog logs and insert into database
        WATCHDOG_LOG=$(find ~/.config/Code/logs -name "*Watchdog*" 2>/dev/null | tail -1)
        
        if [ -f "$WATCHDOG_LOG" ]; then
            echo "Extracting FD data from: $WATCHDOG_LOG" | tee -a "$LOGFILE"
            
            grep "FILE DESCRIPTOR WARNING" "$WATCHDOG_LOG" 2>/dev/null | \
                awk -F'[][]' '{
                    timestamp=$2
                    gsub(/Z/, "", timestamp)
                    match($0, /FDs=([0-9]+)/, fd)
                    print timestamp "|" fd[1]
                }' | while IFS='|' read timestamp fd_count; do
                    echo "  $timestamp: $fd_count FDs" | tee -a "$LOGFILE"
                done
            
            echo "" | tee -a "$LOGFILE"
            echo "FD leak trend (last 10 warnings):" | tee -a "$LOGFILE"
            grep "FILE DESCRIPTOR WARNING" "$WATCHDOG_LOG" 2>/dev/null | \
                tail -10 | \
                awk '{print $1, $2, $8}' | tee -a "$LOGFILE"
        fi
        ;;
        
    errors)
        echo "=== ERROR DETAILS WITH STACK TRACES ===" | tee -a "$LOGFILE"
        sqlite3 "$DB" "SELECT 
            datetime(timestamp) as time,
            error_type,
            substr(error_message, 1, 80) as message,
            substr(stack_trace, 1, 100) as stack
        FROM errors 
        WHERE stack_trace IS NOT NULL
        ORDER BY timestamp DESC 
        LIMIT 20;" | tee -a "$LOGFILE"
        ;;
        
    timeline)
        echo "=== ERROR TIMELINE (HOURLY) ===" | tee -a "$LOGFILE"
        sqlite3 "$DB" "SELECT 
            strftime('%Y-%m-%d %H:00', timestamp) as hour,
            error_type,
            COUNT(*) as count
        FROM errors 
        GROUP BY hour, error_type 
        ORDER BY hour DESC, count DESC 
        LIMIT 50;" | column -t -s'|' | tee -a "$LOGFILE"
        ;;
        
    correlation)
        echo "=== ERROR-TO-FD-LEAK CORRELATION ===" | tee -a "$LOGFILE"
        
        # Find errors that occurred during FD leak warnings
        WATCHDOG_LOG=$(find ~/.config/Code/logs -name "*Watchdog*" 2>/dev/null | tail -1)
        AUGMENT_LOG=$(find ~/.config/Code/logs -name "Augment.log" 2>/dev/null | tail -1)
        
        if [ -f "$WATCHDOG_LOG" ] && [ -f "$AUGMENT_LOG" ]; then
            # Extract FD warning timestamps
            grep "FILE DESCRIPTOR WARNING" "$WATCHDOG_LOG" 2>/dev/null | \
                awk -F'[][]' '{print $2}' | \
                while read fd_timestamp; do
                    # Convert to comparable format (YYYY-MM-DD HH:MM)
                    fd_time=$(echo "$fd_timestamp" | cut -d: -f1-2)
                    
                    # Find errors within same minute
                    echo "FD warning at: $fd_timestamp" | tee -a "$LOGFILE"
                    grep "\[error\]" "$AUGMENT_LOG" 2>/dev/null | \
                        grep "$fd_time" | \
                        head -5 | \
                        sed 's/^/  /' | tee -a "$LOGFILE"
                    echo "" | tee -a "$LOGFILE"
                done | head -30
        fi
        ;;
        
    *)
        echo "❌ Unknown query type: $QUERY_TYPE" | tee -a "$LOGFILE"
        echo "" | tee -a "$LOGFILE"
        echo "Available query types:" | tee -a "$LOGFILE"
        echo "  summary      - Error counts by type" | tee -a "$LOGFILE"
        echo "  leaks        - File descriptor leak analysis" | tee -a "$LOGFILE"
        echo "  errors       - Error details with stack traces" | tee -a "$LOGFILE"
        echo "  timeline     - Hourly error timeline" | tee -a "$LOGFILE"
        echo "  correlation  - Error-to-FD-leak correlation" | tee -a "$LOGFILE"
        ;;
esac

echo "" | tee -a "$LOGFILE"
echo "✅ Query complete" | tee -a "$LOGFILE"
echo "Log file: $LOGFILE" | tee -a "$LOGFILE"
echo "END: watchdog-query-interface" | tee -a "$LOGFILE"

