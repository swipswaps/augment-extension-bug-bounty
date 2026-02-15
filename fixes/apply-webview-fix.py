#!/usr/bin/env python3
"""
WEBVIEW FIX - CORRECTED VERSION
Uses GS (markToolAsCompleted) instead of Qs (markToolAsError) when output exists

KEY FIXES:
1. Call GS(n, o, toolState.result) when output exists (line 44339)
2. Only call Qs when NO output exists (line 44344)
3. Wait for cancelToolRun to complete before checking state

EVIDENCE:
- Line 10818: GS = S("tools/markToolAsCompleted") ← SUCCESS action
- Line 10819: Qs = S("tools/markToolAsError") ← ERROR action
- Line 44294: Normal flow uses GS for success, Qs for error
"""

import os
import shutil
from datetime import datetime

WEBVIEW_JS = "/home/owner/.vscode/extensions/augment.vscode-augment-0.754.3/common-webviews/assets/extension-client-context-CN64fWtK.js"

print("=== APPLYING CORRECTED WEBVIEW FIX ===\n")
print("CHANGES:")
print("  - Use GS (markToolAsCompleted) when output exists")
print("  - Use Qs (markToolAsError) only when no output")
print("  - Wait for cancelToolRun before checking state\n")

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

# Step 4: Replace the throw with CORRECTED wait-and-return
print("Step 4: Replacing with CORRECTED code (GS for success, Qs for error)...")

old_code = '                throw yield* w([m, m.cancelToolRun], n, o), new Error("Tool call was cancelled due to timeout")'

new_code = '''                // TIMEOUT FIX: Wait for cancelToolRun and dispatch correct action
                yield* w([m, m.cancelToolRun], n, o);
                // Wait 500ms for extension to read output
                yield* je(500);
                // Check if we got output from the cancelled process
                const toolState = yield* Ln.effect(n, o);
                if (toolState.result) {
                    // Got output - use GS (markToolAsCompleted) NOT Qs
                    yield* E(GS(n, o, toolState.result));
                    return;
                }
                // No output - use Qs (markToolAsError)
                yield* E(Qs(n, o, {
                    isError: !0,
                    text: "Tool call timed out. No output was captured."
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

