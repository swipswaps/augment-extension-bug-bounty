#!/bin/bash
# Pre-Response Check - MUST run before EVERY assistant response
# Enforces RULE 9 compliance by checking if assistant has read terminal output

set -euo pipefail

LOGFILE=".notes/pre-response-$(date +%Y%m%d-%H%M%S).log"

echo "START: pre-response-check" | tee -a "$LOGFILE"

# Check 1: Are there any recent terminal logs?
RECENT_LOGS=$(ls -t .notes/terminal-*.log 2>/dev/null | head -5)

if [ -z "$RECENT_LOGS" ]; then
    echo "⚠️  No recent terminal logs found" | tee -a "$LOGFILE"
    echo "   This is OK if no commands were run" | tee -a "$LOGFILE"
else
    echo "📋 Recent terminal logs:" | tee -a "$LOGFILE"
    ls -lht .notes/terminal-*.log 2>/dev/null | head -5 | tee -a "$LOGFILE"
    echo "" | tee -a "$LOGFILE"
    
    # Check the most recent log
    MOST_RECENT=$(ls -t .notes/terminal-*.log 2>/dev/null | head -1)
    echo "🔍 Checking most recent log: $MOST_RECENT" | tee -a "$LOGFILE"
    
    # Check for START/END markers
    HAS_START=$(grep -c "^START:" "$MOST_RECENT" || echo "0")
    HAS_END=$(grep -c "^END:" "$MOST_RECENT" || echo "0")
    
    echo "   START markers: $HAS_START" | tee -a "$LOGFILE"
    echo "   END markers: $HAS_END" | tee -a "$LOGFILE"
    
    if [ "$HAS_START" -gt 0 ] && [ "$HAS_END" -eq 0 ]; then
        echo "" | tee -a "$LOGFILE"
        echo "❌ CRITICAL VIOLATION: Command started but never completed" | tee -a "$LOGFILE"
        echo "   Log file: $MOST_RECENT" | tee -a "$LOGFILE"
        echo "" | tee -a "$LOGFILE"
        echo "HALT: DO NOT RESPOND UNTIL:" | tee -a "$LOGFILE"
        echo "1. You read the log file: cat $MOST_RECENT" | tee -a "$LOGFILE"
        echo "2. You check if command is still running" | tee -a "$LOGFILE"
        echo "3. You wait for END marker or diagnose failure" | tee -a "$LOGFILE"
        echo "4. You quote verbatim output from the log" | tee -a "$LOGFILE"
        echo "" | tee -a "$LOGFILE"
        cat "$MOST_RECENT" | tee -a "$LOGFILE"
        echo "" | tee -a "$LOGFILE"
        echo "END: pre-response-check" | tee -a "$LOGFILE"
        echo "LOG: $LOGFILE"
        exit 1
    fi
    
    if [ "$HAS_START" -gt 0 ] && [ "$HAS_END" -gt 0 ]; then
        echo "✅ Most recent command completed successfully" | tee -a "$LOGFILE"
    fi
fi

# Check 2: Are there any watchdog logs?
WATCHDOG_LOGS=$(ls -t .notes/watchdog-*.log 2>/dev/null | head -1)

if [ -n "$WATCHDOG_LOGS" ]; then
    echo "" | tee -a "$LOGFILE"
    echo "📋 Most recent watchdog log: $WATCHDOG_LOGS" | tee -a "$LOGFILE"
    
    if grep -q "VIOLATION" "$WATCHDOG_LOGS"; then
        echo "❌ WATCHDOG DETECTED VIOLATION" | tee -a "$LOGFILE"
        echo "   Review watchdog log before responding" | tee -a "$LOGFILE"
        cat "$WATCHDOG_LOGS" | tee -a "$LOGFILE"
    fi
fi

echo "" | tee -a "$LOGFILE"
echo "✅ PRE-RESPONSE CHECK PASSED" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"
echo "REMINDER BEFORE RESPONDING:" | tee -a "$LOGFILE"
echo "1. Have you quoted verbatim output from ALL recent commands?" | tee -a "$LOGFILE"
echo "2. Have you read ALL log files created since last response?" | tee -a "$LOGFILE"
echo "3. Have you analyzed what the output means?" | tee -a "$LOGFILE"
echo "4. Are you about to say 'OK' without evidence? STOP!" | tee -a "$LOGFILE"

echo "END: pre-response-check" | tee -a "$LOGFILE"
echo "LOG: $LOGFILE"

exit 0

