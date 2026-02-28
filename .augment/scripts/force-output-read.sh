#!/bin/bash
# WHAT: Force LLM to read command output by adding mandatory delay AFTER command completes
# WHY: Tool infrastructure reads output split second before it's fully written to buffer
# HOW: Add sleep 0.5 AFTER command completes, BEFORE returning control to LLM

# WHAT: This wrapper ensures output buffer is fully flushed before tool returns
# WHY: Race condition between command completion and output buffer flush
# HOW: Command runs → output writes to buffer → sleep 0.5 → buffer fully flushed → tool returns

# USAGE: force-output-read.sh "command to run"
# EXAMPLE: force-output-read.sh "sqlite3 db.db 'SELECT * FROM errors;'"

COMMAND="$1"
LOGFILE=".notes/terminal-$(date +%Y%m%d-%H%M%S).log"

# WHAT: Run command with START/END markers
# WHY: Verify command completed and output was captured
# HOW: echo START → run command → echo END → sleep to flush buffer
echo "START: $COMMAND" | tee -a "$LOGFILE"

# WHAT: Execute the actual command
# WHY: This is what user requested
# HOW: eval to handle complex commands with pipes, redirects, etc.
eval "$COMMAND" 2>&1 | tee -a "$LOGFILE"

# WHAT: Capture exit code BEFORE any other commands
# WHY: Need to preserve command's actual exit code
# HOW: Store in variable immediately after command
EXIT_CODE=${PIPESTATUS[0]}

echo "END: $COMMAND (exit code: $EXIT_CODE)" | tee -a "$LOGFILE"

# WHAT: CRITICAL DELAY - Wait for output buffer to flush
# WHY: Tool reads output split second before buffer is fully written
# HOW: sleep 0.5 seconds to ensure all output is in buffer before tool returns
sleep 0.5

echo "" | tee -a "$LOGFILE"
echo "Log file: $LOGFILE" | tee -a "$LOGFILE"

# WHAT: Return original command's exit code
# WHY: Preserve success/failure status for caller
# HOW: exit with stored EXIT_CODE
exit $EXIT_CODE

