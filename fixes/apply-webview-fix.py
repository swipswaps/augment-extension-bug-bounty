#!/usr/bin/env python3
"""
WEBVIEW FIX - Wait for cancelToolRun to complete and return output
Replaces line 44333 to wait for output instead of throwing immediately
"""

import os
import shutil
from datetime import datetime

WEBVIEW_JS = "/home/owner/.vscode/extensions/augment.vscode-augment-0.754.3/common-webviews/assets/extension-client-context-CN64fWtK.js"

print("=== APPLYING WEBVIEW FIX ===\n")

# Step 1: Backup
timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
backup = f"{WEBVIEW_JS}.backup-{timestamp}"
print("Step 1: Creating backup...")
shutil.copy2(WEBVIEW_JS, backup)
print(f"✓ Backup created: {backup}\n")

# Step 2: Read file
print("Step 2: Reading webview JS...")
with open(WEBVIEW_JS, 'r') as f:
    content = f.read()
print(f"✓ Read {len(content)} bytes\n")

# Step 3: Show current code
print("Step 3: Current code (line 44333):")
lines = content.split('\n')
print(f"  44333: {lines[44332][:150]}\n")

# Step 4: Replace the throw with wait-and-return
print("Step 4: Replacing throw with wait-and-return...")

old_code = '                throw yield* w([m, m.cancelToolRun], n, o), new Error("Tool call was cancelled due to timeout")'

new_code = '''                // TIMEOUT FIX: Wait for cancelToolRun to complete and get output
                yield* w([m, m.cancelToolRun], n, o);
                // Wait 500ms for extension to read output
                yield* je(500);
                // Check if we got output from the cancelled process
                const toolState = yield* Ln.effect(n, o);
                if (toolState.result && toolState.result.text) {
                    // Got output - return it
                    return;
                }
                // No output - return diagnostic message
                yield* E(Qs(n, o, {
                    isError: !1,
                    text: "Tool call timed out. Process was terminated. Output may have been captured before termination."
                }));
                return;'''

if old_code in content:
    content = content.replace(old_code, new_code)
    print("✓ Code replaced\n")
else:
    print("✗ FAILED: Old code not found")
    print("Searching for similar pattern...")
    if "throw yield* w([m, m.cancelToolRun]" in content:
        print("Found similar pattern - attempting replacement...")
        # Try to find and replace the actual pattern
        import re
        pattern = r'throw yield\* w\(\[m, m\.cancelToolRun\], n, o\), new Error\("Tool call was cancelled due to timeout"\)'
        if re.search(pattern, content):
            content = re.sub(pattern, new_code.strip(), content)
            print("✓ Pattern replaced using regex\n")
        else:
            print("✗ Pattern not found with regex either")
            exit(1)
    else:
        print("✗ Cannot find any matching pattern")
        exit(1)

# Step 5: Write file
print("Step 5: Writing modified webview JS...")
with open(WEBVIEW_JS, 'w') as f:
    f.write(content)
print("✓ File written\n")

# Step 6: Verify
print("Step 6: Verifying fix...")
with open(WEBVIEW_JS, 'r') as f:
    verify_content = f.read()

if "TIMEOUT FIX: Wait for cancelToolRun" in verify_content and "yield* je(500)" in verify_content:
    print("✓ SUCCESS: Webview now waits for output before returning\n")
    print("=== FIX COMPLETE ===\n")
    print("⚠ RESTART VS CODE for changes to take effect\n")
    print("Test with:")
    print("  /tmp/test-timeout-behavior.sh\n")
    print("Expected result:")
    print("  Lines 1-5 should appear in tool result <output> section")
else:
    print("✗ FAILED: Fix did not apply correctly")
    print("Restoring backup...")
    shutil.copy2(backup, WEBVIEW_JS)
    print("✓ Backup restored")
    exit(1)

