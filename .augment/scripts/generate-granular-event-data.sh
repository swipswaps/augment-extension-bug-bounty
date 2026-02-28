#!/usr/bin/env bash
set -euo pipefail

# USER REQUEST: "visualization with granularity of error, event, system and application relevant messages was expected"
# PROBLEM: Current visualizations show aggregated FD counts, not individual error messages
# SOLUTION: Generate JSON data with FULL VERBATIM error messages, events, and system logs
# VISUALIZATION GOAL: Timeline showing each error/event with full message text, not just counts
# TROUBLESHOOTING VALUE: See exact error "Request cancelled" at 12:56:04, not just "10 errors occurred"

LOGFILE=".notes/generate-granular-data-$(date +%Y%m%d-%H%M%S).log"
mkdir -p .notes
exec > >(tee -a "$LOGFILE") 2>&1

echo "START: generate-granular-event-data"
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
echo "STEP 1: Extract ALL error messages with full verbatim text"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

# VISUALIZATION 1: Error timeline with FULL error messages (not just counts)
# EACH POINT: timestamp, severity, full error message, source file
# TROUBLESHOOTING: Click on point to see exact error text
# EXAMPLE: "2026-02-18 12:56:04.261 [error] 'ClientWorkspaces': Failed to call chat input completion API Request cancelled"
sqlite3 -json "$DB_PATH" <<'SQL' > "$VIZ_DIR/error-messages.json"
SELECT 
    timestamp,
    event_type,
    severity,
    message,
    CASE severity
        WHEN 'ERROR' THEN 'critical'
        WHEN 'WARNING' THEN 'warning'
        ELSE 'info'
    END as status
FROM events
WHERE severity IN ('ERROR', 'WARNING', 'INFO')
ORDER BY timestamp ASC;
SQL

echo "✅ Generated: $VIZ_DIR/error-messages.json"
echo "   Contains: $(jq 'length' "$VIZ_DIR/error-messages.json") error/warning/info messages"
echo ""
echo "Sample error messages:"
jq -r '.[] | "  [\(.timestamp)] \(.severity): \(.message)"' "$VIZ_DIR/error-messages.json" | head -10
echo ""

echo "═══════════════════════════════════════════════════════════════════"
echo "STEP 2: Extract ALL system events with full details"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

# VISUALIZATION 2: System event timeline with FULL event details
# EACH POINT: timestamp, event type, metric value, full message
# TROUBLESHOOTING: See exact FD count at each measurement, not aggregated
# EXAMPLE: "FILE DESCRIPTOR WARNING | VS Code FDs=60528 | threshold=50000"
sqlite3 -json "$DB_PATH" <<'SQL' > "$VIZ_DIR/system-events.json"
SELECT 
    timestamp,
    event_type,
    severity,
    message,
    metric_value,
    CASE 
        WHEN event_type = 'FILE DESCRIPTOR WARNING' AND metric_value > 55000 THEN 'critical'
        WHEN event_type = 'FILE DESCRIPTOR WARNING' AND metric_value > 50000 THEN 'warning'
        WHEN event_type = 'HEARTBEAT' THEN 'info'
        ELSE 'normal'
    END as status
FROM events
WHERE event_type IN ('FILE DESCRIPTOR WARNING', 'HEARTBEAT', 'MONITORING STARTED')
ORDER BY timestamp ASC;
SQL

echo "✅ Generated: $VIZ_DIR/system-events.json"
echo "   Contains: $(jq 'length' "$VIZ_DIR/system-events.json") system events"
echo ""
echo "Sample system events:"
jq -r '.[] | "  [\(.timestamp)] \(.event_type): \(.message // "N/A") (metric=\(.metric_value // "N/A"))"' "$VIZ_DIR/system-events.json" | head -10
echo ""

echo "═══════════════════════════════════════════════════════════════════"
echo "STEP 3: Extract FD breakdown with FULL detail per timestamp"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

# VISUALIZATION 3: FD breakdown timeline showing EACH measurement
# EACH POINT: timestamp, FD type, count (not aggregated)
# TROUBLESHOOTING: See exact REG count at 18:01 (48,282), not just "REG decreased"
# EXAMPLE: "2026-02-18T18:01:16.433Z | REG: 48,282 | unix: 3,037 | pipe: 2,666"
sqlite3 -json "$DB_PATH" <<'SQL' > "$VIZ_DIR/fd-breakdown-timeline.json"
SELECT 
    timestamp,
    fd_type,
    count,
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
ORDER BY timestamp ASC, count DESC;
SQL

echo "✅ Generated: $VIZ_DIR/fd-breakdown-timeline.json"
echo "   Contains: $(jq 'length' "$VIZ_DIR/fd-breakdown-timeline.json") FD breakdown measurements"
echo ""
echo "Sample FD breakdown:"
jq -r 'group_by(.timestamp) | .[] | "  [\(.[0].timestamp)] " + (map("\(.fd_type)=\(.count)") | join(", "))' "$VIZ_DIR/fd-breakdown-timeline.json" | head -5
echo ""

echo "═══════════════════════════════════════════════════════════════════"
echo "STEP 4: Extract application logs from watchdog with FULL messages"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

# VISUALIZATION 4: Application log viewer with FULL verbatim log lines
# EACH ENTRY: timestamp, log file, full log line (not truncated)
# TROUBLESHOOTING: See exact log line "Augment.log: 2026-02-18 12:56:04.261 [error] 'ClientWorkspaces': Failed to call chat input completion API Request cancelled"
# SOURCE: Parse watchdog log for "EXTENSION ERROR" entries with full messages

WATCHDOG_LOG=$(find ~/.config/Code/logs -path "*/exthost/output_logging_*/1-Watchdog Log.log" -type f 2>/dev/null | sort | tail -1)

if [ -f "$WATCHDOG_LOG" ]; then
    echo "Parsing watchdog log: $WATCHDOG_LOG"
    
    # EXTRACT: All log entries with timestamps and full messages
    # FORMAT: [timestamp] source.log: full error message
    # FILTER: Only entries with actual error/warning content (not just counts)
    grep -E '\[20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z\]' "$WATCHDOG_LOG" | \
    grep -E '(\.log:|ERROR|WARNING|CRITICAL)' | \
    grep -v 'count=' | \
    awk -F'\\[|\\]' '{
        timestamp = $2
        rest = substr($0, index($0, "]") + 2)
        
        # Extract log file name if present
        if (match(rest, /([A-Za-z0-9_-]+\.log):/, arr)) {
            source = arr[1]
            message = substr(rest, RSTART + RLENGTH + 1)
        } else {
            source = "watchdog"
            message = rest
        }
        
        # Determine severity
        severity = "INFO"
        if (match(message, /error|ERROR|failed|FAILED/)) severity = "ERROR"
        else if (match(message, /warn|WARNING/)) severity = "WARNING"
        
        # Output JSON
        gsub(/"/, "\\\"", message)
        gsub(/\t/, " ", message)
        print "{\"timestamp\":\"" timestamp "\",\"source\":\"" source "\",\"severity\":\"" severity "\",\"message\":\"" message "\"}"
    }' | jq -s '.' > "$VIZ_DIR/application-logs.json"
    
    echo "✅ Generated: $VIZ_DIR/application-logs.json"
    echo "   Contains: $(jq 'length' "$VIZ_DIR/application-logs.json") application log entries"
    echo ""
    echo "Sample application logs:"
    jq -r '.[] | "  [\(.timestamp)] \(.source): \(.message)"' "$VIZ_DIR/application-logs.json" | head -10
else
    echo "⚠️  Watchdog log not found, creating empty application-logs.json"
    echo "[]" > "$VIZ_DIR/application-logs.json"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "STEP 5: Create combined event stream with ALL messages"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

# VISUALIZATION 5: Unified timeline showing ALL events/errors/logs in chronological order
# EACH ENTRY: timestamp, type (error/system/app), severity, full message
# TROUBLESHOOTING: See complete picture - errors, FD warnings, and app logs together
# EXAMPLE: See "Request cancelled" error at same time as FD spike
jq -s '
    (.[0] | map({timestamp, type: "error", severity, message, status})) +
    (.[1] | map({timestamp, type: "system", severity, message, status, metric_value})) +
    (.[2] | map({timestamp, type: "application", severity, message, source}))
    | sort_by(.timestamp)
' "$VIZ_DIR/error-messages.json" "$VIZ_DIR/system-events.json" "$VIZ_DIR/application-logs.json" > "$VIZ_DIR/unified-timeline.json"

echo "✅ Generated: $VIZ_DIR/unified-timeline.json"
echo "   Contains: $(jq 'length' "$VIZ_DIR/unified-timeline.json") total events"
echo ""
echo "Sample unified timeline:"
jq -r '.[] | "  [\(.timestamp)] [\(.type)] \(.severity): \(.message // "N/A")"' "$VIZ_DIR/unified-timeline.json" | head -15
echo ""

echo "═══════════════════════════════════════════════════════════════════"
echo "GRANULAR EVENT DATA GENERATED"
echo "═══════════════════════════════════════════════════════════════════"
echo ""
echo "Output directory: $VIZ_DIR"
echo ""
echo "Files generated:"
ls -lh "$VIZ_DIR"/*.json | grep -E '(error-messages|system-events|fd-breakdown-timeline|application-logs|unified-timeline)'
echo ""
echo "Next step: Create granular visualization dashboard"
echo "  Run: bash .augment/scripts/create-granular-dashboard.sh"
echo ""

echo "END: generate-granular-event-data"

