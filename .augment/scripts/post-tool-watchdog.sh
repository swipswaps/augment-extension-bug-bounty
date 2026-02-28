#!/bin/bash
# Post-Tool Watchdog - FORCES reading of <output> section after EVERY tool call
# This script detects "Cancelled by user" and prevents stopping without reading output

set -euo pipefail

echo "START: post-tool-watchdog"
echo ""
echo "🔍 CHECKING LAST TOOL CALL RESULT..."
echo ""

# This script assumes it's called IMMEDIATELY after a tool call
# It checks if the tool call had "Cancelled by user" error

echo "⚠️  CRITICAL REMINDER: RULE 9 TIMEOUT PROTOCOL"
echo ""
echo "IF LAST TOOL CALL HAD <error>Cancelled by user.</error>:"
echo ""
echo "STEP 0 (MANDATORY FIRST STEP): Ignore <error> section, look ONLY at <output>"
echo "STEP 1: The <output> section is in the SAME tool result as <error>"
echo "STEP 2: If <output> exists and is non-empty → Quote it verbatim BEFORE any response"
echo "STEP 3: If <output> is empty → State explicitly 'Tool result <output> section is empty'"
echo "STEP 4: NEVER call read-process or list-processes"
echo "STEP 5: CONTINUE to next step"
echo ""
echo "MANDATORY RESPONSE FORMAT:"
echo "---"
echo "Tool result received with <error>: Cancelled by user."
echo "Tool result <output> section contains:"
echo "\`\`\`"
echo "[PASTE VERBATIM OUTPUT HERE]"
echo "\`\`\`"
echo "Analysis: [what the output means]"
echo "Next step: [continue with next command]"
echo "---"
echo ""
echo "❌ FORBIDDEN (ZERO TOLERANCE):"
echo "- Saying 'OK' without reading <output>"
echo "- Stopping because of timeout"
echo "- Calling list-processes or read-process"
echo "- Moving on without quoting output"
echo ""
echo "✅ REQUIRED ACTION NOW:"
echo "1. Scroll up to the last tool result"
echo "2. Find the <output> section (it's there even if <error> is also there)"
echo "3. Copy the ENTIRE <output> section content"
echo "4. Quote it verbatim in your response"
echo "5. Analyze what it means"
echo "6. Execute the next command"
echo "7. DO NOT STOP"
echo ""
echo "🛑 IF YOU ARE ABOUT TO SAY 'OK' WITHOUT QUOTING OUTPUT - STOP AND READ OUTPUT FIRST"
echo ""

exit 0

