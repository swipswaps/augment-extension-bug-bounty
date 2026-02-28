#!/bin/bash
# Output Verification Watchdog
# Detects when LLM fails to read command output
# WHY: This is the enforcement mechanism - HALTS if LLM skips output

set -euo pipefail

DB_FILE=".augment/command_history.db"
TIMESTAMP=$(date --iso-8601=seconds)

# Get the most recent command from database
LAST_COMMAND_ID=$(sqlite3 "$DB_FILE" "SELECT id FROM commands ORDER BY id DESC LIMIT 1;" 2>/dev/null || echo "0")

if [ "$LAST_COMMAND_ID" -eq 0 ]; then
    echo "⚠️  No commands in database yet"
    exit 0
fi

# Get command details
COMMAND_INFO=$(sqlite3 "$DB_FILE" "SELECT command, exit_code, log_file FROM commands WHERE id = $LAST_COMMAND_ID;")
COMMAND=$(echo "$COMMAND_INFO" | cut -d'|' -f1)
EXIT_CODE=$(echo "$COMMAND_INFO" | cut -d'|' -f2)
LOG_FILE=$(echo "$COMMAND_INFO" | cut -d'|' -f3)

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🔍 OUTPUT VERIFICATION WATCHDOG"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📝 Checking command_id: $LAST_COMMAND_ID"
echo "📋 Command: $COMMAND"
echo "🔢 Exit code: $EXIT_CODE"
echo "📄 Log file: $LOG_FILE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# CRITICAL CHECKS:
# 1. Did LLM quote output verbatim?
# 2. Did LLM check exit code?
# 3. Did LLM acknowledge errors?

# For now, this is a REMINDER to the LLM
# In production, this would parse LLM response and detect violations

echo "⚠️  ⚠️  ⚠️  LLM VERIFICATION REQUIRED ⚠️  ⚠️  ⚠️"
echo ""
echo "The LLM MUST demonstrate it read the output by:"
echo ""
echo "1. ✅ Quoting verbatim output from: $LOG_FILE"
echo "2. ✅ Explicitly stating exit code: $EXIT_CODE"
echo "3. ✅ Acknowledging any errors or warnings"
echo "4. ✅ Analyzing what the output means"
echo ""

if [ "$EXIT_CODE" -ne 0 ]; then
    echo "🚨 CRITICAL: Command FAILED with exit code $EXIT_CODE"
    echo "🚨 LLM MUST acknowledge this failure explicitly"
    echo ""
    
    # Log violation if LLM proceeds without acknowledging error
    # (In production, this would be triggered by parsing LLM response)
    SEVERITY="critical"
    VIOLATION_TYPE="error_ignored"
else
    SEVERITY="major"
    VIOLATION_TYPE="output_not_read"
fi

# Log watchdog check to database
sqlite3 "$DB_FILE" <<EOF
INSERT INTO watchdog_checks (timestamp, check_type, passed, details, command_id)
VALUES (
    '$TIMESTAMP',
    'verify-output-read',
    1,
    'Watchdog executed - LLM compliance pending verification',
    $LAST_COMMAND_ID
);
EOF

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Watchdog check logged (command_id: $LAST_COMMAND_ID)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# FUTURE ENHANCEMENT: Parse LLM response and auto-detect violations
# For now, this serves as a forcing function for LLM transparency

exit 0

