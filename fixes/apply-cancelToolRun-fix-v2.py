#!/usr/bin/env python3
"""
Fix cancelToolRun to return output when timeout occurs - CORRECTED VERSION

This modifies extension.js to:
1. Store the tool result in _runningTools before completion
2. Return the result from cancelToolRun
3. Update the message handler to include result in response
"""

import sys
from datetime import datetime

EXTENSION_FILE = "/home/owner/.vscode/extensions/augment.vscode-augment-0.754.3/out/extension.js"

def main():
    print("=== APPLYING cancelToolRun FIX (v2 - CORRECTED) ===\n")
    
    # Step 1: Create backup
    print("Step 1: Creating backup...")
    import shutil
    backup_path = f"{EXTENSION_FILE}.backup-{datetime.now().strftime('%Y%m%d-%H%M%S')}"
    shutil.copy2(EXTENSION_FILE, backup_path)
    print(f"✓ Backup created: {backup_path}\n")
    
    # Step 2: Read file
    print("Step 2: Reading extension.js...")
    with open(EXTENSION_FILE, 'r') as f:
        content = f.read()
    lines = content.splitlines(keepends=True)
    print(f"✓ Read {len(lines)} lines\n")
    
    # Step 3: Fix callTool to store result (line 236625)
    print("Step 3: Fixing callTool to store result...")
    
    # Find: "try {\n            return await a.call(i, o, c.signal, r, t, s)\n"
    # Replace with: "try {\n            let result = await a.call(i, o, c.signal, r, t, s);\n            let d = this._runningTools.get(r);\n            if (d) d.result = result;\n            return result;\n"
    
    old_callTool = "        try {\n            return await a.call(i, o, c.signal, r, t, s)\n"
    new_callTool = "        try {\n            let result = await a.call(i, o, c.signal, r, t, s);\n            let d = this._runningTools.get(r);\n            if (d) d.result = result;\n            return result;\n"
    
    if old_callTool in content:
        content = content.replace(old_callTool, new_callTool, 1)
        print("✓ Modified callTool to store result\n")
    else:
        print("✗ FAILED: Could not find callTool pattern")
        sys.exit(1)
    
    # Step 4: Fix cancelToolRun to return result (line 236551)
    print("Step 4: Fixing cancelToolRun to return result...")
    
    # Find: "async cancelToolRun(t, r) {\n        let n = this._runningTools.get(r);\n        return n ? (n.abortController.abort(), await n.completionPromise, !0) : !1\n    }"
    # Replace with expanded version
    
    old_cancelToolRun = "        async cancelToolRun(t, r) {\n            let n = this._runningTools.get(r);\n            return n ? (n.abortController.abort(), await n.completionPromise, !0) : !1\n        }"
    new_cancelToolRun = "        async cancelToolRun(t, r) {\n            let n = this._runningTools.get(r);\n            if (!n) return {success: false};\n            n.abortController.abort();\n            await n.completionPromise;\n            return {success: true, result: n.result || null};\n        }"
    
    if old_cancelToolRun in content:
        content = content.replace(old_cancelToolRun, new_cancelToolRun, 1)
        print("✓ Modified cancelToolRun to return result\n")
    else:
        print("✗ FAILED: Could not find cancelToolRun pattern")
        sys.exit(1)
    
    # Step 5: Fix message handler to include result (line 272355)
    print("Step 5: Fixing message handler to include result...")
    
    # Find: "cancelToolRun = async r => (await this._toolsModel.cancelToolRun(r.data.requestId, r.data.toolUseId), {\n            type: \"cancel-tool-run-response\"\n        });"
    # Replace with expanded version
    
    old_handler = "cancelToolRun = async r => (await this._toolsModel.cancelToolRun(r.data.requestId, r.data.toolUseId), {\n            type: \"cancel-tool-run-response\"\n        });"
    new_handler = "cancelToolRun = async r => {\n            let result = await this._toolsModel.cancelToolRun(r.data.requestId, r.data.toolUseId);\n            return {\n                type: \"cancel-tool-run-response\",\n                result: result?.result || null\n            };\n        };"
    
    if old_handler in content:
        content = content.replace(old_handler, new_handler, 1)
        print("✓ Modified message handler to include result\n")
    else:
        print("✗ FAILED: Could not find message handler pattern")
        sys.exit(1)
    
    # Step 6: Write file
    print("Step 6: Writing modified extension.js...")
    with open(EXTENSION_FILE, 'w') as f:
        f.write(content)
    print("✓ File written\n")
    
    print("=== FIX COMPLETE ===\n")
    print("⚠ RESTART VS CODE for changes to take effect\n")
    print("Test with:")
    print("  /tmp/test-timeout-behavior.sh\n")
    print("Expected result:")
    print("  Lines 1-5 should appear in tool result <output> section")

if __name__ == "__main__":
    main()

