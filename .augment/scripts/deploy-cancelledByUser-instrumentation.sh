#!/usr/bin/env bash

# WHAT: Deploy _cancelledByUser latch instrumentation to Augment extension
# WHY: User identified _cancelledByUser as root cause of empty <output> sections
# HOW: Prepend instrumentation to extension.js, backup original
#
# ROOT CAUSE (from user analysis in .notes/69935426-075c-8329-b732-ceb8a5e0b600_0090.txt):
# - _cancelledByUser is a one-way latch (never resets to false)
# - When set to true, extension short-circuits and returns "Cancelled by user."
# - Tool <output> is never surfaced, even though command succeeded
# - Triggered by spurious cancel-tool-run message under terminal resource pressure
#
# EVIDENCE:
# - Line 235772: _cancelledByUser = !1 (initialization only)
# - Line 235861: close(true) sets _cancelledByUser = true
# - Line 235911: callTool() returns "Cancelled by user." when flag is true
# - Line ~270918: cancel-tool-run message handler triggers close(true)

set -euo pipefail

EXTENSION_DIR="$HOME/.vscode/extensions"
AUGMENT_EXTENSION=$(find "$EXTENSION_DIR" -maxdepth 1 -type d -name "augment.vscode-augment-*" | sort -V | tail -1)

if [[ -z "$AUGMENT_EXTENSION" ]]; then
    echo "❌ ERROR: Augment extension not found in $EXTENSION_DIR"
    exit 1
fi

EXTENSION_JS="$AUGMENT_EXTENSION/out/extension.js"
BACKUP_FILE="$AUGMENT_EXTENSION/out/extension.js.backup-cancelledByUser-$(date +%Y%m%d-%H%M%S)"
INSTRUMENTATION_FILE="./instrument-cancelledByUser-latch.js"
LOG_FILE="./augment-cancelledByUser-debug.log"

echo "================================================================================
DEPLOYING _cancelledByUser LATCH INSTRUMENTATION
================================================================================

Extension: $AUGMENT_EXTENSION
Target file: $EXTENSION_JS
Backup file: $BACKUP_FILE
Instrumentation: $INSTRUMENTATION_FILE
Log file: $LOG_FILE

WHAT THIS DOES:
- Backs up original extension.js
- Prepends _cancelledByUser instrumentation to extension.js
- Captures stack traces when latch is set to true or false
- Logs terminal count and FD count at mutation moment

EXPECTED RESULTS:
- Initialization: _cancelledByUser = false (once)
- Latch trigger: _cancelledByUser = true (under resource pressure)
- NEVER: _cancelledByUser = false (after initialization)

If you see _cancelledByUser set to true, that is the moment all tool calls start failing.
================================================================================
"

# WHAT: Verify instrumentation file exists
# WHY: Cannot deploy if instrumentation code is missing
# HOW: Check file existence before proceeding
if [[ ! -f "$INSTRUMENTATION_FILE" ]]; then
    echo "❌ ERROR: Instrumentation file not found: $INSTRUMENTATION_FILE"
    exit 1
fi

# WHAT: Verify extension.js exists
# WHY: Cannot patch if target file is missing
# HOW: Check file existence before proceeding
if [[ ! -f "$EXTENSION_JS" ]]; then
    echo "❌ ERROR: Extension file not found: $EXTENSION_JS"
    exit 1
fi

# WHAT: Create backup of original extension.js
# WHY: User needs ability to rollback if instrumentation causes issues
# HOW: Copy extension.js to timestamped backup file
echo "📦 Creating backup..."
cp "$EXTENSION_JS" "$BACKUP_FILE"
echo "✅ Backup created: $BACKUP_FILE"

# WHAT: Prepend instrumentation to extension.js
# WHY: Instrumentation must load before extension code executes
# HOW: Concatenate instrumentation + original extension.js
echo "🔧 Deploying instrumentation..."
{
    cat "$INSTRUMENTATION_FILE"
    echo ""
    echo "// =============================================================================="
    echo "// ORIGINAL EXTENSION.JS BELOW"
    echo "// =============================================================================="
    echo ""
    cat "$BACKUP_FILE"
} > "$EXTENSION_JS"

echo "✅ Instrumentation deployed successfully"

# WHAT: Verify deployment
# WHY: User needs confirmation that instrumentation is in place
# HOW: Check file size and grep for instrumentation marker
ORIGINAL_SIZE=$(stat -c%s "$BACKUP_FILE")
INSTRUMENTED_SIZE=$(stat -c%s "$EXTENSION_JS")
INSTRUMENTATION_SIZE=$((INSTRUMENTED_SIZE - ORIGINAL_SIZE))

echo "
================================================================================
DEPLOYMENT VERIFICATION
================================================================================

Original size: $ORIGINAL_SIZE bytes
Instrumented size: $INSTRUMENTED_SIZE bytes
Instrumentation overhead: $INSTRUMENTATION_SIZE bytes

Instrumentation markers found:
$(grep -c "_cancelledByUser LATCH MUTATION DETECTED" "$EXTENSION_JS" || echo 0) occurrences

================================================================================
NEXT STEPS
================================================================================

1. Reload VS Code window (Ctrl+Shift+P → 'Developer: Reload Window')
2. Use Augment AI normally until 'Cancelled by user' error appears
3. Check log file: $LOG_FILE
4. Run: ./.augment/scripts/show-cancelledByUser-stack-traces.sh

The instrumentation will capture:
- Stack trace when _cancelledByUser set to true (latch engaged)
- Terminal count at mutation moment
- File descriptor count at mutation moment
- Process PID and timestamp

This will provide definitive proof for Augment team showing when/why latch triggers.
================================================================================
"

# WHAT: Initialize log file
# WHY: User needs to see instrumentation is active
# HOW: Touch log file to create it
touch "$LOG_FILE"
echo "✅ Log file initialized: $LOG_FILE"

echo "
🎯 DEPLOYMENT COMPLETE

To verify instrumentation is active, reload VS Code and check:
  cat $LOG_FILE

To rollback instrumentation:
  cp $BACKUP_FILE $EXTENSION_JS
"

