#!/usr/bin/env bash
# Patch Active Augment Extension Version
# Works for both release and pre-release versions

set -euo pipefail

echo "╔════════════════════════════════════════════════════════════════════════════╗"
echo "║                    PATCH ACTIVE AUGMENT VERSION                            ║"
echo "╚════════════════════════════════════════════════════════════════════════════╝"
echo ""

# Detect active version
ACTIVE_VERSION=$(code --list-extensions --show-versions | grep augment | cut -d'@' -f2)
EXT_DIR="$HOME/.vscode/extensions/augment.vscode-augment-$ACTIVE_VERSION"

echo "Active version: $ACTIVE_VERSION"
echo "Extension directory: $EXT_DIR"
echo ""

if [ ! -d "$EXT_DIR" ]; then
    echo "❌ Extension directory not found"
    exit 1
fi

# Find webview bundle
WEBVIEW=$(find "$EXT_DIR/common-webviews" -name "extension-client-context-*.js" 2>/dev/null | head -1)

if [ -z "$WEBVIEW" ]; then
    echo "❌ Webview bundle not found"
    exit 1
fi

echo "Target file: $WEBVIEW"
echo ""

# Check if already patched
if ! grep -q "je(500)" "$WEBVIEW" 2>/dev/null; then
    echo "✅ Already patched (je(500) not found)"
    exit 0
fi

# Create backup
STAMP=$(date +%F-%H%M%S)
BACKUP="$WEBVIEW.backup-$STAMP"
cp "$WEBVIEW" "$BACKUP"
echo "✅ Backup created: $BACKUP"
echo ""

# Apply patch
echo "Applying patch..."
sed -i 's/je(500)//g' "$WEBVIEW"
sed -i 's/Tool call timed out\. Process was terminated\. Output may have been captured before termination\./Tool call timed out before any output was captured./g' "$WEBVIEW"

# Verify patch
if grep -q "je(500)" "$WEBVIEW" 2>/dev/null; then
    echo "❌ Patch failed - je(500) still present"
    echo "Restoring backup..."
    cp "$BACKUP" "$WEBVIEW"
    exit 1
fi

echo "✅ Patch applied successfully"
echo ""
echo "Changes made:"
echo "  1. Removed je(500) heuristic delay"
echo "  2. Updated timeout error message"
echo ""
echo "⚠️  RESTART VS Code for changes to take effect"

