#!/usr/bin/env python3
"""
Fix cancelToolRun to return output when timeout occurs.

This modifies extension.js to:
1. Store the tool result in _runningTools before completion
2. Return the result from cancelToolRun
3. Update the message handler to include result in response
"""

import sys
from datetime import datetime

EXTENSION_FILE = "/home/owner/.vscode/extensions/augment.vscode-augment-0.754.3/out/extension.js"

def main():
    print("=== APPLYING cancelToolRun FIX ===\n")
    
    # Step 1: Create backup
    print("Step 1: Creating backup...")
    import shutil
    backup_path = f"{EXTENSION_FILE}.backup-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
    shutil.copy2(EXTENSION_FILE, backup_path)
    print(f"✓ Backup created: {backup_path}\n")
    
    # Step 2: Read file
    print("Step 2: Reading extension.js...")
    with open(EXTENSION_FILE, 'r') as f:
        lines = f.readlines()
    print(f"✓ Read {len(lines)} lines\n")
    
    # Step 3: Fix callTool to store result (lines 236600-236625)
    print("Step 3: Fixing callTool to store result...")
    
    # Find the line: "try {"
    # Replace the try-finally block to store result
    
    # Original (line 236615-236625):
    #     try {
    #         return await a.call(i, o, c.signal, r, t, s)
    #     } finally {
    #         let d = this._runningTools.get(r);
    #         d && (d.resolveCompletion(), this._runningTools.delete(r))
    #     }
    
    # New:
    #     try {
    #         let result = await a.call(i, o, c.signal, r, t, s);
    #         let d = this._runningTools.get(r);
    #         if (d) d.result = result;
    #         return result;
    #     } finally {
    #         let d = this._runningTools.get(r);
    #         d && (d.resolveCompletion(), this._runningTools.delete(r))
    #     }
    
    # Line 236625 is index 236624 (0-based)
    if lines[236624].strip() == "try {":
        # Replace line 236626: "return await a.call(i, o, c.signal, r, t, s)"
        # with four lines
        indent = "            "
        lines[236625] = f"{indent}let result = await a.call(i, o, c.signal, r, t, s);\n"
        lines.insert(236626, f"{indent}let d = this._runningTools.get(r);\n")
        lines.insert(236627, f"{indent}if (d) d.result = result;\n")
        lines.insert(236628, f"{indent}return result;\n")
        print("✓ Modified callTool to store result\n")
    else:
        print(f"✗ FAILED: Line 236625 is not 'try {{', it's: {lines[236624].strip()}")
        sys.exit(1)
    
    # Step 4: Fix cancelToolRun to return result (lines 236551-236554, now shifted by 3)
    print("Step 4: Fixing cancelToolRun to return result...")

    # Original (line 236551-236554):
    #     async cancelToolRun(t, r) {
    #         let n = this._runningTools.get(r);
    #         return n ? (n.abortController.abort(), await n.completionPromise, !0) : !1
    #     }

    # New:
    #     async cancelToolRun(t, r) {
    #         let n = this._runningTools.get(r);
    #         if (!n) return {success: false};
    #         n.abortController.abort();
    #         await n.completionPromise;
    #         return {success: true, result: n.result || null};
    #     }

    # Original line 236551 is index 236550 (0-based)
    # After inserting 3 lines above, it's now at 236550 + 3 = 236553
    # But wait - we inserted at 236626-236628, which is AFTER 236551
    # So cancelToolRun is still at 236550!
    target_line = 236550  # No shift because we inserted AFTER this line
    if "async cancelToolRun(t, r) {" in lines[target_line]:
        # Line 236552 (now 236555) has: "let n = this._runningTools.get(r);"
        # Line 236553 (now 236556) has: "return n ? (n.abortController.abort(), await n.completionPromise, !0) : !1"
        indent = "        "
        # Keep line target_line + 1 (let n = ...)
        # Replace line target_line + 2 with expanded version
        lines[target_line + 2] = f"{indent}if (!n) return {{success: false}};\n"
        lines.insert(target_line + 3, f"{indent}n.abortController.abort();\n")
        lines.insert(target_line + 4, f"{indent}await n.completionPromise;\n")
        lines.insert(target_line + 5, f"{indent}return {{success: true, result: n.result || null}};\n")
        print("✓ Modified cancelToolRun to return result\n")
    else:
        print(f"✗ FAILED: Line {target_line} doesn't contain 'async cancelToolRun', it's: {lines[target_line].strip()}")
        sys.exit(1)
    
    # Step 5: Fix message handler to include result (line 272355, now shifted by 7)
    print("Step 5: Fixing message handler to include result...")
    
    # Original (line 272355-272357):
    #     cancelToolRun = async r => (await this._toolsModel.cancelToolRun(r.data.requestId, r.data.toolUseId), {
    #         type: "cancel-tool-run-response"
    #     });
    
    # New:
    #     cancelToolRun = async r => {
    #         let result = await this._toolsModel.cancelToolRun(r.data.requestId, r.data.toolUseId);
    #         return {
    #             type: "cancel-tool-run-response",
    #             result: result?.result || null
    #         };
    #     };
    
    # Line 272355 is index 272354
    # We inserted 3 lines at 236626-236628 (before this)
    # We inserted 3 lines at 236552-236554 (before this)
    # Total shift: 3 + 3 = 6
    target_line = 272354 + 6  # = 272360
    if "cancelToolRun = async r =>" in lines[target_line]:
        indent = "        "
        lines[target_line] = f"{indent}cancelToolRun = async r => {{\n"
        lines[target_line + 1] = f"{indent}    let result = await this._toolsModel.cancelToolRun(r.data.requestId, r.data.toolUseId);\n"
        lines[target_line + 2] = f"{indent}    return {{\n"
        lines.insert(target_line + 3, f"{indent}        type: \"cancel-tool-run-response\",\n")
        lines.insert(target_line + 4, f"{indent}        result: result?.result || null\n")
        lines.insert(target_line + 5, f"{indent}    }};\n")
        lines.insert(target_line + 6, f"{indent}}};\n")
        # Remove old lines (now at target_line + 7, 8)
        del lines[target_line + 7:target_line + 9]
        print("✓ Modified message handler to include result\n")
    else:
        print(f"✗ FAILED: Line {target_line} doesn't contain 'cancelToolRun = async r =>', it's: {lines[target_line].strip()}")
        sys.exit(1)
    
    # Step 6: Write file
    print("Step 6: Writing modified extension.js...")
    with open(EXTENSION_FILE, 'w') as f:
        f.writelines(lines)
    print("✓ File written\n")
    
    print("=== FIX COMPLETE ===\n")
    print("⚠ RESTART VS CODE for changes to take effect\n")
    print("Test with:")
    print("  /tmp/test-timeout-behavior.sh\n")
    print("Expected result:")
    print("  Lines 1-5 should appear in tool result <output> section")

if __name__ == "__main__":
    main()

