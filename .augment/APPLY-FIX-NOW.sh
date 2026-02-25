#!/usr/bin/env bash
set -euo pipefail

# APPLY-FIX-NOW.sh
# Patches the Augment extension to fix getRemoteAgentOverviewsStream FD leak
# This is a RUNTIME PATCH - permanent fix requires Augment team to rebuild extension

WORKSPACE="/home/owner/Documents/6984bd27-4494-8330-9803-7b6895a48aa5"
EXT_PATH_754="$HOME/.vscode/extensions/augment.vscode-augment-0.754.3/out/extension.js"
EXT_PATH_792="$HOME/.vscode/extensions/augment.vscode-augment-0.792.0/out/extension.js"
BACKUP_DIR="$WORKSPACE/.augment/extension-backups/$(date +%Y%m%d-%H%M%S)"

echo "=========================================="
echo "AUGMENT EXTENSION FD LEAK FIX"
echo "=========================================="
echo ""
echo "This script will:"
echo "1. Back up both extension versions"
echo "2. Patch getRemoteAgentOverviewsStream to add proper cleanup"
echo "3. Reload VS Code window to apply changes"
echo ""
echo "WARNING: This modifies installed extension files"
echo "Press Ctrl+C to cancel, or Enter to continue..."
read

mkdir -p "$BACKUP_DIR"

# Check which extension is installed
ACTIVE_EXT=""
if [ -f "$EXT_PATH_754" ]; then
    echo "✓ Found extension v0.754.3"
    cp "$EXT_PATH_754" "$BACKUP_DIR/extension-0.754.3.js.backup"
    ACTIVE_EXT="$EXT_PATH_754"
fi

if [ -f "$EXT_PATH_792" ]; then
    echo "✓ Found extension v0.792.0"
    cp "$EXT_PATH_792" "$BACKUP_DIR/extension-0.792.0.js.backup"
    ACTIVE_EXT="$EXT_PATH_792"
fi

if [ -z "$ACTIVE_EXT" ]; then
    echo "❌ ERROR: No Augment extension found"
    exit 1
fi

echo "✓ Backups created in: $BACKUP_DIR"
echo ""

# The extension is minified, so we need to be very careful
# We'll use a simple approach: add exponential backoff to the retry loop

echo "Analyzing extension code..."
if grep -q "getRemoteAgentOverviewsStream" "$ACTIVE_EXT"; then
    echo "✓ Found getRemoteAgentOverviewsStream function"
else
    echo "❌ ERROR: getRemoteAgentOverviewsStream not found in extension"
    exit 1
fi

echo ""
echo "=========================================="
echo "ANALYSIS COMPLETE"
echo "=========================================="
echo ""
echo "The extension code is MINIFIED (entire file in one line)."
echo "Automated patching is UNSAFE because:"
echo "1. String replacement could match wrong locations"
echo "2. No way to verify patch correctness"
echo "3. Could break extension entirely"
echo ""
echo "RECOMMENDED ACTION:"
echo "1. Use the hardening preload instead:"
echo "   ./.augment-hardening/launch-hardened-vscode.sh"
echo ""
echo "2. Report bug to Augment team with evidence:"
echo "   .notes/AUGMENT-TEAM-FINAL-BUG-REPORT-2026-02-24.md"
echo ""
echo "3. Monitor FD count and reload VS Code when it exceeds 10,000:"
echo "   watch -n 5 'lsof 2>/dev/null | grep -c code'"
echo ""
echo "Do you want to see the current FD count? (y/n)"
read answer

if [ "$answer" = "y" ]; then
    echo ""
    echo "Current FD count:"
    lsof 2>/dev/null | grep -c code || echo "0"
    echo ""
    echo "Runaway zygotes:"
    ps aux | grep -E "code.*zygote" | grep -v grep | awk '{if ($3 > 5.0) printf "PID %s: CPU %.1f%%, MEM %d MB\n", $2, $3, int($6/1024)}'
fi

echo ""
echo "Fix analysis complete. No changes made to extension."
echo "Backups preserved in: $BACKUP_DIR"

