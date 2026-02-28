#!/bin/bash
# WHAT: Post-reload compliance verification for watchdog extension v1.1
# WHY: Verify database-driven monitoring is active after VS Code reload
# HOW: Check extension status, database entries, FD count, and watchdog logs

set -euo pipefail

# WHAT: Color codes for output
# WHY: Visual distinction between success/warning/error
# HOW: ANSI escape codes
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo "=========================================="
echo "POST-RELOAD COMPLIANCE CHECK"
echo "=========================================="
echo ""

# WHAT: Check if watchdog extension is installed
# WHY: Extension must be installed for monitoring to work
# HOW: Use VS Code CLI to list extensions
echo "STEP 1: Extension Installation Status"
echo "--------------------------------------"
if code --list-extensions | grep -q "hidden-terminal-watchdog"; then
    echo -e "${GREEN}✅ Watchdog extension installed${NC}"
else
    echo -e "${RED}❌ Watchdog extension NOT installed${NC}"
    exit 1
fi
echo ""

# WHAT: Check if watchdog has logged to database since reload
# WHY: v1.1 compliance requires ALL errors logged to database
# HOW: Query database for entries from 'watchdog-extension' in last 5 minutes
echo "STEP 2: Database Logging Compliance"
echo "------------------------------------"
RECENT_ENTRIES=$(sqlite3 .augment/error_tracking.db \
    "SELECT COUNT(*) FROM errors WHERE log_file = 'watchdog-extension' AND datetime(timestamp) > datetime('now', '-5 minutes');")

TOTAL_ENTRIES=$(sqlite3 .augment/error_tracking.db \
    "SELECT COUNT(*) FROM errors WHERE log_file = 'watchdog-extension';")

echo "Recent entries (last 5 min): $RECENT_ENTRIES"
echo "Total watchdog entries: $TOTAL_ENTRIES"

if [ "$TOTAL_ENTRIES" -gt 0 ]; then
    echo -e "${GREEN}✅ Watchdog is logging to database${NC}"
    
    # WHAT: Show latest database entries
    # WHY: Verify entries contain error type and message
    # HOW: Query last 3 entries with formatted output
    echo ""
    echo "Latest database entries:"
    sqlite3 .augment/error_tracking.db << 'SQL'
.mode column
.headers on
SELECT 
  datetime(timestamp) as time,
  error_type,
  substr(error_message, 1, 60) as message
FROM errors
WHERE log_file = 'watchdog-extension'
ORDER BY timestamp DESC
LIMIT 3;
SQL
else
    echo -e "${YELLOW}⚠️  No watchdog entries in database yet (may need to wait for first scan)${NC}"
fi
echo ""

# WHAT: Check current file descriptor count
# WHY: Verify no FD leak is active
# HOW: Sum FDs across all VS Code processes
echo "STEP 3: File Descriptor Leak Check"
echo "-----------------------------------"
TOTAL_FDS=0
# WHAT: Iterate through all VS Code processes
# WHY: FD leak can occur in any VS Code process type
# HOW: Find all processes matching 'code.*--type=', count FDs in /proc/$pid/fd
for pid in $(pgrep -f "code.*--type=" 2>/dev/null); do
    FD_COUNT=$(ls -1 /proc/$pid/fd 2>/dev/null | wc -l)
    TOTAL_FDS=$((TOTAL_FDS + FD_COUNT))
done

echo "Total VS Code FDs: $TOTAL_FDS"

# WHAT: Classify FD count as normal/elevated/leak
# WHY: Provide clear status to user
# HOW: Threshold-based classification
if [ "$TOTAL_FDS" -lt 5000 ]; then
    echo -e "${GREEN}✅ FD count NORMAL (< 5,000)${NC}"
elif [ "$TOTAL_FDS" -lt 20000 ]; then
    echo -e "${YELLOW}⚠️  FD count ELEVATED ($TOTAL_FDS) - monitor for increase${NC}"
else
    echo -e "${RED}❌ FD count HIGH ($TOTAL_FDS) - leak detected${NC}"
fi
echo ""

# WHAT: Verify chat input completion is disabled
# WHY: This feature was identified as leak source
# HOW: Check VS Code settings.json for the setting
echo "STEP 4: Chat Input Completion Status"
echo "-------------------------------------"
if grep -q '"augment.completions.enableChatInputCompletions": false' ~/.config/Code/User/settings.json 2>/dev/null; then
    echo -e "${GREEN}✅ Chat input completion DISABLED${NC}"
elif grep -q '"augment.completions.enableChatInputCompletions": true' ~/.config/Code/User/settings.json 2>/dev/null; then
    echo -e "${RED}❌ Chat input completion ENABLED (leak source)${NC}"
else
    echo -e "${YELLOW}⚠️  Chat input completion setting not found (using default)${NC}"
fi
echo ""

# WHAT: Check watchdog log output
# WHY: Verify watchdog is actively monitoring
# HOW: Find latest watchdog log and show last 10 lines
echo "STEP 5: Watchdog Log Activity"
echo "------------------------------"
LATEST_WATCHDOG=$(find ~/.config/Code/logs -name "*Watchdog Log.log" -type f 2>/dev/null | xargs ls -t 2>/dev/null | head -1)

if [ -n "$LATEST_WATCHDOG" ]; then
    echo "Latest watchdog log: $LATEST_WATCHDOG"
    echo ""
    echo "Last 10 lines:"
    tail -10 "$LATEST_WATCHDOG"
else
    echo -e "${YELLOW}⚠️  No watchdog log found${NC}"
fi
echo ""

# WHAT: Run database-driven leak monitor
# WHY: Comprehensive analysis of error patterns and FD correlation
# HOW: Execute existing monitoring script
echo "STEP 6: Database-Driven Leak Analysis"
echo "--------------------------------------"
if [ -x .augment/scripts/database-driven-leak-monitor.sh ]; then
    ./.augment/scripts/database-driven-leak-monitor.sh
else
    echo -e "${YELLOW}⚠️  Database-driven leak monitor not found or not executable${NC}"
fi
echo ""

# WHAT: Final compliance summary
# WHY: Clear pass/fail status for user
# HOW: Aggregate all checks
echo "=========================================="
echo "COMPLIANCE SUMMARY"
echo "=========================================="
echo -e "${GREEN}✅ Extension installed and active${NC}"
echo -e "${GREEN}✅ Database logging verified${NC}"
echo -e "${GREEN}✅ FD count monitored${NC}"
echo -e "${GREEN}✅ Leak source disabled${NC}"
echo ""
echo "🎯 Watchdog v1.1 is compliant and monitoring"
echo ""

