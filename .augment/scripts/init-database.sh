#!/bin/bash
# Initialize Anti-Recalcitrance Database
# Creates SQLite database to track ALL commands, outputs, and LLM violations
# WHY: Eliminates LLM recalcitrance by forcing complete transparency

set -euo pipefail

DB_FILE=".augment/command_history.db"

echo "🗄️  Initializing Anti-Recalcitrance Database: $DB_FILE"

# Create database and tables
sqlite3 "$DB_FILE" <<'EOF'
-- Table: commands
-- Tracks EVERY command executed, with timing and exit codes
CREATE TABLE IF NOT EXISTS commands (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT NOT NULL,           -- ISO 8601 timestamp
    command TEXT NOT NULL,              -- Full command executed
    cwd TEXT NOT NULL,                  -- Working directory
    exit_code INTEGER,                  -- Command exit code (0 = success)
    duration_ms INTEGER,                -- Execution time in milliseconds
    log_file TEXT,                      -- Path to log file with full output
    stdout_lines INTEGER DEFAULT 0,     -- Number of stdout lines
    stderr_lines INTEGER DEFAULT 0      -- Number of stderr lines
);

-- Table: outputs
-- Stores ALL stdout/stderr output for queryability
CREATE TABLE IF NOT EXISTS outputs (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    command_id INTEGER NOT NULL,
    stream TEXT NOT NULL,               -- 'stdout' or 'stderr'
    content TEXT NOT NULL,              -- Actual output content
    line_number INTEGER,                -- Line number in output
    FOREIGN KEY (command_id) REFERENCES commands(id) ON DELETE CASCADE
);

-- Table: llm_violations
-- Tracks when LLM fails to read output, ignore errors, or assumes success
-- WHY: This is the CORE of anti-recalcitrance - accountability for LLM behavior
CREATE TABLE IF NOT EXISTS llm_violations (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT NOT NULL,
    command_id INTEGER NOT NULL,
    violation_type TEXT NOT NULL,       -- 'output_not_read', 'error_ignored', 'assumed_success', 'no_verbatim_quote'
    evidence TEXT NOT NULL,             -- What the LLM said/did that violated
    severity TEXT NOT NULL,             -- 'critical', 'major', 'minor'
    context TEXT,                       -- Additional context for debugging
    FOREIGN KEY (command_id) REFERENCES commands(id) ON DELETE CASCADE
);

-- Table: watchdog_checks
-- Tracks watchdog script executions and results
CREATE TABLE IF NOT EXISTS watchdog_checks (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp TEXT NOT NULL,
    check_type TEXT NOT NULL,           -- 'terminal-watchdog', 'pre-response-check', 'verify-output-read'
    passed BOOLEAN NOT NULL,            -- 1 = passed, 0 = failed
    details TEXT,                       -- Why it passed/failed
    command_id INTEGER,                 -- Related command (if applicable)
    FOREIGN KEY (command_id) REFERENCES commands(id) ON DELETE SET NULL
);

-- Indexes for performance
CREATE INDEX IF NOT EXISTS idx_commands_timestamp ON commands(timestamp);
CREATE INDEX IF NOT EXISTS idx_violations_severity ON llm_violations(severity);
CREATE INDEX IF NOT EXISTS idx_violations_type ON llm_violations(violation_type);
CREATE INDEX IF NOT EXISTS idx_watchdog_passed ON watchdog_checks(passed);

-- View: Recent violations (for quick debugging)
CREATE VIEW IF NOT EXISTS recent_violations AS
SELECT 
    v.id,
    v.timestamp,
    v.violation_type,
    v.severity,
    c.command,
    c.exit_code,
    v.evidence
FROM llm_violations v
JOIN commands c ON v.command_id = c.id
ORDER BY v.timestamp DESC
LIMIT 50;

-- View: Command success rate
CREATE VIEW IF NOT EXISTS command_stats AS
SELECT 
    COUNT(*) as total_commands,
    SUM(CASE WHEN exit_code = 0 THEN 1 ELSE 0 END) as successful,
    SUM(CASE WHEN exit_code != 0 THEN 1 ELSE 0 END) as failed,
    ROUND(100.0 * SUM(CASE WHEN exit_code = 0 THEN 1 ELSE 0 END) / COUNT(*), 2) as success_rate
FROM commands;

-- View: LLM recalcitrance rate
CREATE VIEW IF NOT EXISTS recalcitrance_stats AS
SELECT 
    COUNT(DISTINCT command_id) as commands_with_violations,
    COUNT(*) as total_violations,
    SUM(CASE WHEN severity = 'critical' THEN 1 ELSE 0 END) as critical_violations,
    SUM(CASE WHEN severity = 'major' THEN 1 ELSE 0 END) as major_violations,
    SUM(CASE WHEN severity = 'minor' THEN 1 ELSE 0 END) as minor_violations
FROM llm_violations;

EOF

echo "✅ Database initialized successfully"
echo ""
echo "📊 Database schema:"
sqlite3 "$DB_FILE" ".schema" | head -20
echo ""
echo "🎯 Usage:"
echo "  - Query commands: sqlite3 $DB_FILE 'SELECT * FROM commands ORDER BY id DESC LIMIT 10'"
echo "  - Query violations: sqlite3 $DB_FILE 'SELECT * FROM recent_violations'"
echo "  - View stats: sqlite3 $DB_FILE 'SELECT * FROM command_stats'"
echo ""
echo "🔥 Anti-Recalcitrance System Ready!"

