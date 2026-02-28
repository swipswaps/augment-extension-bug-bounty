#!/bin/bash
# MANDATORY COMPLIANCE CHECK - MUST RUN BEFORE EVERY RESPONSE
# This script enforces @rules compliance and prevents RULE 9 violations

set -e

LOGFILE=".notes/compliance-$(date +%Y%m%d-%H%M%S).log"

echo "START: mandatory-compliance-check" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"

# RULE 0: Write Then Follow Exactly The Correct Prompt
echo "✅ RULE 0: Write Then Follow Exactly The Correct Prompt" | tee -a "$LOGFILE"
echo "   - FIRST write the exact prompt to follow" | tee -a "$LOGFILE"
echo "   - THEN execute it step-by-step without deviation" | tee -a "$LOGFILE"
echo "   - PROCEED WITHOUT STOPPING UNLESS IMPOSSIBLE" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"

# RULE 9: Mandatory Output Reading
echo "✅ RULE 9: Mandatory Output Reading (ZERO TOLERANCE)" | tee -a "$LOGFILE"
echo "   - AFTER EVERY launch-process call:" | tee -a "$LOGFILE"
echo "     1. Read <output> section from tool result" | tee -a "$LOGFILE"
echo "     2. Read corresponding log file from .notes/" | tee -a "$LOGFILE"
echo "     3. Quote verbatim output from BOTH sources" | tee -a "$LOGFILE"
echo "     4. Verify they match" | tee -a "$LOGFILE"
echo "     5. If <output> is truncated but log file has complete output → use log file" | tee -a "$LOGFILE"
echo "     6. NEVER skip log file reading" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"

# RULE 9 TIMEOUT PROTOCOL
echo "✅ RULE 9 TIMEOUT PROTOCOL (MANDATORY):" | tee -a "$LOGFILE"
echo "   When launch-process returns timeout or <error>Cancelled by user.</error>:" | tee -a "$LOGFILE"
echo "   - STEP 0 (MANDATORY FIRST STEP): Ignore <error> section, look ONLY at <output> section" | tee -a "$LOGFILE"
echo "   - STEP 1: The <output> section is in the SAME tool result - look for it NOW" | tee -a "$LOGFILE"
echo "   - STEP 2: If <output> exists and is non-empty → Quote it verbatim BEFORE any other response" | tee -a "$LOGFILE"
echo "   - STEP 3: If <output> is empty or missing → State explicitly 'Tool result <output> section is empty'" | tee -a "$LOGFILE"
echo "   - STEP 4: NEVER call read-process or list-processes" | tee -a "$LOGFILE"
echo "   - STEP 5: read-terminal is allowed as fallback when <output> is empty/truncated" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"

# FORBIDDEN PATTERNS
echo "❌ FORBIDDEN (ZERO TOLERANCE):" | tee -a "$LOGFILE"
echo "   - Saying 'OK' without reading output" | tee -a "$LOGFILE"
echo "   - Ignoring <output> section when it exists" | tee -a "$LOGFILE"
echo "   - Assuming failure without checking output" | tee -a "$LOGFILE"
echo "   - Calling read-process after timeout (output is in tool result)" | tee -a "$LOGFILE"
echo "   - Calling list-processes to find terminals (output is in tool result)" | tee -a "$LOGFILE"
echo "   - Making assumptions about command success/failure without evidence" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"

# TERMINAL LOGGING REQUIREMENT
echo "✅ MANDATORY TERMINAL LOGGING:" | tee -a "$LOGFILE"
echo "   ALL commands MUST log to .notes/terminal-YYYYMMDD-HHMMSS.log:" | tee -a "$LOGFILE"
echo '   LOGFILE=".notes/terminal-$(date +%Y%m%d-%H%M%S).log"' | tee -a "$LOGFILE"
echo '   echo "START: action" | tee -a "$LOGFILE" && command 2>&1 | tee -a "$LOGFILE" && echo "END: action" | tee -a "$LOGFILE"' | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"

# CHECK RECENT TERMINAL LOGS
echo "📋 RECENT TERMINAL LOGS:" | tee -a "$LOGFILE"
ls -lht .notes/terminal-*.log 2>&1 | head -5 | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"

# CHECK IF TERMINAL HAS UNREAD OUTPUT
echo "📺 CHECKING TERMINAL FOR UNREAD OUTPUT:" | tee -a "$LOGFILE"
echo "   (This simulates what the LLM should do after EVERY command)" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"

echo "END: mandatory-compliance-check" | tee -a "$LOGFILE"
echo "LOG: $LOGFILE" | tee -a "$LOGFILE"

# Return success
exit 0

