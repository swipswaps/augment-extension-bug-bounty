#!/usr/bin/env bash
#
# Fix Terminal Accumulation and Timeout Issues
#
# WHAT: Prevents terminal spam and timeout errors that cause "Request cancelled"
# WHY: RULE 22 violation - terminal accumulation causes MCP instability
# HOW: Use single terminals, proper logging, avoid wait=false
#
# WORKING EXAMPLE:
#   ./.augment/scripts/fix-terminal-timeout-issues.sh
#
# RESOLVES:
#   1. Terminal accumulation (spawning dozens of terminals)
#   2. Timeout errors ("Request cancelled" x30 in database)
#   3. MCP client instability (cancel-tool-run signals)
#   4. VS Code crashes from improper reload signals

set -euo pipefail

LOGFILE=".notes/terminal-fix-$(date +%Y%m%d-%H%M%S).log"
DB_FILE=".augment/error_tracking.db"

exec > >(tee -a "$LOGFILE") 2>&1

echo "START: fix-terminal-timeout-issues"
echo "Timestamp: $(date --iso-8601=seconds)"
echo ""

# ============================================================================
# PROBLEM 1: Terminal Accumulation
# ============================================================================
echo "=== PROBLEM 1: Terminal Accumulation ==="
echo ""
echo "WHAT: Spawning dozens of unreused terminals"
echo "WHY: Each launch-process with wait=false creates persistent terminal"
echo "EVIDENCE:"
sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM errors WHERE error_message LIKE '%terminal%' OR error_message LIKE '%process%';" | \
    awk '{print "  - " $1 " terminal-related errors in database"}'
echo ""

echo "HOW TO FIX:"
echo "  ✅ CORRECT: Use wait=true (output in tool result <output> section)"
echo "  ✅ CORRECT: Combine commands with && instead of separate terminals"
echo "  ✅ CORRECT: Reuse existing terminals for related commands"
echo "  ❌ WRONG: Use wait=false (creates hidden terminal)"
echo "  ❌ WRONG: Spawn new terminal for each small command"
echo ""

echo "WORKING EXAMPLE:"
cat << 'EXAMPLE'
# ❌ WRONG - Creates 3 separate terminals
launch-process: git status (wait=false)
launch-process: git diff (wait=false)
launch-process: git log (wait=false)
# Result: 3 persistent terminals, resource waste

# ✅ CORRECT - Single terminal, combined command
launch-process: git status && echo "---" && git diff --stat && echo "---" && git log --oneline -5 (wait=true)
# Result: 1 terminal, output in <output> section, auto-cleanup
EXAMPLE
echo ""

# ============================================================================
# PROBLEM 2: Timeout Errors
# ============================================================================
echo "=== PROBLEM 2: Timeout Errors ==="
echo ""
echo "WHAT: 'Request cancelled' errors (30 in database)"
echo "WHY: Commands timeout but LLM doesn't read partial output"
echo "EVIDENCE:"
sqlite3 "$DB_FILE" "SELECT timestamp, error_message FROM errors WHERE error_type = 'Request cancelled' ORDER BY id DESC LIMIT 3;" | \
    awk '{print "  - " $0}'
echo ""

echo "HOW TO FIX:"
echo "  ✅ CORRECT: Read <output> section even if timeout"
echo "  ✅ CORRECT: Quote verbatim output before analyzing"
echo "  ✅ CORRECT: Use max_wait_seconds=10 (not 3)"
echo "  ❌ WRONG: Ignore <output> section when timeout occurs"
echo "  ❌ WRONG: Call list-processes or read-process after timeout"
echo ""

echo "WORKING EXAMPLE:"
cat << 'EXAMPLE'
# Command times out after 3 seconds
Tool result: <error>Cancelled by user.</error>
             <output>START: action
                     Partial output here...
             </output>

# ❌ WRONG - LLM ignores <output> section
"Tool call was cancelled due to timeout" → [moves on]

# ✅ CORRECT - LLM reads <output> section
"Tool result <output> section contains:
```
START: action
Partial output here...
```
Command timed out but captured partial output. Proceeding..."
EXAMPLE
echo ""

# ============================================================================
# PROBLEM 3: VS Code Reload Crashes
# ============================================================================
echo "=== PROBLEM 3: VS Code Reload Crashes ==="
echo ""
echo "WHAT: 'the window terminated unexpectedly (reason: clean-exit, code: 0)'"
echo "WHY: Sending improper signals (pkill -SIGUSR1, kill -9) to VS Code"
echo ""

echo "HOW TO FIX:"
echo "  ✅ CORRECT: User manually reloads (Ctrl+Shift+P → Developer: Reload Window)"
echo "  ✅ CORRECT: Ask user to reload instead of forcing"
echo "  ❌ WRONG: pkill -SIGUSR1 code (causes clean-exit crash)"
echo "  ❌ WRONG: kill -9 <vscode-pid> (causes killed, code: 9 crash)"
echo "  ❌ WRONG: xdotool automation (unreliable, causes timeouts)"
echo ""

echo "WORKING EXAMPLE:"
cat << 'EXAMPLE'
# ❌ WRONG - Causes crash
pkill -SIGUSR1 code
# Result: "window terminated unexpectedly (reason: clean-exit, code: 0)"

# ✅ CORRECT - Ask user
echo "Extension installed. Please reload VS Code:"
echo "  Ctrl+Shift+P → Developer: Reload Window"
# Result: User controls reload, no crashes
EXAMPLE
echo ""

# ============================================================================
# SOLUTION SUMMARY
# ============================================================================
echo "=== SOLUTION SUMMARY ==="
echo ""
echo "1. Terminal Management:"
echo "   - Use wait=true for all commands"
echo "   - Combine related commands with &&"
echo "   - Maximum 5 active terminals at once"
echo ""
echo "2. Timeout Handling:"
echo "   - ALWAYS read <output> section (even if timeout)"
echo "   - Quote verbatim output before analysis"
echo "   - Use max_wait_seconds=10 minimum"
echo ""
echo "3. VS Code Reload:"
echo "   - NEVER send signals to VS Code processes"
echo "   - Ask user to reload manually"
echo "   - Document reload steps clearly"
echo ""

echo "✅ Fix script complete"
echo "END: fix-terminal-timeout-issues"

