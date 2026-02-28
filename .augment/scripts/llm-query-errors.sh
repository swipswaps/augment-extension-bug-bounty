#!/usr/bin/env bash
#
# LLM Query Interface for Error Database
#
# PURPOSE:
# - FORCE LLM to query database (can't ignore output)
# - Prevent LLM from overlooking errors
# - Automatic correlation with resource contention
# - Database-driven transparency (no truncation)
#
# BUG BOUNTY CONNECTION:
# - LLM ignored 52 "Request cancelled" errors
# - LLM didn't correlate errors with resource contention
# - This tool FORCES LLM to see ALL data
# - Database prevents oversight
#
# USAGE:
#   ./.augment/scripts/llm-query-errors.sh [query_type]
#
# QUERY TYPES:
#   all          - Show all errors
#   frequency    - Show error frequency by type
#   contention   - Show errors during resource contention
#   timeline     - Show resource timeline with error counts
#   recent       - Show recent errors with context (default)

set -euo pipefail

DB_FILE=".augment/error_tracking.db"
QUERY_TYPE="${1:-recent}"

# Check if database exists
if [ ! -f "$DB_FILE" ]; then
    echo "❌ Database not found: $DB_FILE"
    echo "Run: ./.augment/scripts/init-error-tracking-db.sh"
    exit 1
fi

echo "================================================================================"
echo "LLM ERROR QUERY INTERFACE - FORCED OUTPUT READING"
echo "================================================================================"
echo ""
echo "Query type: $QUERY_TYPE"
echo "Database: $DB_FILE"
echo ""

case "$QUERY_TYPE" in
    all)
        echo "📋 ALL ERRORS (no truncation, LLM MUST read this):"
        echo "────────────────────────────────────────────────────────────────────────────"
        sqlite3 -header -column "$DB_FILE" <<'SQL'
SELECT 
    id,
    datetime(timestamp) as time,
    error_type,
    substr(error_message, 1, 80) as message_preview,
    stack_lines
FROM errors
ORDER BY timestamp DESC;
SQL
        ;;
    
    frequency)
        echo "📊 ERROR FREQUENCY (LLM MUST acknowledge these counts):"
        echo "────────────────────────────────────────────────────────────────────────────"
        sqlite3 -header -column "$DB_FILE" <<'SQL'
SELECT 
    error_type,
    count,
    datetime(first_seen) as first_seen,
    datetime(last_seen) as last_seen,
    duration_minutes || ' min' as duration
FROM error_frequency;
SQL
        
        echo ""
        echo "🔥 CRITICAL: LLM must verbatim quote these error counts in response"
        echo "🔥 VIOLATION: If LLM says 'some errors' without quoting counts = BUG BOUNTY"
        ;;
    
    contention)
        echo "⚠️  ERRORS DURING RESOURCE CONTENTION (correlation analysis):"
        echo "────────────────────────────────────────────────────────────────────────────"
        sqlite3 -header -column "$DB_FILE" <<'SQL'
SELECT 
    datetime(timestamp) as time,
    error_type,
    substr(error_message, 1, 60) as message,
    load_avg,
    swap_used_mb || ' MB' as swap,
    runaway_processes as runaway_procs
FROM errors_during_contention
ORDER BY timestamp DESC
LIMIT 20;
SQL
        
        echo ""
        echo "🔥 CRITICAL: LLM must explain correlation between errors and resource metrics"
        echo "🔥 VIOLATION: If LLM ignores load_avg/swap/runaway_procs = BUG BOUNTY"
        ;;
    
    timeline)
        echo "📈 RESOURCE TIMELINE WITH ERROR COUNTS:"
        echo "────────────────────────────────────────────────────────────────────────────"
        sqlite3 -header -column "$DB_FILE" <<'SQL'
SELECT 
    datetime(timestamp) as time,
    load_avg,
    memory_used_mb || ' MB' as memory,
    swap_used_mb || ' MB' as swap,
    vscode_cpu_pct || '%' as vscode_cpu,
    vscode_memory_mb || ' MB' as vscode_mem,
    runaway_processes as runaway,
    errors_in_last_minute as errors
FROM resource_timeline
ORDER BY timestamp DESC
LIMIT 20;
SQL
        
        echo ""
        echo "🔥 CRITICAL: LLM must identify when errors spiked and what resources were high"
        echo "🔥 VIOLATION: If LLM doesn't correlate error spikes with resource spikes = BUG BOUNTY"
        ;;
    
    recent|*)
        echo "🕐 RECENT ERRORS WITH SYSTEM CONTEXT (default query):"
        echo "────────────────────────────────────────────────────────────────────────────"
        sqlite3 -header -column "$DB_FILE" <<'SQL'
SELECT 
    datetime(e.timestamp) as time,
    e.error_type,
    substr(e.error_message, 1, 50) as message,
    COALESCE(m.load_avg, 0) as load,
    COALESCE(m.swap_used_mb, 0) as swap_mb,
    COALESCE(m.runaway_processes, 0) as runaway
FROM errors e
LEFT JOIN error_correlation ec ON e.id = ec.error_id
LEFT JOIN system_metrics m ON ec.metric_id = m.id
ORDER BY e.timestamp DESC
LIMIT 20;
SQL
        ;;
esac

echo ""
echo "================================================================================"
echo "DATABASE STATISTICS (LLM MUST quote these verbatim):"
echo "================================================================================"

TOTAL_ERRORS=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM errors;")
TOTAL_METRICS=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM system_metrics;")
ERRORS_WITH_CONTENTION=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM errors_during_contention;")

echo "Total errors in database: $TOTAL_ERRORS"
echo "Total metric samples: $TOTAL_METRICS"
echo "Errors during resource contention: $ERRORS_WITH_CONTENTION"

if [ "$ERRORS_WITH_CONTENTION" -gt 0 ] && [ "$TOTAL_ERRORS" -gt 0 ]; then
    CONTENTION_PCT=$(sqlite3 "$DB_FILE" "SELECT ROUND(100.0 * (SELECT COUNT(*) FROM errors_during_contention) / (SELECT COUNT(*) FROM errors), 1);")
    echo "Percentage of errors during contention: ${CONTENTION_PCT}%"
    
    echo ""
    echo "🔥 CRITICAL FINDING: ${CONTENTION_PCT}% of errors occurred during resource contention"
    echo "🔥 LLM MUST acknowledge this correlation in response"
fi

echo ""
echo "================================================================================"
echo "END OF FORCED OUTPUT - LLM MUST HAVE READ ALL ABOVE DATA"
echo "================================================================================"

