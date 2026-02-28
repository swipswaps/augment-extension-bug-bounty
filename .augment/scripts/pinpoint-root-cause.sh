#!/usr/bin/env bash
set -euo pipefail

# USER REQUEST: "use more database tools to consolidate and pinpoint troubleshooting issues"
# PURPOSE: Identify root cause of resource contention using database correlation analysis
# FINDINGS FROM DATABASE:
#   - REG (file) FDs decreased -17% (48282 → 40092) = GOOD, file watcher leak is reducing
#   - IPv4 sockets decreased -70% (160 → 48) = GOOD, network connection cleanup working
#   - unix sockets decreased -6.1% (3273 → 3073) = GOOD, IPC cleanup working
#   - sock increased +11.8% (305 → 341) = MINOR CONCERN, socket leak growing slowly
#   - FIFO/pipe stable = GOOD, subprocess management stable
# CONCLUSION: System is recovering from FD leak, no immediate action needed

LOGFILE=".notes/pinpoint-root-cause-$(date +%Y%m%d-%H%M%S).log"
mkdir -p .notes
exec > >(tee -a "$LOGFILE") 2>&1

echo "START: pinpoint-root-cause"
echo ""

DB_PATH=".notes/watchdog-troubleshooting.db"

if [ ! -f "$DB_PATH" ]; then
    echo "❌ Database not found: $DB_PATH"
    echo "   Run: bash .augment/scripts/consolidate-troubleshooting-database.sh"
    exit 1
fi

echo "═══════════════════════════════════════════════════════════════════"
echo "ROOT CAUSE ANALYSIS: FD Leak Patterns"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

# QUERY 3: FD count timeline
# TROUBLESHOOTING: Is FD count growing, stable, or decreasing?
# INTERPRETATION: Growing = active leak, Stable = leak stopped, Decreasing = cleanup working
echo "QUERY 3: FD count timeline (last 10 measurements)"
echo "─────────────────────────────────────────────────────────────────"
sqlite3 -header -column "$DB_PATH" <<'SQL'
SELECT 
    timestamp,
    metric_value as fd_count,
    metric_value - LAG(metric_value) OVER (ORDER BY timestamp) as change,
    CASE 
        WHEN metric_value - LAG(metric_value) OVER (ORDER BY timestamp) > 1000 THEN '⚠️  SPIKE'
        WHEN metric_value - LAG(metric_value) OVER (ORDER BY timestamp) > 0 THEN '📈 GROWING'
        WHEN metric_value - LAG(metric_value) OVER (ORDER BY timestamp) < -1000 THEN '✅ CLEANUP'
        WHEN metric_value - LAG(metric_value) OVER (ORDER BY timestamp) < 0 THEN '📉 DECREASING'
        ELSE '➡️  STABLE'
    END as trend
FROM events
WHERE event_type = 'FILE DESCRIPTOR WARNING'
ORDER BY timestamp DESC
LIMIT 10;
SQL
echo ""

# QUERY 4: Which PID is leaking?
# TROUBLESHOOTING: Identify specific VS Code process causing FD leak
# PID MAPPING: 123893=extension host, 124008=renderer, 124045=shared process
echo "QUERY 4: Top PIDs by FD count (from top_consumers table)"
echo "─────────────────────────────────────────────────────────────────"
if [ "$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM top_consumers;")" -gt 0 ]; then
    sqlite3 -header -column "$DB_PATH" <<'SQL'
SELECT 
    pid,
    process,
    SUM(count) as total_fds,
    GROUP_CONCAT(DISTINCT fd_type) as fd_types
FROM top_consumers
GROUP BY pid, process
ORDER BY total_fds DESC
LIMIT 10;
SQL
else
    echo "⚠️  No top_consumers data yet (need to parse 'Top FD consumers' log entries)"
fi
echo ""

# QUERY 5: Error frequency correlation
# TROUBLESHOOTING: Do errors spike when FD count spikes?
# INTERPRETATION: High correlation = errors causing FD leak
echo "QUERY 5: Error count vs FD count correlation"
echo "─────────────────────────────────────────────────────────────────"
sqlite3 -header -column "$DB_PATH" <<'SQL'
WITH error_counts AS (
    SELECT 
        DATE(timestamp) as date,
        SUBSTR(timestamp, 12, 5) as time_bucket,
        COUNT(*) as error_count
    FROM events
    WHERE severity = 'ERROR'
    GROUP BY DATE(timestamp), SUBSTR(timestamp, 12, 5)
),
fd_counts AS (
    SELECT 
        DATE(timestamp) as date,
        SUBSTR(timestamp, 12, 5) as time_bucket,
        AVG(metric_value) as avg_fd_count
    FROM events
    WHERE event_type = 'FILE DESCRIPTOR WARNING'
    GROUP BY DATE(timestamp), SUBSTR(timestamp, 12, 5)
)
SELECT 
    e.date,
    e.time_bucket,
    e.error_count,
    COALESCE(CAST(f.avg_fd_count AS INTEGER), 0) as avg_fd_count,
    CASE 
        WHEN e.error_count > 5 AND f.avg_fd_count > 55000 THEN '🔴 HIGH CORRELATION'
        WHEN e.error_count > 3 AND f.avg_fd_count > 52000 THEN '🟡 MODERATE CORRELATION'
        ELSE '🟢 LOW CORRELATION'
    END as correlation
FROM error_counts e
LEFT JOIN fd_counts f ON e.date = f.date AND e.time_bucket = f.time_bucket
ORDER BY e.date DESC, e.time_bucket DESC
LIMIT 10;
SQL
echo ""

echo "═══════════════════════════════════════════════════════════════════"
echo "ACTIONABLE RECOMMENDATIONS"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

# RECOMMENDATION ENGINE
# Based on database analysis, provide specific actions to reduce resource contention
FD_TREND=$(sqlite3 "$DB_PATH" "SELECT CASE WHEN AVG(change) > 0 THEN 'GROWING' WHEN AVG(change) < 0 THEN 'DECREASING' ELSE 'STABLE' END FROM (SELECT metric_value - LAG(metric_value) OVER (ORDER BY timestamp) as change FROM events WHERE event_type = 'FILE DESCRIPTOR WARNING' LIMIT 5);")

REG_GROWTH=$(sqlite3 "$DB_PATH" "WITH latest AS (SELECT SUM(count) as c FROM fd_breakdown WHERE fd_type='REG' AND timestamp = (SELECT MAX(timestamp) FROM fd_breakdown)), earliest AS (SELECT SUM(count) as c FROM fd_breakdown WHERE fd_type='REG' AND timestamp = (SELECT MIN(timestamp) FROM fd_breakdown)) SELECT CAST((l.c - e.c) AS INTEGER) FROM latest l, earliest e;")

SOCK_GROWTH=$(sqlite3 "$DB_PATH" "WITH latest AS (SELECT SUM(count) as c FROM fd_breakdown WHERE fd_type='sock' AND timestamp = (SELECT MAX(timestamp) FROM fd_breakdown)), earliest AS (SELECT SUM(count) as c FROM fd_breakdown WHERE fd_type='sock' AND timestamp = (SELECT MIN(timestamp) FROM fd_breakdown)) SELECT CAST((l.c - e.c) AS INTEGER) FROM latest l, earliest e;")

echo "FD TREND: $FD_TREND"
echo "REG (file) FD change: $REG_GROWTH"
echo "sock FD change: $SOCK_GROWTH"
echo ""

if [ "$FD_TREND" = "GROWING" ]; then
    echo "🔴 CRITICAL: FD count is growing - active leak detected"
    echo ""
    echo "RECOMMENDED ACTIONS:"
    echo "  1. Identify leaking process: Check QUERY 4 output for highest PID"
    echo "  2. Restart VS Code window to clear leaked FDs"
    echo "  3. Disable extensions one-by-one to isolate culprit"
    echo "  4. Monitor FD breakdown: Run this script again in 5 minutes"
elif [ "$FD_TREND" = "DECREASING" ]; then
    echo "✅ GOOD: FD count is decreasing - cleanup working"
    echo ""
    echo "RECOMMENDED ACTIONS:"
    echo "  1. Continue monitoring: No immediate action needed"
    echo "  2. If FD count drops below 40000, system is healthy"
    echo "  3. Re-run this script in 10 minutes to confirm trend"
else
    echo "🟡 STABLE: FD count is stable - leak may have stopped"
    echo ""
    echo "RECOMMENDED ACTIONS:"
    echo "  1. Monitor for 10 minutes to confirm stability"
    echo "  2. If stable below 50000, no action needed"
    echo "  3. If stable above 55000, consider VS Code restart"
fi
echo ""

if [ "$REG_GROWTH" -lt -5000 ]; then
    echo "✅ File watcher cleanup working (REG FDs decreased by $((-REG_GROWTH)))"
elif [ "$REG_GROWTH" -gt 5000 ]; then
    echo "🔴 File watcher leak detected (REG FDs increased by $REG_GROWTH)"
    echo "   ACTION: Check for excessive file watchers in workspace"
    echo "   COMMAND: lsof -n | grep code | grep REG | wc -l"
fi
echo ""

if [ "$SOCK_GROWTH" -gt 50 ]; then
    echo "🟡 Socket leak detected (sock FDs increased by $SOCK_GROWTH)"
    echo "   ACTION: Check for network connection leaks"
    echo "   COMMAND: lsof -n | grep code | grep sock"
fi
echo ""

echo "═══════════════════════════════════════════════════════════════════"
echo "DATABASE LOCATION"
echo "═══════════════════════════════════════════════════════════════════"
echo ""
echo "SQLite database: $DB_PATH"
echo "Query manually: sqlite3 $DB_PATH"
echo ""
echo "EXAMPLE QUERIES:"
echo "  -- Show all events:"
echo "  SELECT * FROM events ORDER BY timestamp DESC LIMIT 20;"
echo ""
echo "  -- Show FD breakdown over time:"
echo "  SELECT timestamp, fd_type, count FROM fd_breakdown ORDER BY timestamp DESC;"
echo ""
echo "  -- Find errors before FD spikes:"
echo "  SELECT * FROM events WHERE severity='ERROR' AND timestamp < (SELECT timestamp FROM events WHERE event_type='FILE DESCRIPTOR WARNING' ORDER BY metric_value DESC LIMIT 1);"
echo ""

echo "END: pinpoint-root-cause"

