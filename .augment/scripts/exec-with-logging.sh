#!/bin/bash
# Command Execution Wrapper with Database Logging
# FORCES complete transparency - ALL output logged and displayed
# WHY: Eliminates LLM recalcitrance by making output unavoidable

set -euo pipefail

DB_FILE=".augment/command_history.db"
LOGDIR=".notes"
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOGFILE="$LOGDIR/cmd-$TIMESTAMP.log"

# Ensure database exists
if [ ! -f "$DB_FILE" ]; then
    echo "❌ Database not initialized. Run: .augment/scripts/init-database.sh"
    exit 1
fi

# Get command from arguments
COMMAND="$*"
CWD=$(pwd)
START_TIME=$(date +%s%3N)  # Milliseconds

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$LOGFILE"
echo "🔥 ANTI-RECALCITRANCE COMMAND EXECUTION" | tee -a "$LOGFILE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$LOGFILE"
echo "📝 Command: $COMMAND" | tee -a "$LOGFILE"
echo "📂 CWD: $CWD" | tee -a "$LOGFILE"
echo "⏰ Timestamp: $(date --iso-8601=seconds)" | tee -a "$LOGFILE"
echo "📄 Log file: $LOGFILE" | tee -a "$LOGFILE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"

# Execute command with tee (FORCES output visibility)
# CRITICAL: tee ensures output is BOTH displayed AND logged
# This eliminates LLM's ability to skip reading output
echo "START: command-output" | tee -a "$LOGFILE"
set +e  # Don't exit on command failure
eval "$COMMAND" 2>&1 | tee -a "$LOGFILE"
EXIT_CODE=${PIPESTATUS[0]}
set -e
echo "END: command-output" | tee -a "$LOGFILE"

END_TIME=$(date +%s%3N)
DURATION=$((END_TIME - START_TIME))

echo "" | tee -a "$LOGFILE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$LOGFILE"
echo "📊 EXECUTION SUMMARY" | tee -a "$LOGFILE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$LOGFILE"
echo "Exit code: $EXIT_CODE" | tee -a "$LOGFILE"
echo "Duration: ${DURATION}ms" | tee -a "$LOGFILE"
echo "Log file: $LOGFILE" | tee -a "$LOGFILE"

if [ "$EXIT_CODE" -eq 0 ]; then
    echo "Status: ✅ SUCCESS" | tee -a "$LOGFILE"
else
    echo "Status: ❌ FAILED (exit code $EXIT_CODE)" | tee -a "$LOGFILE"
fi

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"

# Count output lines
STDOUT_LINES=$(grep -c "^" "$LOGFILE" || echo 0)

# Log to database
# CRITICAL: This creates accountability - every command is tracked
sqlite3 "$DB_FILE" <<EOF
INSERT INTO commands (timestamp, command, cwd, exit_code, duration_ms, log_file, stdout_lines)
VALUES (
    '$(date --iso-8601=seconds)',
    '$(echo "$COMMAND" | sed "s/'/''/g")',
    '$(echo "$CWD" | sed "s/'/''/g")',
    $EXIT_CODE,
    $DURATION,
    '$(echo "$LOGFILE" | sed "s/'/''/g")',
    $STDOUT_LINES
);
EOF

COMMAND_ID=$(sqlite3 "$DB_FILE" "SELECT last_insert_rowid();")

echo "🗄️  Logged to database (command_id: $COMMAND_ID)" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"

# CRITICAL WARNING: LLM MUST READ OUTPUT
echo "⚠️  ⚠️  ⚠️  MANDATORY FOR LLM ⚠️  ⚠️  ⚠️" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"
echo "YOU (LLM) MUST:" | tee -a "$LOGFILE"
echo "1. Quote verbatim output from above" | tee -a "$LOGFILE"
echo "2. Check exit code: $EXIT_CODE" | tee -a "$LOGFILE"
echo "3. Acknowledge any errors" | tee -a "$LOGFILE"
echo "4. Read log file: $LOGFILE" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"
echo "FAILURE TO DO SO = VIOLATION LOGGED TO DATABASE" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"

# Return exit code
exit $EXIT_CODE

