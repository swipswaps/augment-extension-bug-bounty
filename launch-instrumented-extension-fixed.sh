#!/usr/bin/env bash
###############################################################################
# AUGMENT EXTENSION LATCH INSTRUMENTATION LAUNCHER (FIXED - INSTANCE-LEVEL)
#
# VERSION: 2.0.0
# CREATED: 2026-02-22T12:13:00Z
#
# PURPOSE:
#   Deploy FIXED latch instrumentation (instance-level) to Augment extension
#
# WHAT CHANGED FROM v1.0:
#   - Now uses Module._load hook (not just exports)
#   - Wraps constructor to instrument instances at creation time
#   - Self-executing module (no external function calls needed)
#
# COMPLIANCE:
#   RULE 0  - Emission gate: All steps verified before execution
#   RULE 2  - No partial compliance: Complete deployment or rollback
#   RULE 6  - Known working patterns: Standard bash file manipulation
#   RULE 11 - No placeholders: All paths are real, auto-detected
#   RULE 18 - Rollback present: Backup and restore commands included
#   RULE 22 - Terminal hygiene: Single command, no wait=false
#
# ENVIRONMENT:
#   - Bash 4+
#   - VS Code with Augment extension installed
#   - Node.js 18+
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
BACKUP_FILE="$AUGMENT_EXTENSION/out/extension.js.backup-latches-fixed-$(date +%Y%m%d-%H%M%S)"
INSTRUMENTATION_FILE="./instrument-latches-fixed.js"
INSTRUMENTATION_DEST="$AUGMENT_EXTENSION/out/instrument-latches-fixed.js"
LOG_FILE="./augment-latch-debug.log"

echo "================================================================================
AUGMENT EXTENSION LATCH INSTRUMENTATION DEPLOYMENT (FIXED v2.0)
================================================================================

Extension: $AUGMENT_EXTENSION
Target file: $EXTENSION_JS
Backup file: $BACKUP_FILE
Instrumentation: $INSTRUMENTATION_FILE
Log file: $LOG_FILE

WHAT'S DIFFERENT IN v2.0:
- Uses Module._load hook to intercept class loading
- Wraps constructor to instrument instances at creation time
- Self-executing (no external function calls needed)
- Previous version failed because it never executed instrumentation

WHAT THIS DOES:
- Backs up original extension.js
- Injects FIXED latch instrumentation at top of extension.js
- Captures stack traces when _closingPromise or _cancelledByUser are set
- Logs to $LOG_FILE with full context

EXPECTED RESULTS:
- Initialization: _cancelledByUser = false (once per instance)
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

# WHAT: Remove old instrumentation if present
# WHY: Don't want both old and new instrumentation running
# HOW: Remove old file and old injection from extension.js
echo "🧹 Removing old instrumentation (if present)..."
rm -f "$AUGMENT_EXTENSION/out/instrument-latches.js" 2>/dev/null || true
rm -f "$AUGMENT_EXTENSION/out/instrument-cancelledByUser-latch.js" 2>/dev/null || true
rm -f "$AUGMENT_EXTENSION/out/instrument-closing-promise-prototype.js" 2>/dev/null || true

# WHAT: Create backup of current extension.js
# WHY: User needs ability to rollback if instrumentation causes issues
# HOW: Copy extension.js to timestamped backup file
echo "📦 Creating backup..."
cp "$EXTENSION_JS" "$BACKUP_FILE"
echo "✅ Backup created: $BACKUP_FILE"

# WHAT: Remove old instrumentation injections from extension.js
# WHY: Clean slate for new instrumentation
# HOW: Filter out old require() statements
echo "🧹 Cleaning old injections from extension.js..."
grep -v "require('./instrument-" "$BACKUP_FILE" > "$EXTENSION_JS.tmp" || cp "$BACKUP_FILE" "$EXTENSION_JS.tmp"
mv "$EXTENSION_JS.tmp" "$EXTENSION_JS"

# WHAT: Copy new instrumentation file to extension directory
# WHY: require('./instrument-latches-fixed.js') needs file in same directory
# HOW: Copy to out/ directory where extension.js lives
echo "📦 Copying FIXED instrumentation to extension directory..."
cp "$INSTRUMENTATION_FILE" "$INSTRUMENTATION_DEST"
echo "✅ Instrumentation copied: $INSTRUMENTATION_DEST"

# WHAT: Inject FIXED instrumentation at top of extension.js
# WHY: Instrumentation must load before extension code executes
# HOW: Prepend require() statement to extension.js
echo "🔧 Injecting FIXED instrumentation..."
{
    echo "// LATCH INSTRUMENTATION INJECTED (FIXED v2.0) $(date -Iseconds)"
    echo "// WHAT: Instrument _closingPromise and _cancelledByUser latches (INSTANCE-LEVEL)"
    echo "// WHY: Capture stack traces when latches are set"
    echo "// HOW: Module._load hook + constructor wrapping"
    echo "require('./instrument-latches-fixed.js');"
    echo ""
    cat "$EXTENSION_JS"
} > "$EXTENSION_JS.new"

mv "$EXTENSION_JS.new" "$EXTENSION_JS"

echo "✅ FIXED instrumentation injected successfully"

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
$(grep -c "LATCH INSTRUMENTATION INJECTED (FIXED v2.0)" "$EXTENSION_JS" || echo 0) injection markers
$(grep -c "require('./instrument-latches-fixed.js')" "$EXTENSION_JS" || echo 0) require statements

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
   - Timestamp and process PID
   - Instance creation events

This will provide definitive proof for Augment team showing when/why latch triggers.

================================================================================
"

# WHAT: Clear old log file
# WHY: Start fresh with new instrumentation
# HOW: Remove old log file if it exists
rm -f "$LOG_FILE" 2>/dev/null || true
echo "✅ Old log file cleared"

echo "
🎯 DEPLOYMENT COMPLETE (FIXED v2.0)

Instrumentation is now active. Reload VS Code to activate.

To verify instrumentation is working:
  1. Reload VS Code window
  2. cat $LOG_FILE
  3. Look for [INSTRUMENTATION INITIALIZED - INSTANCE-LEVEL v2.0] message
  4. Look for [INSTRUMENTATION] Instrumented ... instance messages

To rollback:
  cp \"$BACKUP_FILE\" \"$EXTENSION_JS\"
  rm \"$INSTRUMENTATION_DEST\"
"

