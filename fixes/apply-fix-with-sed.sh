#!/bin/bash
# ACTUAL FIX - Read output BEFORE sending Ctrl+C
# This uses sed to modify the minified extension.js

set -e

EXTENSION_JS="/home/owner/.vscode/extensions/augment.vscode-augment-0.754.3/out/extension.js"

echo "=== APPLYING EXTENSION.JS FIX ==="
echo ""

# Backup
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP="${EXTENSION_JS}.backup-${TIMESTAMP}"
echo "Step 1: Creating backup..."
cp "$EXTENSION_JS" "$BACKUP"
echo "✓ Backup created: $BACKUP"
echo ""

# Show current code
echo "Step 2: Current code (line 259682-259684):"
sed -n '259682,259684p' "$EXTENSION_JS"
echo ""

# Apply fix - Read output BEFORE killing
echo "Step 3: Applying fix (read output before kill)..."

# The fix: Move line 259683 (hybridReadOutput) to BEFORE line 259682 (sendText)
# Current order:
#   259682: sendText("\u0003") - KILL
#   259683: let o = await this.hybridReadOutput(r); - READ
# New order:
#   259682: let o = await this.hybridReadOutput(r); - READ FIRST
#   259683: sendText("\u0003") - KILL AFTER

# Use sed to swap the lines
sed -i '259682 {
    # Read the kill line into hold space
    h
    # Read the next line (hybridReadOutput)
    n
    # Print it first
    p
    # Get the kill line from hold space
    g
    # Print it second
}' "$EXTENSION_JS"

echo "✓ Fix applied"
echo ""

# Verify
echo "Step 4: Verifying fix..."
echo "New code (line 259682-259684):"
sed -n '259682,259684p' "$EXTENSION_JS"
echo ""

# Check if hybridReadOutput is now BEFORE sendText
if sed -n '259682p' "$EXTENSION_JS" | grep -q "hybridReadOutput"; then
    echo "✓ SUCCESS: hybridReadOutput is now on line 259682 (BEFORE kill)"
    echo "✓ Output will be captured before process is killed"
    echo ""
    echo "=== FIX COMPLETE ==="
    echo ""
    echo "⚠ RESTART VS CODE for changes to take effect"
    echo ""
    echo "Test with:"
    echo "  /tmp/test-timeout-behavior.sh"
    echo ""
    echo "Expected result:"
    echo "  Lines 1-5 should appear in tool result <output> section"
    exit 0
else
    echo "✗ FAILED: Fix did not apply correctly"
    echo "Restoring backup..."
    cp "$BACKUP" "$EXTENSION_JS"
    echo "✓ Backup restored"
    exit 1
fi

