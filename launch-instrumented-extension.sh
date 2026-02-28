#!/usr/bin/env bash
###############################################################################
# AUGMENT EXTENSION LATCH INSTRUMENTATION LAUNCHER
#
# VERSION: 1.0.0
# CREATED: 2026-02-21T21:30:00Z
#
# PURPOSE:
#   Deploy latch instrumentation to Augment extension and launch VS Code
#
# WHAT THIS DOES:
#   1. Auto-detect Augment extension.js path
#   2. Backup original extension.js (timestamped)
#   3. Inject require('./instrument-latches.js') at top of extension entry point
#   4. Ensure file permissions are correct
#   5. Provide rollback command
#
# COMPLIANCE:
#   RULE 0  - Emission gate: All steps verified before execution
#   RULE 2  - No partial compliance: Complete deployment or rollback
#   RULE 6  - Known working patterns: Standard bash file manipulation
#   RULE 11 - No placeholders: All paths are real, auto-detected
#   RULE 18 - Rollback present: Backup and restore commands included
#   RULE 22 - Terminal hygiene: Single command, no wait=false, no terminal spam
#
# ENVIRONMENT:
#   - Bash 4+
#   - VS Code with Augment extension installed
#   - Node.js 18+
#
# SAFETY:
#   - Creates timestamped backup before modification
#   - Provides explicit rollback command
#   - Verifies file existence before proceeding
###############################################################################

set -euo pipefail

# WHAT: Locate Augment extension directory
# WHY: Extension path varies by version
# HOW: Find most recent version in ~/.vscode/extensions
EXTENSION_DIR="$HOME/.vscode/extensions"
AUGMENT_EXTENSION=$(find "$EXTENSION_DIR" -maxdepth 1 -type d -name "augment.vscode-augment-*" | sort -V | tail -1)

if [[ -z "$AUGMENT_EXTENSION" ]]; then
    echo "❌ ERROR: Augment extension not found in $EXTENSION_DIR"
    exit 1
fi

# WHAT: Define file paths
# WHY: Need to know where to inject instrumentation
# HOW: Standard extension structure has out/extension.js
EXTENSION_JS="$AUGMENT_EXTENSION/out/extension.js"
BACKUP_FILE="$AUGMENT_EXTENSION/out/extension.js.backup-latches-$(date +%Y%m%d-%H%M%S)"
INSTRUMENTATION_FILE="./instrument-latches.js"
LOG_FILE="./augment-latch-debug.log"

echo "================================================================================
AUGMENT EXTENSION LATCH INSTRUMENTATION DEPLOYMENT
================================================================================

Extension: $AUGMENT_EXTENSION
Target file: $EXTENSION_JS
Backup file: $BACKUP_FILE
Instrumentation: $INSTRUMENTATION_FILE
Log file: $LOG_FILE

WHAT THIS DOES:
- Backs up original extension.js
- Injects latch instrumentation at top of extension.js
- Captures stack traces when _closingPromise or _cancelledByUser are set
- Logs to $LOG_FILE with full context

EXPECTED RESULTS:
- Initialization: _cancelledByUser = false (once)
- Latch trigger: _cancelledByUser = true (under resource pressure)
- Full stack trace showing which function triggered the latch

================================================================================
"

# WHAT: Verify instrumentation file exists
# WHY: Cannot deploy if instrumentation code is missing
# HOW: Check file existence before proceeding
if [[ ! -f "$INSTRUMENTATION_FILE" ]]; then
    echo "❌ ERROR: Instrumentation file not found: $INSTRUMENTATION_FILE"
    echo ""
    echo "Expected file: $INSTRUMENTATION_FILE"
    echo "Current directory: $(pwd)"
    exit 1
fi

# WHAT: Verify extension.js exists
# WHY: Cannot patch if target file is missing
# HOW: Check file existence before proceeding
if [[ ! -f "$EXTENSION_JS" ]]; then
    echo "❌ ERROR: Extension file not found: $EXTENSION_JS"
    echo ""
    echo "Extension directory: $AUGMENT_EXTENSION"
    echo "Expected file: $EXTENSION_JS"
    exit 1
fi

# WHAT: Create backup of original extension.js
# WHY: User needs ability to rollback if instrumentation causes issues
# HOW: Copy extension.js to timestamped backup file
echo "📦 Creating backup..."
cp "$EXTENSION_JS" "$BACKUP_FILE"
echo "✅ Backup created: $BACKUP_FILE"

# WHAT: Copy instrumentation file to extension directory
# WHY: require('./instrument-latches.js') needs file in same directory
# HOW: Copy to out/ directory where extension.js lives
INSTRUMENTATION_DEST="$AUGMENT_EXTENSION/out/instrument-latches.js"
echo "📦 Copying instrumentation to extension directory..."
cp "$INSTRUMENTATION_FILE" "$INSTRUMENTATION_DEST"
echo "✅ Instrumentation copied: $INSTRUMENTATION_DEST"

# WHAT: Inject instrumentation at top of extension.js
# WHY: Instrumentation must load before extension code executes
# HOW: Prepend require() statement to extension.js
echo "🔧 Injecting instrumentation..."
{
    echo "// LATCH INSTRUMENTATION INJECTED $(date -Iseconds)"
    echo "// WHAT: Instrument _closingPromise and _cancelledByUser latches"
    echo "// WHY: Capture stack traces when latches are set"
    echo "// HOW: Object.defineProperty() intercepts property assignments"
    echo "require('./instrument-latches.js');"
    echo ""
    cat "$BACKUP_FILE"
} > "$EXTENSION_JS"

echo "✅ Instrumentation injected successfully"

# WHAT: Verify deployment
# WHY: User needs confirmation that instrumentation is in place
# HOW: Check file size and grep for instrumentation marker
ORIGINAL_SIZE=$(stat -c%s "$BACKUP_FILE")
INSTRUMENTED_SIZE=$(stat -c%s "$EXTENSION_JS")
INSTRUMENTATION_OVERHEAD=$((INSTRUMENTED_SIZE - ORIGINAL_SIZE))

echo "
================================================================================
DEPLOYMENT VERIFICATION
================================================================================

Original size: $ORIGINAL_SIZE bytes
Instrumented size: $INSTRUMENTED_SIZE bytes
Instrumentation overhead: $INSTRUMENTATION_OVERHEAD bytes

Instrumentation markers found:
$(grep -c "LATCH INSTRUMENTATION INJECTED" "$EXTENSION_JS" || echo 0) injection markers
$(grep -c "require('./instrument-latches.js')" "$EXTENSION_JS" || echo 0) require statements

================================================================================
ROLLBACK COMMAND (if needed)
================================================================================

To restore original extension.js:

  cp \"$BACKUP_FILE\" \"$EXTENSION_JS\"
  rm \"$INSTRUMENTATION_DEST\"

Then reload VS Code window.

================================================================================
NEXT STEPS
================================================================================

1. Reload VS Code window:
   - Press Ctrl+Shift+P
   - Type: Developer: Reload Window
   - Press Enter

2. Use Augment AI normally until 'Cancelled by user' error appears

3. Check log file for stack traces:
   cat $LOG_FILE

4. The log will show:
   - Exact function that set _cancelledByUser = true
   - Full call chain leading to latch trigger
   - Terminal count and FD count (if instrumented)
   - Timestamp and process PID

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

Instrumentation is now active. Reload VS Code to activate.

To verify instrumentation is working:
  1. Reload VS Code window
  2. cat $LOG_FILE
  3. Look for [INSTRUMENTATION INITIALIZED] message

To rollback:
  cp \"$BACKUP_FILE\" \"$EXTENSION_JS\"
  rm \"$INSTRUMENTATION_DEST\"
"

