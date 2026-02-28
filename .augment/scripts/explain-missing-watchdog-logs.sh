#!/usr/bin/env bash
set -euo pipefail

LOGFILE=".notes/explain-missing-$(date +%Y%m%d-%H%M%S).log"
mkdir -p .notes
exec > >(tee -a "$LOGFILE") 2>&1

echo "START: explain-missing-watchdog-logs"
echo ""

echo "═══════════════════════════════════════════════════════════════════"
echo "🔍 WHY WATCHDOG NOT LOGGING RECENT COMMANDS"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

# Check terminal log files
echo "1. TERMINAL LOG FILES CREATED:"
RECENT_LOGS=$(find .notes -name "terminal-*.log" -mmin -30 2>/dev/null | sort)
if [ -z "$RECENT_LOGS" ]; then
    echo "  ⚠️  NO terminal logs created in last 30 minutes"
    echo "  This means: launch-process NOT creating log files"
else
    echo "$RECENT_LOGS" | while read logfile; do
        TIMESTAMP=$(stat -c %y "$logfile" | cut -d. -f1)
        LINES=$(wc -l < "$logfile")
        echo "  ✅ $(basename "$logfile") - $LINES lines - $TIMESTAMP"
    done
fi
echo ""

# Check watchdog log
echo "2. WATCHDOG LOG STATUS:"
WATCHDOG_LOG=$(find ~/.config/Code/logs -path "*/exthost/output_logging_*/1-Watchdog Log.log" -type f 2>/dev/null | sort | tail -1)
if [ -z "$WATCHDOG_LOG" ]; then
    echo "  ⚠️  NO WATCHDOG LOG FOUND"
else
    echo "  Log: $WATCHDOG_LOG"
    LAST_TERMINAL_OUTPUT=$(grep "TERMINAL OUTPUT" "$WATCHDOG_LOG" 2>/dev/null | tail -1)
    LAST_HEARTBEAT=$(grep "HEARTBEAT" "$WATCHDOG_LOG" 2>/dev/null | tail -1)
    
    echo "  Last TERMINAL OUTPUT: ${LAST_TERMINAL_OUTPUT:-NONE}"
    echo "  Last HEARTBEAT: ${LAST_HEARTBEAT:-NONE}"
fi
echo ""

# Root cause analysis
echo "═══════════════════════════════════════════════════════════════════"
echo "🚨 ROOT CAUSE ANALYSIS"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

echo "PROBLEM: Commands run but NOT logged in watchdog"
echo ""

echo "POSSIBLE CAUSES:"
echo ""

echo "1. TERMINAL LOGS NOT CREATED"
echo "   - launch-process NOT using tee to .notes/terminal-*.log"
echo "   - Scripts missing: exec > >(tee -a \"\$LOGFILE\") 2>&1"
echo "   - Watchdog can't log what doesn't exist"
echo ""

echo "2. WATCHDOG NOT MONITORING .notes/ DIRECTORY"
echo "   - Watchdog may monitor different directory"
echo "   - File watcher not detecting new files"
echo "   - Permission issues preventing read"
echo ""

echo "3. TERMINAL COUNT MISMATCH"
WATCHDOG_TERMINAL_COUNT=$(grep "HEARTBEAT" "$WATCHDOG_LOG" 2>/dev/null | tail -1 | grep -oP 'terminals=\K\d+' || echo "0")
ACTUAL_TERMINAL_COUNT=$(ps aux | grep -E 'gnome-terminal|xterm|konsole|code.*pty' | grep -v grep | wc -l)
echo "   - Watchdog reports: $WATCHDOG_TERMINAL_COUNT terminals"
echo "   - Actual terminals: $ACTUAL_TERMINAL_COUNT"
if [ "$WATCHDOG_TERMINAL_COUNT" -ne "$ACTUAL_TERMINAL_COUNT" ]; then
    echo "   ⚠️  MISMATCH - Watchdog not tracking all terminals"
fi
echo ""

echo "4. COMMANDS RUN WITHOUT TEE"
echo "   - Recent commands may not use tee"
echo "   - Output goes to terminal but NOT to log file"
echo "   - Watchdog only sees log files, not terminal output"
echo ""

# Check recent command patterns
echo "═══════════════════════════════════════════════════════════════════"
echo "📊 RECENT COMMAND PATTERNS"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

echo "Checking if recent commands used tee:"
RECENT_TERMINAL_LOGS=$(find .notes -name "terminal-*.log" -mmin -60 2>/dev/null | sort -r | head -5)
if [ -z "$RECENT_TERMINAL_LOGS" ]; then
    echo "  ⚠️  NO terminal logs in last 60 minutes"
    echo "  DIAGNOSIS: Commands NOT using tee to create log files"
else
    echo "$RECENT_TERMINAL_LOGS" | while read logfile; do
        TIMESTAMP=$(stat -c %y "$logfile" | cut -d. -f1)
        FIRST_LINE=$(head -1 "$logfile" 2>/dev/null)
        echo "  $(basename "$logfile") - $TIMESTAMP"
        echo "    First line: $FIRST_LINE"
    done
fi
echo ""

# Solution
echo "═══════════════════════════════════════════════════════════════════"
echo "🔧 SOLUTION"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

echo "TO FIX MISSING WATCHDOG LOGS:"
echo ""

echo "1. ALL COMMANDS MUST USE TEE:"
echo "   LOGFILE=\".notes/terminal-\$(date +%Y%m%d-%H%M%S).log\""
echo "   exec > >(tee -a \"\$LOGFILE\") 2>&1"
echo ""

echo "2. VERIFY LOG FILE CREATED:"
echo "   ls -lh .notes/terminal-*.log | tail -5"
echo ""

echo "3. VERIFY WATCHDOG SEES IT:"
echo "   tail -20 ~/.config/Code/logs/*/exthost/output_logging_*/1-Watchdog\\ Log.log"
echo ""

echo "4. TEST WITH THIS COMMAND:"
cat << 'EOF'
   LOGFILE=".notes/terminal-$(date +%Y%m%d-%H%M%S).log"
   exec > >(tee -a "$LOGFILE") 2>&1
   echo "START: test-watchdog-logging"
   echo "This should appear in watchdog log"
   ps aux | grep code | head -5
   echo "END: test-watchdog-logging"
EOF
echo ""

# Live test
echo "═══════════════════════════════════════════════════════════════════"
echo "🧪 LIVE TEST"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

TEST_LOG=".notes/terminal-$(date +%Y%m%d-%H%M%S).log"
echo "Creating test log: $TEST_LOG"
echo "START: watchdog-test" | tee -a "$TEST_LOG"
echo "Current time: $(date)" | tee -a "$TEST_LOG"
echo "VS Code memory: $(ps aux | grep -E '/usr/share/code|/proc/self/ex' | grep -v grep | awk '{sum+=$6} END {print int(sum/1024)}')MB" | tee -a "$TEST_LOG"
echo "END: watchdog-test" | tee -a "$TEST_LOG"

echo ""
echo "Test log created: $TEST_LOG"
echo "Wait 60 seconds and check watchdog log for TERMINAL OUTPUT entry"
echo ""

echo "END: explain-missing-watchdog-logs"

