#!/usr/bin/env python3
"""
USER REQUEST: "try to show what line and subroutine of what file or scripts called or caused the error"
PURPOSE: Extract error messages with FULL stack traces from Augment.log
BENEFIT: LLM can see exact file (extension.js:252:1928) and function (eH.callApi) that caused error
TROUBLESHOOTING VALUE: Shows call chain: callApi → chatInputCompletion → callChatInputCompletionAPI → fetchCompletion
"""

import re
import json
import sys
from pathlib import Path
from datetime import datetime

# FIND AUGMENT LOG
log_dir = Path.home() / ".config/Code/logs"
augment_logs = list(log_dir.glob("**/Augment.log"))

if not augment_logs:
    print("ERROR: No Augment.log found", file=sys.stderr)
    sys.exit(1)

# Use most recent log
augment_log = sorted(augment_logs, key=lambda p: p.stat().st_mtime)[-1]
print(f"Parsing: {augment_log}", file=sys.stderr)

# PARSE LOG WITH STACK TRACES
events = []
current_event = None

with open(augment_log, 'r', errors='ignore') as f:
    for line in f:
        line = line.rstrip()
        
        # Match log entry: "2026-02-18 13:01:00.652 [error] 'ClientWorkspaces': Failed to call..."
        log_match = re.match(r'(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3}) \[(\w+)\] (.+)', line)
        
        if log_match:
            # Save previous event
            if current_event:
                events.append(current_event)
            
            # Start new event
            timestamp_str = log_match.group(1)
            severity = log_match.group(2).upper()
            message = log_match.group(3)
            
            # Convert timestamp to ISO format
            dt = datetime.strptime(timestamp_str, "%Y-%m-%d %H:%M:%S.%f")
            timestamp_iso = dt.strftime("%Y-%m-%dT%H:%M:%S.%f")[:-3] + "Z"
            
            # Extract source from message (e.g., 'ClientWorkspaces':)
            source_match = re.match(r"'([^']+)':\s*(.*)", message)
            if source_match:
                source = source_match.group(1)
                message_text = source_match.group(2)
            else:
                source = "Augment"
                message_text = message
            
            current_event = {
                "timestamp": timestamp_iso,
                "source": source,
                "severity": severity,
                "message": message_text,
                "stack_trace": [],
                "files": []
            }
        
        elif current_event:
            # Check for stack trace lines
            if line.startswith('\tat '):
                # Stack trace: "\tat eH.callApi (/home/owner/.vscode/extensions/.../extension.js:252:1928)"
                current_event["stack_trace"].append(line.strip())
                
                # Extract file path, line, column, function
                file_match = re.search(r'\(([^)]+):(\d+):(\d+)\)', line)
                if file_match:
                    file_path = file_match.group(1)
                    line_num = int(file_match.group(2))
                    col_num = int(file_match.group(3))
                    
                    # Extract function name
                    func_match = re.match(r'\s*at\s+([^\s(]+)', line)
                    func_name = func_match.group(1) if func_match else "unknown"
                    
                    # Simplify file path (show only filename and extension name)
                    if '/extensions/' in file_path:
                        parts = file_path.split('/extensions/')
                        if len(parts) > 1:
                            ext_parts = parts[1].split('/')
                            simplified_path = f"{ext_parts[0]}/{ext_parts[-1]}"
                        else:
                            simplified_path = Path(file_path).name
                    else:
                        simplified_path = Path(file_path).name
                    
                    current_event["files"].append({
                        "path": file_path,
                        "simplified_path": simplified_path,
                        "line": line_num,
                        "column": col_num,
                        "function": func_name
                    })
            
            elif line.startswith('Error:') or line.startswith('    at'):
                # Additional error context
                current_event["stack_trace"].append(line.strip())

# Save last event
if current_event:
    events.append(current_event)

# OUTPUT JSON
print(json.dumps(events, indent=2))

print(f"✅ Extracted {len(events)} log entries", file=sys.stderr)
print(f"   With stack traces: {sum(1 for e in events if e['stack_trace'])}", file=sys.stderr)
print(f"   With file info: {sum(1 for e in events if e['files'])}", file=sys.stderr)

