#!/bin/bash
# CORRECTED WEBVIEW FIX
# Changes line 44339-44346 to use GS instead of Qs

WEBVIEW_JS="/home/owner/.vscode/extensions/augment.vscode-augment-0.754.3/common-webviews/assets/extension-client-context-CN64fWtK.js"

echo "=== APPLYING CORRECTED WEBVIEW FIX ==="
echo ""
echo "CHANGES:"
echo "  Line 44339: Remove .text check (just check toolState.result)"
echo "  Line 44340: Call GS(n, o, toolState.result) instead of just return"
echo "  Line 44344: Use GS (markToolAsCompleted) NOT Qs (markToolAsError)"
echo ""

# Backup
BACKUP="${WEBVIEW_JS}.backup-$(date +%Y%m%d-%H%M%S)"
echo "Creating backup: $BACKUP"
cp "$WEBVIEW_JS" "$BACKUP"
echo "✓ Backup created"
echo ""

# Show current code
echo "Current code (lines 44338-44347):"
sed -n '44338,44347p' "$WEBVIEW_JS"
echo ""

# Apply fix using Python for precision
python3 << 'PYTHON_EOF'
import re

WEBVIEW_JS = "/home/owner/.vscode/extensions/augment.vscode-augment-0.754.3/common-webviews/assets/extension-client-context-CN64fWtK.js"

with open(WEBVIEW_JS, 'r') as f:
    content = f.read()

# Replace the buggy code with corrected code
old_pattern = r'''                if \(toolState\.result && toolState\.result\.text\) \{
                    // Got output - return it
                    return;
                \}
                // No output - return diagnostic message
                yield\* E\(Qs\(n, o, \{
                    isError: !1,
                    text: "Tool call timed out\. Process was terminated\. Output may have been captured before termination\."
                \}\)\);'''

new_code = '''                if (toolState.result) {
                    // Got output - use GS (markToolAsCompleted)
                    yield* E(GS(n, o, toolState.result));
                    return;
                }
                // No output - use Qs (markToolAsError)
                yield* E(Qs(n, o, {
                    isError: !0,
                    text: "Tool call timed out. No output was captured."
                }));'''

content = re.sub(old_pattern, new_code, content)

with open(WEBVIEW_JS, 'w') as f:
    f.write(content)

print("✓ Fix applied")
PYTHON_EOF

echo ""
echo "New code (lines 44338-44347):"
sed -n '44338,44347p' "$WEBVIEW_JS"
echo ""

# Verify GS is used
if grep -q "yield\* E(GS(n, o, toolState.result))" "$WEBVIEW_JS"; then
    echo "✓ SUCCESS: Now using GS (markToolAsCompleted) for success"
    echo "✓ SUCCESS: Now using Qs (markToolAsError) only for error"
    echo ""
    echo "⚠ RESTART VS CODE for changes to take effect"
    echo ""
    echo "Test with: /tmp/test-timeout-behavior.sh"
    echo "Expected: Lines 1-5 in tool result <output> section"
else
    echo "✗ FAILED: GS not found in expected location"
    echo "Restoring backup..."
    cp "$BACKUP" "$WEBVIEW_JS"
    echo "✓ Backup restored"
    exit 1
fi

