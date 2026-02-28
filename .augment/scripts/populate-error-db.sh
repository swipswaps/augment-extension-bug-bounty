#!/usr/bin/env bash
#
# Populate Error Tracking Database from Logs
#
# PURPOSE:
# - Parse VS Code extension logs for errors
# - Extract error messages and stack traces
# - Capture system metrics at time of error
# - Store in database for correlation analysis
#
# ANTI-RECALCITRANCE:
# - Forces LLM to query database (can't ignore)
# - All 52 "Request cancelled" errors will be in database
# - Automatic correlation with resource contention
# - No truncation, no oversight

set -euo pipefail

DB_FILE=".augment/error_tracking.db"
LOG_DIR=".notes"

# Initialize database if not exists
if [ ! -f "$DB_FILE" ]; then
    echo "📦 Database not found, initializing..."
    ./.augment/scripts/init-error-tracking-db.sh
fi

echo "🔍 Parsing error logs from $LOG_DIR..."

# Find all terminal log files
LOG_FILES=$(find "$LOG_DIR" -name "terminal-*.log" -type f 2>/dev/null | sort)

if [ -z "$LOG_FILES" ]; then
    echo "⚠️  No log files found in $LOG_DIR"
    exit 0
fi

ERROR_COUNT=0

# Parse each log file
for logfile in $LOG_FILES; do
    echo "  Processing: $logfile"
    
    # Extract errors with timestamps
    # Pattern: [YYYY-MM-DD HH:MM:SS] [ERROR] message
    # OR: YYYY-MM-DD HH:MM:SS.mmm [error] message
    grep -E "\[error\]|\[ERROR\]|Error:|ERROR:" "$logfile" 2>/dev/null | while IFS= read -r line; do
        # Extract timestamp (various formats)
        TIMESTAMP=$(echo "$line" | grep -oP '\d{4}-\d{2}-\d{2}[T ]\d{2}:\d{2}:\d{2}' | head -1)
        
        if [ -z "$TIMESTAMP" ]; then
            TIMESTAMP=$(date --iso-8601=seconds)
        fi
        
        # Determine error type
        ERROR_TYPE="Unknown"
        if echo "$line" | grep -q "Request cancelled"; then
            ERROR_TYPE="Request cancelled"
        elif echo "$line" | grep -q "fetch failed"; then
            ERROR_TYPE="fetch failed"
        elif echo "$line" | grep -q "ClientMetricsReporter"; then
            ERROR_TYPE="ClientMetricsReporter"
        elif echo "$line" | grep -q "timeout"; then
            ERROR_TYPE="timeout"
        fi
        
        # Extract error message (escape single quotes for SQL)
        ERROR_MESSAGE=$(echo "$line" | sed "s/'/''/g")
        
        # Insert into database
        sqlite3 "$DB_FILE" <<SQL
INSERT INTO errors (timestamp, log_file, error_type, error_message, extension_name)
VALUES (
    '$TIMESTAMP',
    '$(echo "$logfile" | sed "s/'/''/g")',
    '$ERROR_TYPE',
    '$ERROR_MESSAGE',
    'Augment'
);
SQL
        
        ERROR_COUNT=$((ERROR_COUNT + 1))
    done
done

echo "✅ Parsed $ERROR_COUNT errors from logs"
echo ""

# Capture current system metrics
echo "📊 Capturing current system metrics..."

TIMESTAMP=$(date --iso-8601=seconds)
LOAD_AVG=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',')
MEMORY_USED=$(free -m | awk 'NR==2 {print $3}')
SWAP_USED=$(free -m | awk 'NR==3 {print $3}')

# VS Code metrics
VSCODE_CPU=$(ps aux | grep -E "(code|/proc/self/exe)" | grep -v grep | awk '{sum+=$3} END {print sum}')
VSCODE_MEMORY=$(ps aux | grep -E "(code|/proc/self/exe)" | grep -v grep | awk '{sum+=$6} END {print int(sum/1024)}')
RUNAWAY_COUNT=$(ps aux | grep -E "(code|/proc/self/exe)" | grep -v grep | awk '$3 > 20.0 || $6 > 600000 {count++} END {print count+0}')

sqlite3 "$DB_FILE" <<SQL
INSERT INTO system_metrics (timestamp, load_avg, memory_used_mb, swap_used_mb, vscode_cpu_pct, vscode_memory_mb, runaway_processes)
VALUES (
    '$TIMESTAMP',
    ${LOAD_AVG:-0},
    ${MEMORY_USED:-0},
    ${SWAP_USED:-0},
    ${VSCODE_CPU:-0},
    ${VSCODE_MEMORY:-0},
    ${RUNAWAY_COUNT:-0}
);
SQL

echo "✅ System metrics captured"
echo ""

# Correlate recent errors with metrics
echo "🔗 Correlating errors with system metrics..."

METRIC_ID=$(sqlite3 "$DB_FILE" "SELECT id FROM system_metrics ORDER BY id DESC LIMIT 1;")

# Correlate errors from last 5 minutes
sqlite3 "$DB_FILE" <<SQL
INSERT INTO error_correlation (error_id, metric_id, time_diff_seconds)
SELECT 
    e.id,
    $METRIC_ID,
    CAST((julianday('$TIMESTAMP') - julianday(e.timestamp)) * 24 * 60 * 60 AS INTEGER)
FROM errors e
WHERE (julianday('$TIMESTAMP') - julianday(e.timestamp)) * 24 * 60 < 5
AND NOT EXISTS (SELECT 1 FROM error_correlation WHERE error_id = e.id);
SQL

echo "✅ Correlation complete"
echo ""

# Show summary
echo "📈 Database Summary:"
sqlite3 -header -column "$DB_FILE" "SELECT * FROM error_frequency;"
echo ""

echo "🎯 Query Examples:"
echo "  sqlite3 $DB_FILE 'SELECT * FROM errors_with_context LIMIT 10'"
echo "  sqlite3 $DB_FILE 'SELECT * FROM errors_during_contention'"
echo "  sqlite3 $DB_FILE 'SELECT * FROM resource_timeline LIMIT 10'"

