#!/usr/bin/env bash
#
# Initialize Error Tracking Database
#
# PURPOSE:
# - Track ALL errors from VS Code extension logs
# - Correlate errors with system resource metrics
# - Prevent LLM from ignoring/overlooking errors
# - Database-driven queries force LLM to see ALL data
#
# BUG BOUNTY CONNECTION:
# - LLM ignoring "Request cancelled" errors (52 occurrences)
# - LLM not correlating errors with resource contention
# - Terminal output truncated/ignored
# - Database prevents oversight - MUST query to see data
#
# ANTI-RECALCITRANCE:
# - Every error logged to database (no truncation)
# - LLM must query database (can't ignore)
# - Automatic correlation with system metrics
# - Forced transparency through SQL queries

set -euo pipefail

DB_FILE=".augment/error_tracking.db"

echo "🗄️  Initializing Error Tracking Database: $DB_FILE"

# Create database and tables
sqlite3 "$DB_FILE" <<'EOF'
-- Table: errors
-- Tracks EVERY error from VS Code extension logs
CREATE TABLE IF NOT EXISTS errors (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT NOT NULL,           -- ISO 8601 timestamp
    log_file TEXT NOT NULL,            -- Source log file
    error_type TEXT NOT NULL,          -- 'Request cancelled', 'fetch failed', etc.
    error_message TEXT NOT NULL,       -- Full error message
    stack_trace TEXT,                  -- Stack trace if available
    stack_lines INTEGER DEFAULT 0,     -- Number of stack trace lines
    extension_name TEXT,               -- Which extension (Augment, etc.)
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Table: system_metrics
-- Tracks system resource metrics at time of error
CREATE TABLE IF NOT EXISTS system_metrics (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT NOT NULL,
    load_avg REAL NOT NULL,            -- 1-minute load average
    memory_used_mb INTEGER NOT NULL,   -- Total memory used (MB)
    swap_used_mb INTEGER NOT NULL,     -- Swap used (MB)
    vscode_cpu_pct REAL,               -- VS Code total CPU %
    vscode_memory_mb INTEGER,          -- VS Code total memory (MB)
    runaway_processes INTEGER DEFAULT 0, -- Count of runaway processes
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);

-- Table: error_correlation
-- Links errors to system metrics (many-to-one)
CREATE TABLE IF NOT EXISTS error_correlation (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    error_id INTEGER NOT NULL,
    metric_id INTEGER NOT NULL,
    time_diff_seconds INTEGER,         -- Time between error and metric sample
    FOREIGN KEY (error_id) REFERENCES errors(id) ON DELETE CASCADE,
    FOREIGN KEY (metric_id) REFERENCES system_metrics(id) ON DELETE CASCADE
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_errors_timestamp ON errors(timestamp);
CREATE INDEX IF NOT EXISTS idx_errors_type ON errors(error_type);
CREATE INDEX IF NOT EXISTS idx_metrics_timestamp ON system_metrics(timestamp);
CREATE INDEX IF NOT EXISTS idx_correlation_error ON error_correlation(error_id);

-- View: Errors with system context
CREATE VIEW IF NOT EXISTS errors_with_context AS
SELECT 
    e.id,
    e.timestamp,
    e.error_type,
    e.error_message,
    e.stack_lines,
    m.load_avg,
    m.memory_used_mb,
    m.swap_used_mb,
    m.vscode_cpu_pct,
    m.vscode_memory_mb,
    m.runaway_processes
FROM errors e
LEFT JOIN error_correlation ec ON e.id = ec.error_id
LEFT JOIN system_metrics m ON ec.metric_id = m.id
ORDER BY e.timestamp DESC;

-- View: Error frequency by type
CREATE VIEW IF NOT EXISTS error_frequency AS
SELECT 
    error_type,
    COUNT(*) as count,
    MIN(timestamp) as first_seen,
    MAX(timestamp) as last_seen,
    ROUND((julianday(MAX(timestamp)) - julianday(MIN(timestamp))) * 24 * 60, 2) as duration_minutes
FROM errors
GROUP BY error_type
ORDER BY count DESC;

-- View: Errors during high resource usage
CREATE VIEW IF NOT EXISTS errors_during_contention AS
SELECT 
    e.timestamp,
    e.error_type,
    e.error_message,
    m.load_avg,
    m.swap_used_mb,
    m.runaway_processes
FROM errors e
LEFT JOIN error_correlation ec ON e.id = ec.error_id
LEFT JOIN system_metrics m ON ec.metric_id = m.id
WHERE m.load_avg > 2.0 OR m.swap_used_mb > 500 OR m.runaway_processes > 0
ORDER BY e.timestamp DESC;

-- View: Resource contention timeline
CREATE VIEW IF NOT EXISTS resource_timeline AS
SELECT 
    timestamp,
    load_avg,
    memory_used_mb,
    swap_used_mb,
    vscode_cpu_pct,
    vscode_memory_mb,
    runaway_processes,
    (SELECT COUNT(*) FROM errors e WHERE e.timestamp BETWEEN datetime(system_metrics.timestamp, '-1 minute') AND system_metrics.timestamp) as errors_in_last_minute
FROM system_metrics
ORDER BY timestamp DESC;

EOF

echo "✅ Database initialized successfully"
echo ""
echo "📊 Database schema:"
sqlite3 "$DB_FILE" ".schema" | head -30
echo ""
echo "🎯 Usage:"
echo "  - Query errors: sqlite3 $DB_FILE 'SELECT * FROM errors ORDER BY id DESC LIMIT 10'"
echo "  - Error frequency: sqlite3 $DB_FILE 'SELECT * FROM error_frequency'"
echo "  - Errors with context: sqlite3 $DB_FILE 'SELECT * FROM errors_with_context LIMIT 10'"
echo "  - Resource timeline: sqlite3 $DB_FILE 'SELECT * FROM resource_timeline LIMIT 10'"
echo ""
echo "🔥 Error Tracking Database Ready!"

