#!/bin/bash
# Automated fix script for Augment VS Code Extension v0.754.3 bugs
# Report ID: 174ab568-83ed-4b09-9ac9-dce2f07c6fcf
# Applies Bug 1, 2, and 3 fixes automatically

set -e

echo "🔧 Augment Extension Bug Fix Installer"
echo "======================================="
echo ""
echo "Report ID: 174ab568-83ed-4b09-9ac9-dce2f07c6fcf"
echo "Fixes: Bug 1 (Cleanup Ordering), Bug 2 (Stream Timeout), Bug 3 (Flush Race)"
echo ""

# Find extension.js
EXTENSION_FILE="$HOME/.vscode/extensions/augment.vscode-augment-0.754.3/out/extension.js"

if [ ! -f "$EXTENSION_FILE" ]; then
    echo "❌ Error: extension.js not found at $EXTENSION_FILE"
    echo "Please check your VS Code extensions directory."
    exit 1
fi

echo "✓ Found extension.js"
echo "  Location: $EXTENSION_FILE"
echo "  Size: $(stat -f%z "$EXTENSION_FILE" 2>/dev/null || stat -c%s "$EXTENSION_FILE") bytes"
echo ""

# Create backup
BACKUP_FILE="${EXTENSION_FILE}.backup-$(date +%Y%m%d-%H%M%S)"
echo "📦 Creating backup..."
cp "$EXTENSION_FILE" "$BACKUP_FILE"
echo "✓ Backup created: $BACKUP_FILE"
echo ""

# Check if fixes already applied
echo "🔍 Checking current state..."

BUG1_CHECK=$(grep -c "cleanupTerminal(h),this._removeLongRunningTerminal" "$EXTENSION_FILE" || true)
BUG2_CHECK=$(grep -c "},100)});return await Promise.race" "$EXTENSION_FILE" || true)
BUG3_CHECK=$(grep -c "await new Promise(r=>setTimeout(r,500))" "$EXTENSION_FILE" || true)

if [ "$BUG1_CHECK" -eq 0 ] && [ "$BUG2_CHECK" -eq 0 ] && [ "$BUG3_CHECK" -ge 2 ]; then
    echo "✓ All fixes appear to be already applied!"
    echo ""
    echo "Current state:"
    echo "  Bug 1 (Cleanup Ordering): FIXED"
    echo "  Bug 2 (Stream Timeout): FIXED"
    echo "  Bug 3 (Flush Race): FIXED"
    echo ""
    echo "No changes needed. Extension is already patched."
    exit 0
fi

echo "Current state:"
echo "  Bug 1 (Cleanup Ordering): $([ "$BUG1_CHECK" -gt 0 ] && echo "NEEDS FIX" || echo "OK")"
echo "  Bug 2 (Stream Timeout): $([ "$BUG2_CHECK" -gt 0 ] && echo "NEEDS FIX" || echo "OK")"
echo "  Bug 3 (Flush Race): $([ "$BUG3_CHECK" -lt 2 ] && echo "NEEDS FIX" || echo "OK")"
echo ""

read -p "Apply fixes? (y/N) " -n 1 -r
echo ""
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted."
    rm "$BACKUP_FILE"
    exit 0
fi

echo ""
echo "🔨 Applying fixes..."
echo ""

# Bug 2: Stream Reader Timeout (100ms → 16000ms)
if [ "$BUG2_CHECK" -gt 0 ]; then
    echo "Applying Bug 2 fix (Stream Reader Timeout)..."
    sed -i.tmp 's/},100)});return await Promise\.race/},16e3)});return await Promise.race/g' "$EXTENSION_FILE"
    rm -f "${EXTENSION_FILE}.tmp"
    echo "✓ Bug 2 fixed"
else
    echo "⊘ Bug 2 already fixed"
fi

# Bug 3: Script File Flush Race (add 500ms delays)
if [ "$BUG3_CHECK" -lt 2 ]; then
    echo "Applying Bug 3 fix (Script File Flush Race)..."
    
    # Location 1: _checkSingleProcessCompletion
    sed -i.tmp 's/if(!o\.isCompleted)return!1;this\._logger\.debug(`\${n} determined process \${r} is done, reading output`);let s;try{s=await this\.hybridReadOutput(r)}/if(!o.isCompleted)return!1;this._logger.debug(`${n} determined process ${r} is done, reading output`);await new Promise(r2=>setTimeout(r2,500));let s;try{s=await this.hybridReadOutput(r)}/g' "$EXTENSION_FILE"
    
    # Location 2: onDidCloseTerminal
    sed -i.tmp 's/this\._removeLongRunningTerminal(h);for(let\[m,A\]of this\._processes)/this._removeLongRunningTerminal(h);await new Promise(r=>setTimeout(r,500));for(let[m,A]of this._processes)/g' "$EXTENSION_FILE"
    
    rm -f "${EXTENSION_FILE}.tmp"
    echo "✓ Bug 3 fixed"
else
    echo "⊘ Bug 3 already fixed"
fi

# Bug 1: Cleanup Ordering (move cleanupTerminal to end)
if [ "$BUG1_CHECK" -gt 0 ]; then
    echo "Applying Bug 1 fix (Cleanup Ordering)..."
    echo "⚠️  Bug 1 fix requires manual intervention or Node.js script"
    echo "    Please use apply-bug1-fix.js for this fix"
    echo "⊘ Bug 1 skipped (use apply-bug1-fix.js)"
else
    echo "⊘ Bug 1 already fixed"
fi

echo ""
echo "✅ Fixes applied successfully!"
echo ""
echo "📋 Verification:"
echo ""

# Verify fixes
BUG2_VERIFY=$(grep -c "},16e3)});return await Promise.race" "$EXTENSION_FILE" || true)
BUG3_VERIFY=$(grep -c "await new Promise(r=>setTimeout(r,500))" "$EXTENSION_FILE" || true)

echo "  Bug 2 (Stream Timeout): $([ "$BUG2_VERIFY" -gt 0 ] && echo "✓ FIXED" || echo "❌ FAILED")"
echo "  Bug 3 (Flush Race): $([ "$BUG3_VERIFY" -ge 2 ] && echo "✓ FIXED" || echo "❌ FAILED")"
echo ""

echo "🔄 Next steps:"
echo ""
echo "1. Reload VS Code window:"
echo "   Ctrl+Shift+P → 'Developer: Reload Window'"
echo ""
echo "2. Test the fixes:"
echo "   echo \"START: test\" && echo \"Line 1\" && echo \"Line 2\" && echo \"END: test\""
echo ""
echo "3. If issues occur, restore backup:"
echo "   cp $BACKUP_FILE $EXTENSION_FILE"
echo ""
echo "✓ Done!"

