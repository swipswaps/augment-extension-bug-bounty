#!/bin/bash
# Terminal Watchdog - Prevents RULE 9 violations by verifying output reading
# This script MUST be run after EVERY launch-process call before assistant responds
# DETECTS "Cancelled by user" and forces reading of <output> section

set -euo pipefail

LOGFILE=".notes/watchdog-$(date +%Y%m%d-%H%M%S).log"

echo "START: terminal-watchdog" | tee -a "$LOGFILE"

# CRITICAL: Check if last tool call had "Cancelled by user" error
# This is a FALSE ERROR - output is still present and MUST be read
echo "" | tee -a "$LOGFILE"
echo "🔍 CHECKING FOR 'Cancelled by user' FALSE ERROR..." | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"
echo "⚠️  IF YOU SEE <error>Cancelled by user.</error> IN TOOL RESULT:" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"
echo "RULE 9 TIMEOUT PROTOCOL (MANDATORY):" | tee -a "$LOGFILE"
echo "- STEP 0 (FIRST): Ignore <error> section completely" | tee -a "$LOGFILE"
echo "- STEP 1: Look ONLY at <output> section in tool result" | tee -a "$LOGFILE"
echo "- STEP 2: Quote verbatim output BEFORE any other response" | tee -a "$LOGFILE"
echo "- STEP 3: If <output> is empty → State explicitly 'Tool result <output> section is empty'" | tee -a "$LOGFILE"
echo "- STEP 4: NEVER call read-process or list-processes" | tee -a "$LOGFILE"
echo "- STEP 5: CONTINUE to next step regardless of timeout" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"
echo "⚡ MANDATORY RESPONSE FORMAT AFTER TIMEOUT:" | tee -a "$LOGFILE"
echo "Tool result received with <error>: Cancelled by user." | tee -a "$LOGFILE"
echo "Tool result <output> section contains:" | tee -a "$LOGFILE"
echo "\`\`\`" | tee -a "$LOGFILE"
echo "[verbatim output here]" | tee -a "$LOGFILE"
echo "\`\`\`" | tee -a "$LOGFILE"
echo "[Then proceed with analysis]" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"
echo "❌ FORBIDDEN PATTERN:" | tee -a "$LOGFILE"
echo "❌ WRONG: 'Tool call was cancelled due to timeout' → [moves on without checking <output>]" | tee -a "$LOGFILE"
echo "✅ CORRECT: 'Tool call was cancelled due to timeout. Checking <output> section: [quotes output]'" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"

# Get the most recent terminal log file
RECENT_LOG=$(ls -t .notes/terminal-*.log 2>/dev/null | head -1)

if [ -z "$RECENT_LOG" ]; then
    echo "❌ VIOLATION: No terminal log files found" | tee -a "$LOGFILE"
    echo "HALT: Cannot proceed without terminal logs" | tee -a "$LOGFILE"
    exit 1
fi

echo "📋 Checking recent log: $RECENT_LOG" | tee -a "$LOGFILE"

# Check if log file has START marker
if ! grep -q "^START:" "$RECENT_LOG"; then
    echo "❌ VIOLATION: Log file missing START marker" | tee -a "$LOGFILE"
    exit 1
fi

# Check if log file has END marker
if ! grep -q "^END:" "$RECENT_LOG"; then
    echo "❌ VIOLATION: Log file missing END marker" | tee -a "$LOGFILE"
    echo "COMMAND DID NOT COMPLETE - DO NOT SAY 'OK'" | tee -a "$LOGFILE"
    echo "" | tee -a "$LOGFILE"
    echo "REQUIRED ACTION:" | tee -a "$LOGFILE"
    echo "1. Read the log file: cat $RECENT_LOG" | tee -a "$LOGFILE"
    echo "2. Check if command is still running" | tee -a "$LOGFILE"
    echo "3. Wait for END marker or diagnose failure" | tee -a "$LOGFILE"
    echo "4. NEVER say 'OK' without END marker" | tee -a "$LOGFILE"
    exit 1
fi

# Extract START and END markers
START_LINE=$(grep "^START:" "$RECENT_LOG" | head -1)
END_LINE=$(grep "^END:" "$RECENT_LOG" | tail -1)

echo "✅ START marker found: $START_LINE" | tee -a "$LOGFILE"
echo "✅ END marker found: $END_LINE" | tee -a "$LOGFILE"

# Check if START and END markers match
START_ACTION=$(echo "$START_LINE" | sed 's/START: //')
END_ACTION=$(echo "$END_LINE" | sed 's/END: //')

if [ "$START_ACTION" != "$END_ACTION" ]; then
    echo "⚠️  WARNING: START/END markers don't match" | tee -a "$LOGFILE"
    echo "   START: $START_ACTION" | tee -a "$LOGFILE"
    echo "   END: $END_ACTION" | tee -a "$LOGFILE"
fi

# Count lines in log file
LINE_COUNT=$(wc -l < "$RECENT_LOG")
echo "📊 Log file has $LINE_COUNT lines" | tee -a "$LOGFILE"

# Show log file content
echo "" | tee -a "$LOGFILE"
echo "📄 FULL LOG CONTENT:" | tee -a "$LOGFILE"
echo "===================" | tee -a "$LOGFILE"
cat "$RECENT_LOG" | tee -a "$LOGFILE"
echo "===================" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"

# Check for common error patterns
if grep -qi "error\|failed\|cannot\|permission denied" "$RECENT_LOG"; then
    echo "⚠️  WARNING: Log contains error keywords" | tee -a "$LOGFILE"
    echo "   Review errors before proceeding" | tee -a "$LOGFILE"
fi

# Verify assistant has quoted the output
echo "" | tee -a "$LOGFILE"
echo "✅ WATCHDOG PASSED - Command completed with START/END markers" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"
echo "MANDATORY NEXT STEPS FOR ASSISTANT:" | tee -a "$LOGFILE"
echo "1. Quote verbatim output from log file above" | tee -a "$LOGFILE"
echo "2. Analyze what the output means" | tee -a "$LOGFILE"
echo "3. Proceed with next action based on evidence" | tee -a "$LOGFILE"
echo "4. NEVER say 'OK' without quoting output" | tee -a "$LOGFILE"

echo "END: terminal-watchdog" | tee -a "$LOGFILE"
echo "LOG: $LOGFILE"

exit 0

