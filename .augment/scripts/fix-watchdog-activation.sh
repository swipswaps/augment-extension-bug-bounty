#!/bin/bash
# WHAT: Fix watchdog extension activation issue
# WHY: Extension activates but activate() function doesn't execute (no logs, no output channel)
# HOW: Add try-catch to activate(), add console.log for debugging, recompile and reinstall

set -euo pipefail

echo "=========================================="
echo "FIX WATCHDOG EXTENSION ACTIVATION"
echo "=========================================="
echo ""

# WHAT: Navigate to extension directory
# WHY: Need to modify source code
# HOW: cd to hidden-terminal-watchdog
cd /home/owner/Documents/6984bd27-4494-8330-9803-7b6895a48aa5/hidden-terminal-watchdog

# WHAT: Add try-catch and console.log to activate() function
# WHY: Silent failures prevent debugging, need to see errors
# HOW: Wrap activate() body in try-catch, add console.log statements
echo "STEP 1: Add error handling to activate() function"
echo "--------------------------------------------------"

# WHAT: Create backup of original file
# WHY: Allow rollback if changes break extension
# HOW: Copy src/extension.ts to src/extension.ts.backup
cp src/extension.ts src/extension.ts.backup
echo "✅ Backup created: src/extension.ts.backup"
echo ""

# WHAT: Modify activate() function to add try-catch
# WHY: Catch and log any errors that prevent extension from running
# HOW: Use sed to wrap function body in try-catch block
echo "STEP 2: Wrap activate() in try-catch"
echo "-------------------------------------"

# WHAT: Show current activate() function start
# WHY: Verify we're modifying the right function
# HOW: Display first 10 lines of activate()
echo "Current activate() function:"
sed -n '122,132p' src/extension.ts
echo ""

# WHAT: Add console.log at start of activate()
# WHY: Verify activate() is being called by VS Code
# HOW: Insert console.log after function declaration
sed -i '123 a\    console.log("[WATCHDOG] activate() function called");' src/extension.ts
echo "✅ Added console.log to activate()"
echo ""

# WHAT: Wrap log() calls in try-catch
# WHY: log() might be failing silently
# HOW: Add try-catch around first log() call
sed -i '124 a\    try {' src/extension.ts
sed -i '126 a\    } catch (err) {\n        console.error("[WATCHDOG] Failed to call log():", err);\n    }' src/extension.ts
echo "✅ Added try-catch around log() call"
echo ""

echo "STEP 3: Recompile extension"
echo "----------------------------"
# WHAT: Compile TypeScript to JavaScript
# WHY: Changes in .ts files don't take effect until compiled
# HOW: Run npm run compile
npm run compile
echo ""

echo "STEP 4: Package extension"
echo "--------------------------"
# WHAT: Create .vsix package file
# WHY: VS Code installs from .vsix files
# HOW: Run vsce package
npx @vscode/vsce package --allow-missing-repository
echo ""

echo "STEP 5: Install extension"
echo "--------------------------"
# WHAT: Install packaged extension to VS Code
# WHY: Replace old version with new version
# HOW: Use code --install-extension with --force flag
VSIX_FILE=$(ls -t *.vsix | head -1)
code --install-extension "$VSIX_FILE" --force
echo ""
echo "✅ Extension installed: $VSIX_FILE"
echo ""

echo "=========================================="
echo "FIX APPLIED"
echo "=========================================="
echo ""
echo "CHANGES MADE:"
echo "  1. Added console.log at start of activate()"
echo "  2. Added try-catch around log() call"
echo "  3. Recompiled extension"
echo "  4. Reinstalled extension"
echo ""
echo "NEXT STEPS:"
echo "  1. Reload VS Code: Ctrl+Shift+P → 'Developer: Reload Window'"
echo "  2. Check extension host log for console.log messages:"
echo "     grep 'WATCHDOG' ~/.config/Code/logs/*/exthost/exthost.log"
echo "  3. If errors appear, they will show root cause"
echo ""
echo "VERIFICATION:"
echo "  - Check VS Code Output panel for 'Watchdog Log' channel"
echo "  - Check terminal for watchdog messages"
echo "  - Check database for watchdog entries"
echo ""

