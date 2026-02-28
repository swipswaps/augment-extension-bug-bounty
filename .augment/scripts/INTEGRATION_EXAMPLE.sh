#!/bin/bash
# INTEGRATION EXAMPLE - How to Use Anti-Recalcitrance System
# WHY: Shows EXACTLY how to integrate into any repo
# WHAT: Working example that can be copied and adapted

set -euo pipefail

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "🎯 ANTI-RECALCITRANCE SYSTEM - INTEGRATION EXAMPLE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "This script demonstrates the COMPLETE workflow:"
echo "1. Initialize database"
echo "2. Execute command with logging"
echo "3. Verify LLM read output"
echo "4. Query database"
echo "5. Export violations"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ============================================================================
# STEP 1: Initialize Database (if not exists)
# ============================================================================

echo "📊 STEP 1: Initialize Database"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ ! -f .augment/command_history.db ]; then
    echo "Database not found, initializing..."
    .augment/scripts/init-database.sh
else
    echo "✅ Database already exists: .augment/command_history.db"
fi

echo ""

# ============================================================================
# STEP 2: Execute Command with Logging
# ============================================================================

echo "🔥 STEP 2: Execute Command with Logging"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "Example: Check system load and memory"
echo ""

# CRITICAL: Use exec-with-logging.sh for ALL commands
# WHY: Forces tee output (visible + logged) and database tracking
.augment/scripts/exec-with-logging.sh "uptime && free -h"

echo ""

# ============================================================================
# STEP 3: Verify LLM Read Output
# ============================================================================

echo "🔍 STEP 3: Verify LLM Read Output"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# CRITICAL: Run watchdog after EVERY command
# WHY: Enforces LLM compliance (quote output, check exit code)
.augment/scripts/verify-output-read.sh

echo ""

# ============================================================================
# STEP 4: Query Database
# ============================================================================

echo "📊 STEP 4: Query Database"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

echo "Recent commands:"
sqlite3 .augment/command_history.db "SELECT id, timestamp, command, exit_code, duration_ms FROM commands ORDER BY id DESC LIMIT 5;"

echo ""
echo "Command statistics:"
sqlite3 .augment/command_history.db "SELECT * FROM command_stats;"

echo ""
echo "Recalcitrance statistics:"
sqlite3 .augment/command_history.db "SELECT * FROM recalcitrance_stats;"

echo ""

# ============================================================================
# STEP 5: Export Violations (if any)
# ============================================================================

echo "📤 STEP 5: Export Violations"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

VIOLATION_COUNT=$(sqlite3 .augment/command_history.db "SELECT COUNT(*) FROM llm_violations;")

if [ "$VIOLATION_COUNT" -gt 0 ]; then
    echo "⚠️  Found $VIOLATION_COUNT violations, exporting..."
    .augment/scripts/export-violations.sh
else
    echo "✅ No violations found (LLM is compliant!)"
fi

echo ""

# ============================================================================
# SUMMARY
# ============================================================================

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ INTEGRATION EXAMPLE COMPLETE"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "🎯 KEY TAKEAWAYS:"
echo ""
echo "1. ✅ Use exec-with-logging.sh for ALL commands"
echo "   - Forces tee output (visible + logged)"
echo "   - Logs to database (accountability)"
echo "   - Captures exit codes (no assumptions)"
echo ""
echo "2. ✅ Run verify-output-read.sh after EVERY command"
echo "   - Enforces LLM compliance"
echo "   - Detects violations"
echo "   - Logs to database"
echo ""
echo "3. ✅ Query database regularly"
echo "   - Check command history"
echo "   - Monitor success rate"
echo "   - Track violations"
echo ""
echo "4. ✅ Export violations to bug bounty repo"
echo "   - Provides evidence"
echo "   - Identifies patterns"
echo "   - Drives improvements"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📚 DOCUMENTATION:"
echo "  - System design: .notes/ANTI_RECALCITRANCE_SYSTEM_DESIGN.md"
echo "  - Why it works: .notes/WHY_REQUEST_COMPLIANCE_WORKS.md"
echo "  - Bug bounty: .notes/BUG_BOUNTY_INTEGRATION.md"
echo "  - Complete guide: .notes/ANTI_RECALCITRANCE_COMPLETE.md"
echo ""
echo "🚀 NEXT STEPS:"
echo "  1. Copy scripts to hidden-terminal-watchdog repo"
echo "  2. Create bug bounty repo structure"
echo "  3. Integrate into all workflows"
echo "  4. Monitor violations and submit to bug bounty"
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

exit 0

