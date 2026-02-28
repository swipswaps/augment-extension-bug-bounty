#!/usr/bin/env bash
###############################################################################
# RESTORE ORIGINAL EXTENSION.JS - ROLLBACK INSTRUMENTATION
#
# PURPOSE:
#   Restore the original Augment extension.js from backup
#   Remove ALL instrumentation files (old and new versions)
#   Provide verification that restoration succeeded
#
# REQUIREMENTS SATISFIED:
#   2.1 ✅ Restore original extension.js from backup
#   2.2 ✅ Remove instrumentation files
#   2.3 ✅ Provide verification
#   2.4 ✅ Complete executable Bash script, safe to run multiple times
#
# USAGE:
#   ./restore-original-extension.sh
#
# SAFETY:
#   - Idempotent (safe to run multiple times)
#   - Verifies backup exists before restoring
#   - Shows file sizes before/after
#   - Provides clear success/failure messages
#
###############################################################################

set -euo pipefail  # Exit on error, undefined variables, pipe failures

# COLORS FOR OUTPUT
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# STEP 1: Auto-detect Augment extension path
echo -e "${YELLOW}[STEP 1]${NC} Auto-detecting Augment extension path..."

EXTENSION_DIR=$(find ~/.vscode/extensions -maxdepth 1 -type d -name "augment.vscode-augment-*" | sort -V | tail -1)

if [ -z "$EXTENSION_DIR" ]; then
  echo -e "${RED}[ERROR]${NC} Augment extension not found in ~/.vscode/extensions"
  exit 1
fi

EXTENSION_JS="$EXTENSION_DIR/out/extension.js"
BACKUP_FILE="$EXTENSION_DIR/out/extension.js.backup"

echo -e "${GREEN}[STEP 1]${NC} ✅ Found extension: $EXTENSION_JS"

# STEP 2: Verify backup exists
echo -e "${YELLOW}[STEP 2]${NC} Verifying backup exists..."

if [ ! -f "$BACKUP_FILE" ]; then
  echo -e "${RED}[ERROR]${NC} Backup file not found: $BACKUP_FILE"
  echo -e "${RED}[ERROR]${NC} Cannot restore without backup!"
  exit 1
fi

BACKUP_SIZE=$(stat -c%s "$BACKUP_FILE" 2>/dev/null || stat -f%z "$BACKUP_FILE" 2>/dev/null)
echo -e "${GREEN}[STEP 2]${NC} ✅ Backup exists: $BACKUP_FILE (${BACKUP_SIZE} bytes)"

# STEP 3: Show current extension.js state
echo -e "${YELLOW}[STEP 3]${NC} Checking current extension.js state..."

if [ -f "$EXTENSION_JS" ]; then
  CURRENT_SIZE=$(stat -c%s "$EXTENSION_JS" 2>/dev/null || stat -f%z "$EXTENSION_JS" 2>/dev/null)
  echo -e "${YELLOW}[INFO]${NC} Current extension.js size: ${CURRENT_SIZE} bytes"
  
  # Check if instrumentation is present
  if head -1 "$EXTENSION_JS" | grep -q "require.*instrument"; then
    echo -e "${YELLOW}[INFO]${NC} Instrumentation detected in extension.js (first line contains require)"
  else
    echo -e "${YELLOW}[INFO]${NC} No instrumentation detected in extension.js"
  fi
else
  echo -e "${YELLOW}[INFO]${NC} extension.js does not exist (will be created from backup)"
fi

# STEP 4: Restore original extension.js from backup
echo -e "${YELLOW}[STEP 4]${NC} Restoring original extension.js from backup..."

cp "$BACKUP_FILE" "$EXTENSION_JS"

RESTORED_SIZE=$(stat -c%s "$EXTENSION_JS" 2>/dev/null || stat -f%z "$EXTENSION_JS" 2>/dev/null)
echo -e "${GREEN}[STEP 4]${NC} ✅ Restored extension.js (${RESTORED_SIZE} bytes)"

# STEP 5: Remove instrumentation files
echo -e "${YELLOW}[STEP 5]${NC} Removing instrumentation files..."

# Remove old instrumentation (global patching version)
if [ -f "$EXTENSION_DIR/out/instrument-closing-promise.js" ]; then
  rm -f "$EXTENSION_DIR/out/instrument-closing-promise.js"
  echo -e "${GREEN}[STEP 5]${NC} ✅ Removed: instrument-closing-promise.js (old version)"
else
  echo -e "${YELLOW}[STEP 5]${NC} ⚠️  instrument-closing-promise.js not found (already removed)"
fi

# Remove new instrumentation (prototype patching version)
if [ -f "$EXTENSION_DIR/out/instrument-closing-promise-prototype.js" ]; then
  rm -f "$EXTENSION_DIR/out/instrument-closing-promise-prototype.js"
  echo -e "${GREEN}[STEP 5]${NC} ✅ Removed: instrument-closing-promise-prototype.js (new version)"
else
  echo -e "${YELLOW}[STEP 5]${NC} ⚠️  instrument-closing-promise-prototype.js not found (already removed)"
fi

# STEP 6: Verification
echo -e "${YELLOW}[STEP 6]${NC} Verifying restoration..."

# Check first line of extension.js
FIRST_LINE=$(head -1 "$EXTENSION_JS")
if echo "$FIRST_LINE" | grep -q "require.*instrument"; then
  echo -e "${RED}[ERROR]${NC} Restoration failed - instrumentation still present in extension.js"
  echo -e "${RED}[ERROR]${NC} First line: $FIRST_LINE"
  exit 1
else
  echo -e "${GREEN}[STEP 6]${NC} ✅ Verification passed - no instrumentation in extension.js"
  echo -e "${GREEN}[STEP 6]${NC} First line: ${FIRST_LINE:0:80}..."
fi

# STEP 7: Final summary
echo ""
echo -e "${GREEN}=================================================================================${NC}"
echo -e "${GREEN}RESTORATION COMPLETE${NC}"
echo -e "${GREEN}=================================================================================${NC}"
echo -e "Extension path: $EXTENSION_JS"
echo -e "Backup used: $BACKUP_FILE"
echo -e "Original size: ${BACKUP_SIZE} bytes"
echo -e "Restored size: ${RESTORED_SIZE} bytes"
echo -e "Instrumentation files removed: ✅"
echo -e "${GREEN}=================================================================================${NC}"
echo ""
echo -e "${YELLOW}NEXT STEP:${NC} Reload VS Code window to activate the restored extension"
echo -e "${YELLOW}HOW:${NC} Press Ctrl+Shift+P → Type 'Developer: Reload Window' → Press Enter"
echo ""

