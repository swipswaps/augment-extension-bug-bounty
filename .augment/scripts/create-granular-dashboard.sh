#!/usr/bin/env bash
set -euo pipefail

# USER REQUEST: "visualization with granularity of error, event, system and application relevant messages was expected"
# PURPOSE: Create interactive dashboard showing INDIVIDUAL error messages, events, and logs (not aggregated)
# VISUALIZATION: Timeline with FULL verbatim error messages, clickable to see details
# TROUBLESHOOTING VALUE: See exact error "Request cancelled" at 13:09:07.435, not just "20 errors"

LOGFILE=".notes/create-granular-dashboard-$(date +%Y%m%d-%H%M%S).log"
mkdir -p .notes
exec > >(tee -a "$LOGFILE") 2>&1

echo "START: create-granular-dashboard"
echo ""

VIZ_DIR=".notes/visualizations"

# STEP 1: Extract application logs from watchdog
echo "═══════════════════════════════════════════════════════════════════"
echo "STEP 1: Extract application logs with FULL error messages"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

WATCHDOG_LOG=$(find ~/.config/Code/logs -path "*/exthost/output_logging_*/1-Watchdog Log.log" -type f 2>/dev/null | sort | tail -1)

if [ -f "$WATCHDOG_LOG" ]; then
    echo "Parsing watchdog log: $WATCHDOG_LOG"
    
    # EXTRACT: All log entries with FULL error messages AND stack traces
    # USER REQUEST: "try to show what line and subroutine of what file or scripts called or caused the error"
    # SOLUTION: Extract multi-line error messages including stack traces with file paths and line numbers
    # BENEFIT: LLM can see exact file (extension.js:252:1928) and function (eH.callApi) that caused error

    # STEP 1: Extract error messages with context (include next 10 lines for stack traces)
    grep -B 0 -A 10 -E 'Augment\.log:|error|ERROR|failed|FAILED|warn|WARNING|STACK:' "$WATCHDOG_LOG" | \
    grep -v 'count=' > "$VIZ_DIR/temp-logs-with-context.txt"

    # STEP 2: Parse multi-line error messages with stack traces
    python3 << PYTHON_EOF > "$VIZ_DIR/application-logs.json"
import re
import json
import sys

# Read temp file
with open("$VIZ_DIR/temp-logs-with-context.txt", 'r') as f:
    lines = f.readlines()

events = []
current_event = None

for line in lines:
    line = line.strip()
    if not line or line == '--':
        continue

    # Match timestamp pattern: [2026-02-18T13:01:09.698Z]
    timestamp_match = re.match(r'\[(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z)\]', line)

    if timestamp_match:
        # Extract content after timestamp
        rest = line[timestamp_match.end():].strip()

        # Check if this is a STACK: line (continuation of previous event)
        if current_event and (rest.startswith('STACK:') or rest.startswith('at ')):
            # This is a stack trace line, not a new event
            pass  # Will be handled below
        else:
            # Save previous event
            if current_event:
                events.append(current_event)

            # Start new event
            timestamp = timestamp_match.group(1)

            # Extract source (Augment.log, TypeScript.log, etc)
            source_match = re.match(r'([A-Za-z0-9_-]+\.log):\s*(.*)', rest)
            if source_match:
                source = source_match.group(1)
                message = source_match.group(2)
            else:
                source = "watchdog"
                message = rest

            # Determine severity
            severity = "INFO"
            if re.search(r'error|ERROR|failed|FAILED', message, re.IGNORECASE):
                severity = "ERROR"
            elif re.search(r'warn|WARNING', message, re.IGNORECASE):
                severity = "WARNING"

            current_event = {
                "timestamp": timestamp,
                "source": source,
                "severity": severity,
                "message": message,
                "stack_trace": [],
                "files": []
            }

    # Check for stack trace lines (after timestamp extraction)
    if timestamp_match:
        rest = line[timestamp_match.end():].strip()
    else:
        rest = line

    if current_event and (rest.startswith('STACK:') or rest.startswith('at ')):
        # Stack trace line from watchdog: "STACK: eH.callApi @ augment.vscode-augment-0.779.0/extension.js:252:1928"
        # OR raw stack trace: "at eH.callApi (/home/owner/.vscode/extensions/augment.vscode-augment-0.779.0/out/extension.js:252:1928)"
        current_event["stack_trace"].append(rest)

        # Extract file path and line number from watchdog format: "STACK: funcName @ file.js:line:col"
        watchdog_match = re.match(r'STACK:\s+([^\s@]+)\s+@\s+([^:]+):(\d+):(\d+)', rest)
        if watchdog_match:
            func_name = watchdog_match.group(1)
            file_path = watchdog_match.group(2)
            line_num = watchdog_match.group(3)
            col_num = watchdog_match.group(4)

            current_event["files"].append({
                "path": file_path,
                "line": int(line_num),
                "column": int(col_num),
                "function": func_name
            })
        else:
            # Extract from raw format: "at funcName (/path/file.js:line:col)"
            file_match = re.search(r'\(([^)]+):(\d+):(\d+)\)', rest)
            if file_match:
                file_path = file_match.group(1)
                line_num = file_match.group(2)
                col_num = file_match.group(3)

                # Extract function name
                func_match = re.match(r'at\s+([^\s(]+)', rest)
                func_name = func_match.group(1) if func_match else "unknown"

                current_event["files"].append({
                    "path": file_path,
                    "line": int(line_num),
                    "column": int(col_num),
                    "function": func_name
                })
    elif current_event and (line.startswith('Error:') or line.startswith('    at')):
        # Additional error context
        current_event["stack_trace"].append(line)

# Save last event
if current_event:
    events.append(current_event)

# Output JSON
print(json.dumps(events, indent=2))
PYTHON_EOF

    rm -f "$VIZ_DIR/temp-logs-with-context.txt"
    
    echo "✅ Generated: $VIZ_DIR/application-logs.json"
    echo "   Contains: $(jq 'length' "$VIZ_DIR/application-logs.json") application log entries"
else
    echo "⚠️  Watchdog log not found, creating empty application-logs.json"
    echo "[]" > "$VIZ_DIR/application-logs.json"
fi

echo ""

# STEP 2: Create unified timeline
echo "═══════════════════════════════════════════════════════════════════"
echo "STEP 2: Create unified timeline with ALL events"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

jq -s '
    (.[0] | map({timestamp, type: "error", severity, message, status})) +
    (.[1] | map({timestamp, type: "system", severity, message, status, metric_value})) +
    (.[2] | map({timestamp, type: "application", severity, message, source}))
    | sort_by(.timestamp)
' "$VIZ_DIR/error-messages.json" "$VIZ_DIR/system-events.json" "$VIZ_DIR/application-logs.json" > "$VIZ_DIR/unified-timeline.json"

echo "✅ Generated: $VIZ_DIR/unified-timeline.json"
echo "   Contains: $(jq 'length' "$VIZ_DIR/unified-timeline.json") total events"
echo ""

echo "═══════════════════════════════════════════════════════════════════"
echo "GRANULAR DATA COMPLETE"
echo "═══════════════════════════════════════════════════════════════════"
echo ""
ls -lh "$VIZ_DIR"/*.json | grep -E '(error-messages|system-events|application-logs|fd-breakdown-timeline|unified-timeline)'
echo ""

echo "END: create-granular-dashboard"

