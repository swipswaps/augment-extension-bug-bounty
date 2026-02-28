#!/usr/bin/env bash
# Deterministic Patch Script for Augment Extension
# Removes heuristic timeout delays from webview code

set -euo pipefail

EXT=$(ls -d ~/.vscode/extensions/augment.vscode-augment-* | sort -V | tail -1)
WEBVIEW=$(find "$EXT" -name "extension-client-context-*.js" | head -1)

if [ -z "$WEBVIEW" ]; then
    echo "❌ Webview bundle not found."
    exit 1
fi

echo "Target file:"
echo "$WEBVIEW"
echo ""

STAMP=$(date +%F-%H%M%S)
cp "$WEBVIEW" "$WEBVIEW.backup-$STAMP"

echo "✅ Backup created: $WEBVIEW.backup-$STAMP"
echo ""

# Remove heuristic delay
echo "Removing je(500) heuristic delay..."
sed -i 's/je(500)//g' "$WEBVIEW"

# Update timeout message to be accurate
echo "Updating timeout message..."
sed -i 's/Tool call timed out\. Process was terminated\. Output may have been captured before termination\./Tool call timed out before any output was captured./g' "$WEBVIEW"

echo ""
echo "✅ Patch complete."
echo ""
echo "Changes made:"
echo "  1. Removed je(500) heuristic delay"
echo "  2. Updated timeout error message"
echo ""
echo "⚠️  RESTART VS Code for changes to take effect"
echo ""

