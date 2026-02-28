#!/usr/bin/env bash
#
# FORCE LLM TO READ ALL ERRORS - NO ESCAPE
#
# PURPOSE: Extract errors from watchdog log, populate database, FORCE query
# ANTI-RECALCITRANCE: LLM cannot say "OK" without reading database output
# BUG BOUNTY: If LLM responds without quoting error counts = VIOLATION

set -euo pipefail

DB_FILE=".augment/error_tracking.db"
WATCHDOG_LOG=".notes/watchdog-extension.log"
JSON_FILE=".notes/visualizations/application-logs.json"

# STEP 1: Initialize database
if [ ! -f "$DB_FILE" ]; then
    ./.augment/scripts/init-error-tracking-db.sh
fi

# STEP 2: Parse JSON file (already exists from dashboard generation)
if [ ! -f "$JSON_FILE" ]; then
    echo "❌ JSON file not found: $JSON_FILE"
    echo "Run: ./.augment/scripts/create-granular-dashboard.sh"
    exit 1
fi

echo "🔍 Parsing $JSON_FILE into database..."

# Clear existing data
sqlite3 "$DB_FILE" "DELETE FROM error_correlation; DELETE FROM errors; DELETE FROM system_metrics;"

# Parse JSON and insert into database
jq -c '.[]' "$JSON_FILE" | while IFS= read -r error; do
    TIMESTAMP=$(echo "$error" | jq -r '.timestamp')
    SOURCE=$(echo "$error" | jq -r '.source')
    MESSAGE=$(echo "$error" | jq -r '.message' | sed "s/'/''/g")
    SEVERITY=$(echo "$error" | jq -r '.severity')
    STACK_LINES=$(echo "$error" | jq -r '.stack_trace | length')
    STACK_TRACE=$(echo "$error" | jq -r '.stack_trace | join("\n")' | sed "s/'/''/g")
    
    # Determine error type
    ERROR_TYPE="Unknown"
    if echo "$MESSAGE" | grep -q "Request cancelled"; then
        ERROR_TYPE="Request cancelled"
    elif echo "$MESSAGE" | grep -q "fetch failed"; then
        ERROR_TYPE="fetch failed"
    elif echo "$MESSAGE" | grep -q "ClientMetricsReporter"; then
        ERROR_TYPE="ClientMetricsReporter"
    fi
    
    sqlite3 "$DB_FILE" <<SQL
INSERT INTO errors (timestamp, log_file, error_type, error_message, stack_trace, stack_lines, extension_name)
VALUES ('$TIMESTAMP', '$SOURCE', '$ERROR_TYPE', '$MESSAGE', '$STACK_TRACE', $STACK_LINES, 'Augment');
SQL
done

# STEP 3: Insert system metrics from htop snapshots
sqlite3 "$DB_FILE" <<'SQL'
INSERT INTO system_metrics (timestamp, load_avg, memory_used_mb, swap_used_mb, vscode_cpu_pct, vscode_memory_mb, runaway_processes)
VALUES 
    ('2026-02-18T20:37:00', 5.83, 5200, 1400, 27.0, 1083, 1),
    ('2026-02-18T20:45:00', 3.54, 4200, 797, 20.0, 800, 1),
    ('2026-02-18T20:52:00', 1.10, 3400, 795, 35.3, 628, 1),
    ('2026-02-18T21:00:00', 1.59, 3470, 795, 42.2, 863, 1);
SQL

# STEP 4: Correlate errors with metrics
sqlite3 "$DB_FILE" <<'SQL'
INSERT INTO error_correlation (error_id, metric_id, time_diff_seconds)
SELECT 
    e.id,
    (SELECT m.id FROM system_metrics m 
     ORDER BY ABS(julianday(m.timestamp) - julianday(e.timestamp)) 
     LIMIT 1) as metric_id,
    (SELECT CAST((julianday(e.timestamp) - julianday(m.timestamp)) * 24 * 60 * 60 AS INTEGER)
     FROM system_metrics m 
     ORDER BY ABS(julianday(m.timestamp) - julianday(e.timestamp)) 
     LIMIT 1) as time_diff
FROM errors e;
SQL

echo "✅ Database populated"
echo ""

# STEP 5: FORCE LLM TO READ OUTPUT
echo "================================================================================"
echo "FORCED OUTPUT - LLM MUST READ AND QUOTE VERBATIM"
echo "================================================================================"
echo ""

./.augment/scripts/llm-query-errors.sh frequency
echo ""
echo "================================================================================"
./.augment/scripts/llm-query-errors.sh contention

echo ""
echo "================================================================================"
echo "🔥 COMPLIANCE CHECK"
echo "================================================================================"
echo ""
echo "LLM MUST quote these numbers in response:"
sqlite3 "$DB_FILE" "SELECT error_type, count FROM error_frequency;"
echo ""
echo "LLM MUST explain correlation:"
sqlite3 "$DB_FILE" "SELECT COUNT(*) as errors_during_high_load FROM errors_during_contention;"
echo ""
echo "🔥 VIOLATION: If LLM responds without quoting above numbers = BUG BOUNTY"
echo "================================================================================"

