#!/usr/bin/env bash
#
# Remove Resource Guardian Extension Completely
#
# PURPOSE:
# - Extension still showing popups despite being "disabled"
# - VS Code loading extension from symlink even with .DISABLED suffix
# - Need to REMOVE symlink completely, not just rename
#
# ROOT CAUSE:
# - Symlink: ~/.vscode/extensions/resource-guardian.vscode-resource-guardian-1.0.0.DISABLED
# - VS Code ignores .DISABLED suffix on symlinks
# - Extension still active, still showing popups
# - User cannot work (constant popups)
#
# SOLUTION:
# - Remove symlink completely
# - Reload VS Code
# - Extension will be gone

set -euo pipefail

echo "================================================================================"
echo "REMOVE RESOURCE GUARDIAN EXTENSION COMPLETELY"
echo "================================================================================"
echo ""

# Step 1: Remove symlink
echo "🗑️  Step 1: Removing extension symlink..."
EXTENSION_SYMLINK="$HOME/.vscode/extensions/resource-guardian.vscode-resource-guardian-1.0.0.DISABLED"

if [ -L "$EXTENSION_SYMLINK" ]; then
    rm -f "$EXTENSION_SYMLINK"
    echo "  ✓ Symlink removed: $EXTENSION_SYMLINK"
elif [ -e "$EXTENSION_SYMLINK" ]; then
    rm -rf "$EXTENSION_SYMLINK"
    echo "  ✓ Directory removed: $EXTENSION_SYMLINK"
else
    echo "  ℹ️  Extension not found (already removed)"
fi

echo ""

# Step 2: Verify removal
echo "🔍 Step 2: Verifying removal..."
REMAINING=$(ls -la ~/.vscode/extensions/ | grep -i resource || true)

if [ -z "$REMAINING" ]; then
    echo "  ✓ No Resource Guardian extension found"
else
    echo "  ⚠️  Still found:"
    echo "$REMAINING"
fi

echo ""

# Step 3: Show current system state
echo "📊 Step 3: Current system state..."
free -h | head -2
echo ""
uptime
echo ""

echo "================================================================================"
echo "✅ RESOURCE GUARDIAN REMOVED"
echo "================================================================================"
echo ""
echo "NEXT STEPS:"
echo "  1. Reload VS Code: Ctrl+Shift+P → 'Reload Window'"
echo "  2. Popups should STOP appearing"
echo "  3. Let VS Code stabilize for 2 minutes"
echo "  4. Monitor: watch -n 5 'free -h && uptime'"
echo ""
echo "IF POPUPS CONTINUE:"
echo "  - Check VS Code extensions: Ctrl+Shift+X"
echo "  - Look for 'Resource Guardian' in list"
echo "  - Uninstall if present"
echo ""

