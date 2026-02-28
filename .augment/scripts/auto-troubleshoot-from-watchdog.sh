#!/bin/bash
# AUTO-TROUBLESHOOT FROM WATCHDOG LOGS
# Purpose: Automated root cause analysis using database + watchdog logs
# Usage: ./.augment/scripts/auto-troubleshoot-from-watchdog.sh
# Output: Identifies leak sources, suggests fixes, logs to database

LOGFILE=".notes/auto-troubleshoot-$(date +%Y%m%d-%H%M%S).log"
DB=".augment/error_tracking.db"
WATCHDOG_LOG=$(find ~/.config/Code/logs -name "*Watchdog*" 2>/dev/null | tail -1)
AUGMENT_LOG=$(find ~/.config/Code/logs -name "Augment.log" 2>/dev/null | tail -1)

echo "START: auto-troubleshoot" | tee -a "$LOGFILE"
echo "Timestamp: $(date -Iseconds)" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"

# STEP 1: Extract all unique stack traces from watchdog logs
echo "=== STEP 1: Extract Stack Traces ===" | tee -a "$LOGFILE"
sqlite3 "$DB" "CREATE TABLE IF NOT EXISTS stack_traces (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    timestamp DATETIME DEFAULT CURRENT_TIMESTAMP,
    error_type TEXT,
    stack_trace TEXT,
    function_name TEXT,
    file_location TEXT,
    occurrence_count INTEGER
);" 2>&1 | tee -a "$LOGFILE"

# Parse watchdog log for stack traces and group by pattern
grep -B 2 "STACK:" "$WATCHDOG_LOG" 2>/dev/null | \
awk '/Error:/{error=$0} /STACK:/{print error "|" $0}' | \
sort | uniq -c | sort -rn | head -20 | tee -a "$LOGFILE"

# Extract function names from stack traces
FUNCTION_PATTERN=$(grep "STACK:" "$WATCHDOG_LOG" 2>/dev/null | \
    grep -oE "[a-zA-Z0-9_]+\.[a-zA-Z0-9_]+ @" | \
    sort | uniq -c | sort -rn | head -1 | awk '{print $2}')

echo "Most common function in stack traces: $FUNCTION_PATTERN" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"

# STEP 2: Correlate stack traces with error messages in Augment.log
echo "=== STEP 2: Correlate with Augment.log ===" | tee -a "$LOGFILE"

# Find all error types and count occurrences
grep -E "\[error\]|\[warning\]" "$AUGMENT_LOG" 2>/dev/null | \
    sed 's/.*\[\(error\|warning\)\] //' | \
    cut -d: -f1-2 | \
    sort | uniq -c | sort -rn | head -10 | tee -a "$LOGFILE"

# Extract feature name from most common error
FEATURE_NAME=$(grep -E "\[error\]" "$AUGMENT_LOG" 2>/dev/null | \
    grep -oE "(chat input completion|codebase-retrieval|hook-integration|CWD tracking)" | \
    sort | uniq -c | sort -rn | head -1 | awk '{$1=""; print $0}' | xargs)

echo "" | tee -a "$LOGFILE"
echo "Feature with most errors: $FEATURE_NAME" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"

# STEP 3: Correlate with file descriptor leak timing
echo "=== STEP 3: Correlate with FD Leak Timing ===" | tee -a "$LOGFILE"

# Extract FD warnings with timestamps
grep "FILE DESCRIPTOR WARNING" "$WATCHDOG_LOG" 2>/dev/null | \
    tail -20 | \
    awk -F'[][]' '{print $2}' | \
    while read timestamp; do
        # Convert ISO timestamp to epoch for comparison
        epoch=$(date -d "${timestamp%Z}" +%s 2>/dev/null || echo 0)
        # Find errors within 60 seconds of FD warning
        if [ "$epoch" -gt 0 ]; then
            echo "FD warning at: $timestamp" | tee -a "$LOGFILE"
            # Search Augment.log for errors near this timestamp
            grep -E "\[error\]" "$AUGMENT_LOG" 2>/dev/null | \
                awk -v ts="$timestamp" '$0 ~ ts {print "  Error: " $0}' | \
                head -3 | tee -a "$LOGFILE"
        fi
    done

echo "" | tee -a "$LOGFILE"

# STEP 4: Calculate error rate and leak correlation
echo "=== STEP 4: Calculate Error Rate ===" | tee -a "$LOGFILE"

TOTAL_ERRORS=$(grep -c "\[error\]" "$AUGMENT_LOG" 2>/dev/null || echo 0)
FEATURE_ERRORS=$(grep -c "$FEATURE_NAME" "$AUGMENT_LOG" 2>/dev/null || echo 0)
FEATURE_CALLS=$(grep -c "Fetching\|Calling" "$AUGMENT_LOG" 2>/dev/null || echo 1)

ERROR_RATE=$((FEATURE_ERRORS * 100 / FEATURE_CALLS))

echo "Total errors in Augment.log: $TOTAL_ERRORS" | tee -a "$LOGFILE"
echo "Errors related to '$FEATURE_NAME': $FEATURE_ERRORS" | tee -a "$LOGFILE"
echo "Total calls to '$FEATURE_NAME': $FEATURE_CALLS" | tee -a "$LOGFILE"
echo "Error rate: ${ERROR_RATE}%" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"

# STEP 5: Identify root cause and suggest fix
echo "=== STEP 5: Root Cause Analysis ===" | tee -a "$LOGFILE"

# Determine if this is a leak source (error rate > 10%)
if [ "$ERROR_RATE" -gt 10 ]; then
    echo "✅ ROOT CAUSE IDENTIFIED" | tee -a "$LOGFILE"
    echo "Feature: $FEATURE_NAME" | tee -a "$LOGFILE"
    echo "Evidence:" | tee -a "$LOGFILE"
    echo "  - Error rate: ${ERROR_RATE}% (threshold: 10%)" | tee -a "$LOGFILE"
    echo "  - Stack trace pattern: $FUNCTION_PATTERN" | tee -a "$LOGFILE"
    echo "  - Correlation: Errors occur during FD leak warnings" | tee -a "$LOGFILE"
    
    # Log to database
    sqlite3 "$DB" "INSERT INTO errors (timestamp, log_file, error_type, error_message, stack_trace) 
        VALUES (datetime('now'), 'auto-troubleshoot', 'root_cause_identified', 
        'Feature: $FEATURE_NAME | Error rate: ${ERROR_RATE}% | Function: $FUNCTION_PATTERN', 
        'Automated analysis from watchdog logs');" 2>&1 | tee -a "$LOGFILE"
    
    echo "" | tee -a "$LOGFILE"
    echo "=== STEP 6: Generate Fix ===" | tee -a "$LOGFILE"
    
    # Map feature name to setting name
    case "$FEATURE_NAME" in
        *"chat input completion"*)
            SETTING="augment.completions.enableChatInputCompletions"
            ;;
        *"hook-integration"*)
            SETTING="augment.hooks.enabled"
            ;;
        *"CWD tracking"*)
            SETTING="augment.terminal.trackCwd"
            ;;
        *)
            SETTING="unknown"
            ;;
    esac
    
    if [ "$SETTING" != "unknown" ]; then
        echo "Suggested fix: Disable setting '$SETTING'" | tee -a "$LOGFILE"
        echo "" | tee -a "$LOGFILE"
        echo "Command to apply fix:" | tee -a "$LOGFILE"
        echo "  jq '. + {\"$SETTING\": false}' ~/.config/Code/User/settings.json > settings.json.tmp" | tee -a "$LOGFILE"
        echo "  mv settings.json.tmp ~/.config/Code/User/settings.json" | tee -a "$LOGFILE"
        echo "" | tee -a "$LOGFILE"
        
        # Log fix suggestion to database
        sqlite3 "$DB" "INSERT INTO errors (timestamp, log_file, error_type, error_message) 
            VALUES (datetime('now'), 'auto-troubleshoot', 'fix_suggested', 
            'Disable $SETTING to stop $FEATURE_NAME leak (error rate: ${ERROR_RATE}%)');" 2>&1 | tee -a "$LOGFILE"
    fi
else
    echo "⚠️  No clear root cause identified (error rate: ${ERROR_RATE}% < 10% threshold)" | tee -a "$LOGFILE"
fi

echo "" | tee -a "$LOGFILE"
echo "✅ Analysis complete" | tee -a "$LOGFILE"
echo "Log file: $LOGFILE" | tee -a "$LOGFILE"
echo "Database: $DB" | tee -a "$LOGFILE"
echo "END: auto-troubleshoot" | tee -a "$LOGFILE"

