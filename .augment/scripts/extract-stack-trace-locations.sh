#!/bin/bash
# WHAT: Extract file:line:offset from stack traces in database and create VS Code diagnostic queue
# WHY: LLM needs to see exact line numbers flagged in editor to comply with rules
# HOW: Query database → parse stack traces → extract locations → write to diagnostics queue

LOGFILE=".notes/terminal-$(date +%Y%m%d-%H%M%S).log"
DB_PATH=".augment/error_tracking.db"
DIAGNOSTICS_QUEUE=".notes/vscode-diagnostics-queue.txt"

# WHAT: Clear old diagnostics queue
# WHY: Start fresh with current errors only
# HOW: Truncate file
> "$DIAGNOSTICS_QUEUE"

echo "START: Extract stack trace locations" | tee -a "$LOGFILE"
echo "=== WHAT: Parse stack traces from database ===" | tee -a "$LOGFILE"
echo "=== WHY: Need exact file:line:offset for VS Code diagnostics ===" | tee -a "$LOGFILE"
echo "=== HOW: Query errors with stack traces, parse with grep/sed ===" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"

# WHAT: Query database for errors with stack traces
# WHY: Stack traces contain file:line:offset information
# HOW: SELECT error_type, error_message, stack_trace WHERE stack_trace IS NOT NULL
sqlite3 "$DB_PATH" "SELECT error_type || '|' || error_message || '|' || stack_trace FROM errors WHERE stack_trace IS NOT NULL AND stack_trace != '' LIMIT 100;" | while IFS='|' read -r error_type error_message stack_trace; do
    
    echo "Processing error: $error_type" | tee -a "$LOGFILE"
    
    # WHAT: Parse stack trace to extract file:line:offset
    # WHY: VS Code diagnostics need exact location
    # HOW: Look for pattern "at function (file:line:offset)" or "at file:line:offset"
    # EXAMPLE: "at eH.callApi (/home/owner/.vscode/extensions/augment.augment-0.754.3/out/extension.js:252:1928)"
    
    echo "$stack_trace" | grep -oE '\([^)]+:[0-9]+:[0-9]+\)' | while read -r location_with_parens; do
        # WHAT: Remove parentheses from location
        # WHY: Need clean file:line:offset format
        # HOW: sed to strip ( and )
        location=$(echo "$location_with_parens" | sed 's/[()]//g')
        
        # WHAT: Extract file path, line number, offset
        # WHY: VS Code diagnostics API needs these separately
        # HOW: Use cut with : delimiter
        file_path=$(echo "$location" | cut -d: -f1)
        line_num=$(echo "$location" | cut -d: -f2)
        offset=$(echo "$location" | cut -d: -f3)
        
        # WHAT: Extract function name from stack trace line
        # WHY: Include in diagnostic message for context
        # HOW: grep for "at function" pattern before location
        function_name=$(echo "$stack_trace" | grep -B1 "$location" | grep -oE 'at [^ ]+' | head -1 | sed 's/at //')
        
        if [ -n "$file_path" ] && [ -n "$line_num" ]; then
            # WHAT: Write to diagnostics queue
            # WHY: Watchdog extension will read this and create VS Code diagnostics
            # HOW: Format: file:line:offset|error_type|function_name|error_message
            echo "$file_path:$line_num:$offset|$error_type|$function_name|$error_message" >> "$DIAGNOSTICS_QUEUE"
            echo "  → $function_name @ $file_path:$line_num:$offset" | tee -a "$LOGFILE"
        fi
    done
done

echo "" | tee -a "$LOGFILE"
echo "=== DIAGNOSTICS QUEUE CREATED ===" | tee -a "$LOGFILE"
QUEUE_COUNT=$(wc -l < "$DIAGNOSTICS_QUEUE")
echo "Total locations flagged: $QUEUE_COUNT" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"

if [ "$QUEUE_COUNT" -gt 0 ]; then
    echo "Sample diagnostics (first 10):" | tee -a "$LOGFILE"
    head -10 "$DIAGNOSTICS_QUEUE" | tee -a "$LOGFILE"
fi

echo "" | tee -a "$LOGFILE"
echo "END: Extract stack trace locations" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"
echo "Log file: $LOGFILE" | tee -a "$LOGFILE"

# WHAT: Add mandatory delay for output buffer flush
# WHY: Tool reads output split second before buffer fully written
# HOW: sleep 0.5 seconds
sleep 0.5

