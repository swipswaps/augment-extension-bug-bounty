#!/usr/bin/env python3
"""
ACTUAL FIX - Read output BEFORE sending Ctrl+C
Swaps lines 259682 and 259683 in extension.js
"""

import os
import shutil
from datetime import datetime

EXTENSION_JS = "/home/owner/.vscode/extensions/augment.vscode-augment-0.754.3/out/extension.js"

print("=== APPLYING EXTENSION.JS FIX ===\n")

# Step 1: Backup
timestamp = datetime.now().strftime("%Y%m%d-%H%M%S")
backup = f"{EXTENSION_JS}.backup-{timestamp}"
print("Step 1: Creating backup...")
shutil.copy2(EXTENSION_JS, backup)
print(f"✓ Backup created: {backup}\n")

# Step 2: Read file
print("Step 2: Reading extension.js...")
with open(EXTENSION_JS, 'r') as f:
    lines = f.readlines()
print(f"✓ Read {len(lines)} lines\n")

# Step 3: Show current code
print("Step 3: Current code (lines 259682-259684):")
print(f"  259682: {lines[259681][:100]}...")
print(f"  259683: {lines[259682][:100]}...")
print(f"  259684: {lines[259683][:100]}...\n")

# Step 4: Swap lines 259682 and 259683
print("Step 4: Swapping lines (read output BEFORE kill)...")
lines[259681], lines[259682] = lines[259682], lines[259681]
print("✓ Lines swapped\n")

# Step 5: Write file
print("Step 5: Writing modified extension.js...")
with open(EXTENSION_JS, 'w') as f:
    f.writelines(lines)
print("✓ File written\n")

# Step 6: Verify
print("Step 6: Verifying fix...")
with open(EXTENSION_JS, 'r') as f:
    verify_lines = f.readlines()

print("New code (lines 259682-259684):")
print(f"  259682: {verify_lines[259681][:100]}...")
print(f"  259683: {verify_lines[259682][:100]}...")
print(f"  259684: {verify_lines[259683][:100]}...\n")

# Check if hybridReadOutput is now BEFORE sendText
if "hybridReadOutput" in verify_lines[259681]:
    print("✓ SUCCESS: hybridReadOutput is now on line 259682 (BEFORE kill)")
    print("✓ Output will be captured before process is killed\n")
    print("=== FIX COMPLETE ===\n")
    print("⚠ RESTART VS CODE for changes to take effect\n")
    print("Test with:")
    print("  /tmp/test-timeout-behavior.sh\n")
    print("Expected result:")
    print("  Lines 1-5 should appear in tool result <output> section")
else:
    print("✗ FAILED: Fix did not apply correctly")
    print("Restoring backup...")
    shutil.copy2(backup, EXTENSION_JS)
    print("✓ Backup restored")
    exit(1)

