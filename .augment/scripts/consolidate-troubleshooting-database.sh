#!/usr/bin/env bash
set -euo pipefail

# USER REQUEST: "check log database and use more database tools to consolidate and pinpoint troubleshooting issues"
# PURPOSE: Aggregate watchdog events into SQLite database for trend analysis and root cause identification
# PROBLEM: Logs are scattered across multiple files, hard to correlate events over time
# SOLUTION: Parse watchdog log into structured database, run SQL queries to identify patterns
# TROUBLESHOOTING VALUE: Find which events correlate with FD spikes, OOM, crashes

LOGFILE=".notes/consolidate-db-$(date +%Y%m%d-%H%M%S).log"
mkdir -p .notes
exec > >(tee -a "$LOGFILE") 2>&1

echo "START: consolidate-troubleshooting-database"
echo ""

# DATABASE SCHEMA:
# events table: timestamp, event_type, severity, message, metric_value
# fd_breakdown table: timestamp, fd_type, count
# top_consumers table: timestamp, process, pid, fd_num, fd_type, count
# correlations view: joins events with FD spikes to find root causes

DB_PATH=".notes/watchdog-troubleshooting.db"

echo "═══════════════════════════════════════════════════════════════════"
echo "STEP 1: Create database schema"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

# CREATE DATABASE SCHEMA
# events: All watchdog events (errors, warnings, heartbeats)
# fd_breakdown: FD type distribution over time (REG/unix/pipe counts)
# top_consumers: Which processes consuming most FDs
# BENEFIT: SQL queries can find "when FD count spiked, what errors occurred?"
sqlite3 "$DB_PATH" <<'SQL'
CREATE TABLE IF NOT EXISTS events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT NOT NULL,
    event_type TEXT NOT NULL,
    severity TEXT,
    message TEXT,
    metric_value INTEGER,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS fd_breakdown (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT NOT NULL,
    fd_type TEXT NOT NULL,
    count INTEGER NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE TABLE IF NOT EXISTS top_consumers (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT NOT NULL,
    process TEXT NOT NULL,
    pid INTEGER NOT NULL,
    fd_num TEXT,
    fd_type TEXT,
    count INTEGER NOT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS idx_events_timestamp ON events(timestamp);
CREATE INDEX IF NOT EXISTS idx_events_type ON events(event_type);
CREATE INDEX IF NOT EXISTS idx_fd_breakdown_timestamp ON fd_breakdown(timestamp);
CREATE INDEX IF NOT EXISTS idx_top_consumers_timestamp ON top_consumers(timestamp);
CREATE INDEX IF NOT EXISTS idx_top_consumers_pid ON top_consumers(pid);
SQL

echo "✅ Database schema created: $DB_PATH"
echo ""

echo "═══════════════════════════════════════════════════════════════════"
echo "STEP 2: Find and parse watchdog log"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

WATCHDOG_LOG=$(find ~/.config/Code/logs -path "*/exthost/output_logging_*/1-Watchdog Log.log" -type f 2>/dev/null | sort | tail -1)

if [ -z "$WATCHDOG_LOG" ]; then
    echo "❌ No watchdog log found"
    exit 1
fi

echo "✅ Watchdog log: $WATCHDOG_LOG"
echo "   Size: $(wc -l < "$WATCHDOG_LOG") lines"
echo ""

echo "═══════════════════════════════════════════════════════════════════"
echo "STEP 3: Parse events into database"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

# PARSE EVENTS
# Extract: [timestamp] EVENT_TYPE | message | metric=value
# Examples:
#   [2026-02-18T18:02:09.597Z] HEARTBEAT | terminals=8 | cancellations=0
#   [2026-02-18T18:02:12.694Z] FILE DESCRIPTOR WARNING | VS Code FDs=52503 | threshold=50000
#   [2026-02-18T18:02:09.710Z] EXTENSION ERROR | VS Code logs (last 1min) | count=20
# BENEFIT: Structured data enables SQL queries like "show all errors before FD spike"

echo "Parsing events..."
grep -E "HEARTBEAT|FILE DESCRIPTOR WARNING|EXTENSION ERROR|SYSTEM ERROR|OOM|CRASH" "$WATCHDOG_LOG" | while IFS= read -r line; do
    # Extract timestamp: [2026-02-18T18:02:09.597Z]
    timestamp=$(echo "$line" | grep -oP '\[\K[^\]]+')
    
    # Extract event type: HEARTBEAT, FILE DESCRIPTOR WARNING, etc
    event_type=$(echo "$line" | grep -oP '\] \K[A-Z ]+(?= \|)')
    
    # Extract full message
    message=$(echo "$line" | sed 's/^\[[^]]*\] //')
    
    # Extract metric value if present (FDs=52503, count=20, etc)
    metric_value=$(echo "$message" | grep -oP '(FDs|count|terminals)=\K[0-9]+' | head -1 || echo "NULL")
    
    # Determine severity
    severity="INFO"
    if echo "$event_type" | grep -q "ERROR"; then severity="ERROR"; fi
    if echo "$event_type" | grep -q "WARNING"; then severity="WARNING"; fi
    
    # Insert into database
    sqlite3 "$DB_PATH" "INSERT INTO events (timestamp, event_type, severity, message, metric_value) VALUES ('$timestamp', '$event_type', '$severity', $(echo "$message" | sed "s/'/''/g" | awk '{print "'"'"'" $0 "'"'"'"}'), $metric_value);"
done

EVENT_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM events;")
echo "✅ Parsed $EVENT_COUNT events"
echo ""

echo "═══════════════════════════════════════════════════════════════════"
echo "STEP 4: Parse FD breakdown into database"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

# PARSE FD BREAKDOWN
# Extract: timestamp + "FD breakdown by type:" + following lines with counts
# Example:
#   [2026-02-18T18:02:17.163Z]   FD breakdown by type:
#   [2026-02-18T18:02:17.163Z]       40415 REG
#   [2026-02-18T18:02:17.163Z]        4221 a_inode
# BENEFIT: Track FD type trends over time (is REG count growing? unix count stable?)

echo "Parsing FD breakdown..."
current_timestamp=""
grep -A 20 "FD breakdown by type:" "$WATCHDOG_LOG" | while IFS= read -r line; do
    if echo "$line" | grep -q "FD breakdown by type:"; then
        current_timestamp=$(echo "$line" | grep -oP '\[\K[^\]]+')
    elif [ -n "$current_timestamp" ] && echo "$line" | grep -qP '^\[[^\]]+\]\s+\d+\s+\w+'; then
        count=$(echo "$line" | grep -oP '\]\s+\K\d+')
        fd_type=$(echo "$line" | grep -oP '\d+\s+\K\w+')
        sqlite3 "$DB_PATH" "INSERT INTO fd_breakdown (timestamp, fd_type, count) VALUES ('$current_timestamp', '$fd_type', $count);"
    fi
done

FD_BREAKDOWN_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM fd_breakdown;")
echo "✅ Parsed $FD_BREAKDOWN_COUNT FD breakdown entries"
echo ""

echo "═══════════════════════════════════════════════════════════════════"
echo "STEP 5: Run troubleshooting queries"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

# QUERY 1: FD spike correlation with errors
# TROUBLESHOOTING: Did errors occur right before FD spike?
echo "QUERY 1: Errors within 5 minutes before FD warnings"
echo "─────────────────────────────────────────────────────────────────"
sqlite3 -header -column "$DB_PATH" <<'SQL'
SELECT 
    e.timestamp,
    e.event_type,
    e.message,
    (SELECT metric_value FROM events WHERE event_type='FILE DESCRIPTOR WARNING' AND timestamp > e.timestamp ORDER BY timestamp LIMIT 1) as next_fd_count
FROM events e
WHERE e.severity = 'ERROR'
AND EXISTS (
    SELECT 1 FROM events fd 
    WHERE fd.event_type = 'FILE DESCRIPTOR WARNING' 
    AND fd.timestamp > e.timestamp 
    AND (julianday(fd.timestamp) - julianday(e.timestamp)) * 24 * 60 < 5
)
ORDER BY e.timestamp DESC
LIMIT 10;
SQL
echo ""

# QUERY 2: FD type growth trend
# TROUBLESHOOTING: Which FD type is growing fastest?
echo "QUERY 2: FD type growth trend (latest vs earliest)"
echo "─────────────────────────────────────────────────────────────────"
sqlite3 -header -column "$DB_PATH" <<'SQL'
WITH latest AS (
    SELECT fd_type, SUM(count) as latest_count
    FROM fd_breakdown
    WHERE timestamp = (SELECT MAX(timestamp) FROM fd_breakdown)
    GROUP BY fd_type
),
earliest AS (
    SELECT fd_type, SUM(count) as earliest_count
    FROM fd_breakdown
    WHERE timestamp = (SELECT MIN(timestamp) FROM fd_breakdown)
    GROUP BY fd_type
)
SELECT 
    l.fd_type,
    COALESCE(e.earliest_count, 0) as earliest,
    l.latest_count as latest,
    l.latest_count - COALESCE(e.earliest_count, 0) as growth,
    ROUND((l.latest_count - COALESCE(e.earliest_count, 0)) * 100.0 / NULLIF(e.earliest_count, 0), 1) as growth_pct
FROM latest l
LEFT JOIN earliest e ON l.fd_type = e.fd_type
ORDER BY growth DESC;
SQL
echo ""

echo "END: consolidate-troubleshooting-database"

