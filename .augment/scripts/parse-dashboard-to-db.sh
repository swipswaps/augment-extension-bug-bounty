#!/usr/bin/env bash
#
# Parse Error Dashboard HTML and Populate Database
#
# PURPOSE:
# - Extract 52 errors from dashboard-errors-embedded.html
# - Parse JSON data embedded in HTML
# - Populate error_tracking.db with all errors
# - Capture system metrics from htop snapshots
#
# BUG BOUNTY CONNECTION:
# - LLM overlooked these 52 errors
# - Database prevents future oversight
# - Forces LLM to query and acknowledge ALL errors

set -euo pipefail

DB_FILE=".augment/error_tracking.db"
HTML_FILE=".notes/visualizations/dashboard-errors-embedded.html"

# Initialize database if not exists
if [ ! -f "$DB_FILE" ]; then
    echo "📦 Database not found, initializing..."
    ./.augment/scripts/init-error-tracking-db.sh
fi

echo "🔍 Parsing error dashboard: $HTML_FILE"

# Extract JSON data from HTML (between const errorData = [ and ];)
JSON_DATA=$(sed -n '/const errorData = \[/,/\];/p' "$HTML_FILE" | sed '1d;$d')

# Parse JSON and insert into database
echo "$JSON_DATA" | jq -c '.[]' | while IFS= read -r error; do
    TIMESTAMP=$(echo "$error" | jq -r '.timestamp')
    SOURCE=$(echo "$error" | jq -r '.source')
    MESSAGE=$(echo "$error" | jq -r '.message' | sed "s/'/''/g")
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
    
    # Insert into database
    sqlite3 "$DB_FILE" <<SQL
INSERT INTO errors (timestamp, log_file, error_type, error_message, stack_trace, stack_lines, extension_name)
VALUES (
    '$TIMESTAMP',
    '$SOURCE',
    '$ERROR_TYPE',
    '$MESSAGE',
    '$STACK_TRACE',
    $STACK_LINES,
    'Augment'
);
SQL
done

echo "✅ Parsed errors from dashboard"
echo ""

# Capture system metrics from htop snapshots in user's message
echo "📊 Capturing system metrics from htop snapshots..."

# Snapshot 1: 08:52 (during errors)
sqlite3 "$DB_FILE" <<'SQL'
INSERT INTO system_metrics (timestamp, load_avg, memory_used_mb, swap_used_mb, vscode_cpu_pct, vscode_memory_mb, runaway_processes)
VALUES 
    ('2026-02-18T20:52:00', 1.10, 3400, 795, 35.3, 628, 1),
    ('2026-02-18T20:37:00', 5.83, 5200, 1400, 27.0, 1083, 1),
    ('2026-02-18T20:45:00', 3.54, 4200, 797, 20.0, 800, 1),
    ('2026-02-18T21:00:00', 1.59, 3470, 795, 42.2, 863, 1);
SQL

echo "✅ System metrics captured"
echo ""

# Correlate ALL errors with nearest metric sample
echo "🔗 Correlating errors with system metrics..."

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
FROM errors e
WHERE NOT EXISTS (SELECT 1 FROM error_correlation WHERE error_id = e.id);
SQL

echo "✅ Correlation complete"
echo ""

# Show summary
echo "📈 Database Summary:"
sqlite3 -header -column "$DB_FILE" "SELECT * FROM error_frequency;"
echo ""

echo "🎯 Query Examples:"
echo "  ./.augment/scripts/llm-query-errors.sh frequency"
echo "  ./.augment/scripts/llm-query-errors.sh contention"
echo "  ./.augment/scripts/llm-query-errors.sh timeline"

