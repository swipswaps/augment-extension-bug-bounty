#!/usr/bin/env bash
set -euo pipefail

# USER REQUEST: "show with react and or d3.js visualizations of evidence what processes persist at stalling or slowing"
# PURPOSE: Generate JSON data for React/D3.js visualizations showing process resource contention over time
# VISUALIZATION GOALS:
#   1. Timeline chart: FD count over time (identify when stalling occurs)
#   2. Process breakdown: Which PIDs consume most resources (identify culprit processes)
#   3. FD type distribution: Pie chart showing REG/unix/pipe breakdown (identify leak type)
#   4. Correlation heatmap: Errors vs FD spikes (identify if errors cause stalling)
# TROUBLESHOOTING VALUE: Visual evidence of "PID 123893 has growing REG FDs correlating with slowdowns"

LOGFILE=".notes/generate-viz-data-$(date +%Y%m%d-%H%M%S).log"
mkdir -p .notes
exec > >(tee -a "$LOGFILE") 2>&1

echo "START: generate-visualization-data"
echo ""

DB_PATH=".notes/watchdog-troubleshooting.db"
VIZ_DIR=".notes/visualizations"
mkdir -p "$VIZ_DIR"

if [ ! -f "$DB_PATH" ]; then
    echo "❌ Database not found: $DB_PATH"
    echo "   Run: bash .augment/scripts/consolidate-troubleshooting-database.sh"
    exit 1
fi

echo "═══════════════════════════════════════════════════════════════════"
echo "STEP 1: Generate timeline data (FD count over time)"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

# VISUALIZATION 1: Line chart showing FD count timeline
# X-AXIS: timestamp
# Y-AXIS: FD count
# THRESHOLD LINE: 50000 (warning threshold)
# ANNOTATIONS: Mark points where errors occurred
# TROUBLESHOOTING: Identify when stalling started (FD spike), when it recovered (FD drop)
sqlite3 -json "$DB_PATH" <<'SQL' > "$VIZ_DIR/timeline.json"
SELECT 
    timestamp,
    metric_value as fd_count,
    CASE 
        WHEN metric_value > 55000 THEN 'critical'
        WHEN metric_value > 50000 THEN 'warning'
        ELSE 'normal'
    END as status,
    (SELECT COUNT(*) FROM events e WHERE e.severity='ERROR' AND e.timestamp BETWEEN datetime(events.timestamp, '-1 minute') AND events.timestamp) as errors_in_last_minute
FROM events
WHERE event_type = 'FILE DESCRIPTOR WARNING'
ORDER BY timestamp ASC;
SQL

echo "✅ Generated: $VIZ_DIR/timeline.json"
cat "$VIZ_DIR/timeline.json" | jq '.' | head -30
echo ""

echo "═══════════════════════════════════════════════════════════════════"
echo "STEP 2: Generate FD type distribution data (pie chart)"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

# VISUALIZATION 2: Pie chart showing FD type breakdown
# SLICES: REG (file watchers), unix (IPC sockets), pipe (subprocesses), CHR (terminals), etc
# COLORS: REG=red (file leak), unix=blue (IPC leak), pipe=green (subprocess leak)
# TROUBLESHOOTING: Large REG slice = file watcher leak, large unix slice = IPC leak
sqlite3 -json "$DB_PATH" <<'SQL' > "$VIZ_DIR/fd-distribution.json"
SELECT 
    fd_type as name,
    SUM(count) as value,
    CASE fd_type
        WHEN 'REG' THEN 'File watchers (potential leak source)'
        WHEN 'unix' THEN 'IPC sockets (inter-process communication)'
        WHEN 'pipe' THEN 'Subprocess pipes'
        WHEN 'FIFO' THEN 'Named pipes'
        WHEN 'CHR' THEN 'Character devices (terminals)'
        WHEN 'DIR' THEN 'Directory handles'
        WHEN 'sock' THEN 'Network sockets'
        WHEN 'IPv4' THEN 'IPv4 network connections'
        WHEN 'IPv6' THEN 'IPv6 network connections'
        WHEN 'a_inode' THEN 'Anonymous inodes (eventfd, signalfd)'
        WHEN 'netlink' THEN 'Netlink sockets (kernel communication)'
        ELSE 'Other'
    END as description
FROM fd_breakdown
WHERE timestamp = (SELECT MAX(timestamp) FROM fd_breakdown)
GROUP BY fd_type
ORDER BY value DESC;
SQL

echo "✅ Generated: $VIZ_DIR/fd-distribution.json"
cat "$VIZ_DIR/fd-distribution.json" | jq '.'
echo ""

echo "═══════════════════════════════════════════════════════════════════"
echo "STEP 3: Generate FD type trend data (stacked area chart)"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

# VISUALIZATION 3: Stacked area chart showing FD type trends over time
# X-AXIS: timestamp
# Y-AXIS: FD count (stacked by type)
# LAYERS: REG (bottom), unix, pipe, FIFO, CHR, etc (stacked on top)
# TROUBLESHOOTING: If REG layer grows over time = file watcher leak, if unix grows = IPC leak
sqlite3 -json "$DB_PATH" <<'SQL' > "$VIZ_DIR/fd-trends.json"
SELECT 
    timestamp,
    fd_type,
    count
FROM fd_breakdown
ORDER BY timestamp ASC, fd_type ASC;
SQL

echo "✅ Generated: $VIZ_DIR/fd-trends.json"
cat "$VIZ_DIR/fd-trends.json" | jq '.' | head -50
echo ""

echo "═══════════════════════════════════════════════════════════════════"
echo "STEP 4: Generate process resource data (bar chart)"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

# VISUALIZATION 4: Horizontal bar chart showing top processes by FD count
# X-AXIS: FD count
# Y-AXIS: Process name + PID
# COLORS: Different color per process type (extension host, renderer, shared process)
# TROUBLESHOOTING: Longest bar = culprit process causing resource contention
# NOTE: Need to parse "Top FD consumers" log entries first (not yet implemented in consolidate script)

# WORKAROUND: Generate from current lsof snapshot
echo "Generating current process snapshot..."
lsof -n 2>/dev/null | grep code | awk '{cmd=$1; pid=$2; fd=""; type=""; for(i=3;i<=NF;i++) {if($i~/^[0-9]+[urw]$/) fd=$i; if($i~/^(REG|DIR|CHR|FIFO|unix|IPv4|IPv6|sock|pipe|a_inode|netlink)$/) type=$i} if(fd && type) print cmd, pid, fd, type}' | awk '{print $2}' | sort | uniq -c | sort -rn | head -10 | awk '{print "{\"pid\": " $2 ", \"fd_count\": " $1 ", \"process\": \"code\"}"}' | jq -s '.' > "$VIZ_DIR/process-resources.json"

echo "✅ Generated: $VIZ_DIR/process-resources.json"
cat "$VIZ_DIR/process-resources.json" | jq '.'
echo ""

echo "═══════════════════════════════════════════════════════════════════"
echo "STEP 5: Generate error correlation data (scatter plot)"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

# VISUALIZATION 5: Scatter plot showing error count vs FD count correlation
# X-AXIS: Error count in time window
# Y-AXIS: FD count
# POINT SIZE: Number of events in that time window
# TREND LINE: Linear regression showing correlation
# TROUBLESHOOTING: Points clustered in top-right = errors cause FD spikes (high correlation)
#                  Points scattered = errors unrelated to FD spikes (low correlation)
sqlite3 -json "$DB_PATH" <<'SQL' > "$VIZ_DIR/error-correlation.json"
WITH time_windows AS (
    SELECT 
        SUBSTR(timestamp, 1, 16) as time_window,
        COUNT(*) as error_count
    FROM events
    WHERE severity = 'ERROR'
    GROUP BY SUBSTR(timestamp, 1, 16)
),
fd_windows AS (
    SELECT 
        SUBSTR(timestamp, 1, 16) as time_window,
        AVG(metric_value) as avg_fd_count
    FROM events
    WHERE event_type = 'FILE DESCRIPTOR WARNING'
    GROUP BY SUBSTR(timestamp, 1, 16)
)
SELECT 
    COALESCE(e.time_window, f.time_window) as timestamp,
    COALESCE(e.error_count, 0) as error_count,
    COALESCE(CAST(f.avg_fd_count AS INTEGER), 0) as fd_count
FROM time_windows e
FULL OUTER JOIN fd_windows f ON e.time_window = f.time_window
ORDER BY timestamp ASC;
SQL

echo "✅ Generated: $VIZ_DIR/error-correlation.json"
cat "$VIZ_DIR/error-correlation.json" | jq '.'
echo ""

echo "═══════════════════════════════════════════════════════════════════"
echo "STEP 6: Generate summary statistics"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

# VISUALIZATION 6: Summary cards showing key metrics
# CARDS: Current FD count, Peak FD count, FD growth rate, Error count, Uptime
# TROUBLESHOOTING: Quick overview of system health
sqlite3 -json "$DB_PATH" <<'SQL' > "$VIZ_DIR/summary-stats.json"
SELECT 
    (SELECT metric_value FROM events WHERE event_type='FILE DESCRIPTOR WARNING' ORDER BY timestamp DESC LIMIT 1) as current_fd_count,
    (SELECT MAX(metric_value) FROM events WHERE event_type='FILE DESCRIPTOR WARNING') as peak_fd_count,
    (SELECT MIN(metric_value) FROM events WHERE event_type='FILE DESCRIPTOR WARNING') as min_fd_count,
    (SELECT COUNT(*) FROM events WHERE severity='ERROR') as total_errors,
    (SELECT COUNT(*) FROM events WHERE event_type='FILE DESCRIPTOR WARNING') as fd_measurements,
    (SELECT 
        CAST((MAX(metric_value) - MIN(metric_value)) * 1.0 / COUNT(*) AS INTEGER)
     FROM events 
     WHERE event_type='FILE DESCRIPTOR WARNING') as avg_fd_change_per_measurement;
SQL

echo "✅ Generated: $VIZ_DIR/summary-stats.json"
cat "$VIZ_DIR/summary-stats.json" | jq '.'
echo ""

echo "═══════════════════════════════════════════════════════════════════"
echo "VISUALIZATION DATA GENERATED"
echo "═══════════════════════════════════════════════════════════════════"
echo ""
echo "Output directory: $VIZ_DIR"
echo ""
echo "Files generated:"
ls -lh "$VIZ_DIR"/*.json
echo ""
echo "Next step: Create React/D3.js visualization dashboard"
echo "  Run: bash .augment/scripts/create-visualization-dashboard.sh"
echo ""

echo "END: generate-visualization-data"

