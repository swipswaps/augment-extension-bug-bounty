#!/bin/bash
# Export LLM Violations to JSON for Bug Bounty Submission
# WHY: Provides evidence for augment-extension-bug-bounty repo

set -euo pipefail

DB_FILE=".augment/command_history.db"
OUTPUT_FILE="bug_bounty_report.json"

echo "📊 Exporting LLM violations to $OUTPUT_FILE"

# Check if database exists
if [ ! -f "$DB_FILE" ]; then
    echo "❌ Database not found: $DB_FILE"
    exit 1
fi

# Export violations to JSON
sqlite3 "$DB_FILE" <<'EOF' > "$OUTPUT_FILE"
.mode json
SELECT 
    v.id as violation_id,
    v.timestamp,
    v.violation_type,
    v.severity,
    v.evidence,
    v.context,
    c.id as command_id,
    c.command,
    c.exit_code,
    c.duration_ms,
    c.log_file
FROM llm_violations v
JOIN commands c ON v.command_id = c.id
ORDER BY v.timestamp DESC;
EOF

# Get stats
TOTAL_VIOLATIONS=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM llm_violations;")
CRITICAL_VIOLATIONS=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM llm_violations WHERE severity='critical';")
TOTAL_COMMANDS=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM commands;")

echo "✅ Export complete"
echo ""
echo "📊 STATISTICS:"
echo "  - Total commands: $TOTAL_COMMANDS"
echo "  - Total violations: $TOTAL_VIOLATIONS"
echo "  - Critical violations: $CRITICAL_VIOLATIONS"
echo ""
echo "📄 Report saved to: $OUTPUT_FILE"
echo ""
echo "🚀 NEXT STEPS:"
echo "  1. Review the report: cat $OUTPUT_FILE | jq"
echo "  2. Submit to bug bounty repo: https://github.com/swipswaps/augment-extension-bug-bounty"
echo ""

exit 0

