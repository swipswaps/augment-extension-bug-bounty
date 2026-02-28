#!/usr/bin/env bash
set -euo pipefail

# PROBLEM: Watchdog log shows recursive entries like:
#   /1-Watchdog Log.log:[timestamp]   /1-Watchdog Log.log:[timestamp]   /1-Watchdog Log.log:[timestamp]
# ROOT CAUSE: grep -iH searches ALL .log files including watchdog's own log
# RECURSION: Watchdog logs "EXTENSION ERROR" → grep finds "error" in watchdog log → logs it → grep finds THAT
# RESULT: Infinite recursion, log spam, no useful error information

LOGFILE=".notes/explain-recursive-fix-$(date +%Y%m%d-%H%M%S).log"
mkdir -p .notes
exec > >(tee -a "$LOGFILE") 2>&1

echo "START: explain-recursive-watchdog-fix"
echo ""

echo "═══════════════════════════════════════════════════════════════════"
echo "🔍 PROBLEM DIAGNOSIS"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

echo "USER SHOWED THIS OUTPUT:"
echo "  /.../1-Watchdog Log.log:[timestamp]   /.../1-Watchdog Log.log:[timestamp]   /.../Augment.vscode-"
echo "  /.../1-Watchdog Log.log:[timestamp]   /.../1-Watchdog Log.log:[timestamp]   /.../Augment.vscode-"
echo ""

echo "WHAT THIS MEANS:"
echo "  1. grep -iH 'error' searches ALL .log files"
echo "  2. Watchdog log CONTAINS the word 'error' (in 'EXTENSION ERROR' entries)"
echo "  3. grep finds 'error' in watchdog log → logs it"
echo "  4. Next cycle: grep finds 'error' in THAT log entry → logs it again"
echo "  5. RECURSION: Each cycle adds more watchdog log references"
echo ""

echo "WHY IT'S NOT DETAILED:"
echo "  - Lines are truncated at 500 chars"
echo "  - Full path repeated multiple times wastes space"
echo "  - Actual error message is at the END, gets cut off"
echo "  - Example: '/path/Watchdog.log:[time] /path/Watchdog.log:[time] /path/Augment.log:ACTUAL ERROR HERE' → truncated"
echo ""

echo "═══════════════════════════════════════════════════════════════════"
echo "🔧 FIX IMPLEMENTED"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

echo "CHANGE 1: Exclude watchdog's own log from grep"
echo "  BEFORE: find \${logsDir} -name '*.log' -exec grep -iH 'error' {} \\;"
echo "  AFTER:  find \${logsDir} -name '*.log' ! -name '*Watchdog*' -exec grep -iH 'error' {} \\;"
echo "  RESULT: grep no longer searches watchdog log, breaks recursion"
echo ""

echo "CHANGE 2: Filter out [info] level messages"
echo "  BEFORE: grep -iH 'error\\|exception'"
echo "  AFTER:  grep -iH 'error\\|exception' | grep -v '\\[info\\]'"
echo "  RESULT: Only log actual errors, not info messages containing word 'error'"
echo ""

echo "CHANGE 3: Extract filename and message separately"
echo "  BEFORE: log(\`  \${line.substring(0, 500)}\`)"
echo "  AFTER:  const match = line.match(/([^:]+\\.log):(.+)/);"
echo "          const filename = match[1].split('/').pop();"
echo "          const message = match[2];"
echo "          log(\`  \${filename}: \${message}\`);"
echo "  RESULT: 'Augment.log: 2026-02-18 12:17:37.236 [error] API request failed'"
echo "          Instead of: '/home/owner/.config/Code/logs/.../Augment.log:2026-02-18...'"
echo ""

echo "CHANGE 4: Increase tail from 10 to 20 lines"
echo "  BEFORE: tail -10"
echo "  AFTER:  tail -20"
echo "  RESULT: More error context, less likely to miss important errors"
echo ""

echo "═══════════════════════════════════════════════════════════════════"
echo "🔧 FIX FOR FILE DESCRIPTOR WARNINGS"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

echo "PROBLEM: '19680 code 123893' doesn't explain WHAT is consuming FDs"
echo "  - Is it file watchers?"
echo "  - Is it network sockets?"
echo "  - Is it pipes to child processes?"
echo "  - Can't tell from just process name and PID"
echo ""

echo "CHANGE 1: Show FD number and type"
echo "  BEFORE: awk '{print \$1, \$2}' (process, PID)"
echo "  AFTER:  awk '{print \$1, \$2, \$4, \$5}' (process, PID, FD#, type)"
echo "  RESULT: '25776 code 123893 4u REG' → 25776 FDs, process 'code', PID 123893, FD 4, type REG (regular file)"
echo ""

echo "CHANGE 2: Add FD breakdown by type"
echo "  NEW: lsof | grep code | awk '{print \$5}' | sort | uniq -c | sort -rn"
echo "  RESULT:"
echo "    45000 REG   (regular files - likely file watchers)"
echo "     3000 unix  (unix sockets - IPC between processes)"
echo "     2000 pipe  (pipes to child processes)"
echo "  ACTION: If REG is high → disable file watchers or reduce watched files"
echo "          If unix is high → extension host communication leak"
echo "          If pipe is high → child process leak (terminals, language servers)"
echo ""

echo "═══════════════════════════════════════════════════════════════════"
echo "📋 VERIFICATION STEPS"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

echo "1. Reload VS Code window (Ctrl+Shift+P > 'Reload Window')"
echo "2. Wait 60 seconds for monitoring cycle"
echo "3. Check watchdog log:"
echo ""
echo "   WATCHDOG_LOG=\$(find ~/.config/Code/logs -name '*Watchdog Log.log' -type f | sort | tail -1)"
echo "   tail -50 \"\$WATCHDOG_LOG\""
echo ""

echo "EXPECTED OUTPUT (EXTENSION ERROR):"
echo "  [2026-02-18T17:25:26.603Z] EXTENSION ERROR | VS Code logs (last 1min) | count=5"
echo "  [2026-02-18T17:25:26.603Z]   Augment.log: 2026-02-18 12:17:37.236 [error] 'AugmentExtensionSidecar': API request failed"
echo "  [2026-02-18T17:25:26.604Z]   Augment.log: 2026-02-18 12:17:37.236 [error] 'AugmentExtensionSidecar': AbortError: This operation was aborted"
echo "  [2026-02-18T17:25:26.606Z]   Augment.log: 2026-02-18 12:17:38.939 [error] 'AugmentExtensionSidecar': API request timeout"
echo ""

echo "EXPECTED OUTPUT (FILE DESCRIPTOR):"
echo "  [2026-02-18T17:25:30.100Z] FILE DESCRIPTOR WARNING | VS Code FDs=51552 | threshold=50000"
echo "  [2026-02-18T17:25:33.766Z]   Top FD consumers (count, process, PID, FD#, type):"
echo "  [2026-02-18T17:25:33.766Z]     19680 code 123893 4u REG"
echo "  [2026-02-18T17:25:33.766Z]      4130 code 124008 5u unix"
echo "  [2026-02-18T17:25:33.766Z]   FD breakdown by type:"
echo "  [2026-02-18T17:25:33.766Z]     45000 REG"
echo "  [2026-02-18T17:25:33.766Z]      3000 unix"
echo "  [2026-02-18T17:25:33.766Z]      2000 pipe"
echo ""

echo "═══════════════════════════════════════════════════════════════════"
echo "✅ SUMMARY"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

echo "FIXES APPLIED:"
echo "  ✅ Exclude watchdog log from grep (breaks recursion)"
echo "  ✅ Filter out [info] messages (only log actual errors)"
echo "  ✅ Extract filename separately (shorter, clearer output)"
echo "  ✅ Show FD type and number (identify leak source)"
echo "  ✅ Add FD breakdown by type (actionable diagnostics)"
echo ""

echo "NEXT STEP:"
echo "  Reload VS Code window to activate updated extension"
echo ""

echo "END: explain-recursive-watchdog-fix"

