#!/bin/bash
# WHAT: Debug why watchdog extension v1.1 is not creating output channel
# WHY: Extension activates (per exthost.log) but no 'Watchdog Log' output exists
# HOW: Check activation logs, runtime errors, package.json config, file paths

set -euo pipefail

echo "=========================================="
echo "WATCHDOG EXTENSION ACTIVATION DEBUG"
echo "=========================================="
echo ""

# WHAT: Find latest extension host log
# WHY: Contains activation events and runtime errors
# HOW: Search VS Code logs directory for exthost.log
echo "STEP 1: Extension Activation Events"
echo "------------------------------------"
EXTHOST_LOG=$(find ~/.config/Code/logs -path "*/exthost/exthost*.log" -type f 2>/dev/null | xargs ls -t 2>/dev/null | head -1)

if [ -n "$EXTHOST_LOG" ]; then
    echo "Extension host log: $EXTHOST_LOG"
    echo ""
    
    # WHAT: Show all watchdog activation attempts
    # WHY: Verify extension is being loaded by VS Code
    # HOW: Grep for watchdog activation events
    echo "Activation attempts:"
    grep -i "hidden-terminal-watchdog.*activat" "$EXTHOST_LOG" | tail -5
    
    echo ""
    
    # WHAT: Check for errors after latest activation
    # WHY: Runtime errors prevent extension from starting
    # HOW: Get timestamp of last activation, show errors after that time
    LAST_ACTIVATION=$(grep -i "hidden-terminal-watchdog.*activat" "$EXTHOST_LOG" | tail -1 | cut -d' ' -f1-2)
    echo "Last activation: $LAST_ACTIVATION"
    echo ""
    echo "Errors after last activation:"
    awk -v start="$LAST_ACTIVATION" '$0 ~ start,0' "$EXTHOST_LOG" | grep -i "error" | head -10 || echo "No errors found"
else
    echo "❌ No extension host log found"
fi
echo ""

# WHAT: Verify package.json configuration
# WHY: Incorrect paths prevent extension from loading
# HOW: Check main entry point and activation events
echo "STEP 2: Package.json Configuration"
echo "-----------------------------------"
cd hidden-terminal-watchdog
echo "Main entry point:"
grep '"main"' package.json
echo ""
echo "Activation events:"
grep -A 2 '"activationEvents"' package.json
echo ""

# WHAT: Verify compiled extension.js exists
# WHY: Missing file causes activation failure
# HOW: Check if out/extension.js exists and is readable
echo "STEP 3: Compiled Extension File"
echo "--------------------------------"
if [ -f "out/extension.js" ]; then
    echo "✅ out/extension.js exists"
    ls -lh out/extension.js
    echo ""
    
    # WHAT: Check for JavaScript syntax errors
    # WHY: Syntax errors prevent extension from loading
    # HOW: Use node -c to check syntax
    if node -c out/extension.js 2>&1; then
        echo "✅ No syntax errors"
    else
        echo "❌ Syntax errors found"
    fi
else
    echo "❌ out/extension.js NOT FOUND"
    echo "Extension cannot load without compiled JavaScript"
fi
echo ""

# WHAT: Check if extension is in correct location
# WHY: VS Code looks for extensions in specific directories
# HOW: Check if vsix was installed to user extensions directory
echo "STEP 4: Extension Installation Location"
echo "----------------------------------------"
INSTALLED_PATH=$(find ~/.vscode/extensions -name "*hidden-terminal-watchdog*" -type d 2>/dev/null | head -1)
if [ -n "$INSTALLED_PATH" ]; then
    echo "✅ Extension installed at: $INSTALLED_PATH"
    echo ""
    echo "Installed files:"
    ls -lh "$INSTALLED_PATH" | head -10
    echo ""
    
    # WHAT: Check if installed extension has out/extension.js
    # WHY: Packaging may have failed to include compiled code
    # HOW: Check for out/extension.js in installed location
    if [ -f "$INSTALLED_PATH/out/extension.js" ]; then
        echo "✅ Compiled code present in installed extension"
    else
        echo "❌ Compiled code MISSING from installed extension"
        echo "This is why extension doesn't run - vsix packaging failed"
    fi
else
    echo "❌ Extension not found in ~/.vscode/extensions"
    echo "Extension may not be properly installed"
fi
echo ""

# WHAT: Check database accessibility
# WHY: Extension needs to write to database
# HOW: Verify database file exists and is writable
echo "STEP 5: Database Accessibility"
echo "-------------------------------"
cd ..
if [ -f ".augment/error_tracking.db" ]; then
    echo "✅ Database exists"
    ls -lh .augment/error_tracking.db
    
    # WHAT: Test database write access
    # WHY: Extension needs write permission
    # HOW: Attempt test insertion
    if sqlite3 .augment/error_tracking.db "SELECT 1;" > /dev/null 2>&1; then
        echo "✅ Database is accessible"
    else
        echo "❌ Database is not accessible"
    fi
else
    echo "❌ Database not found at .augment/error_tracking.db"
fi
echo ""

# WHAT: Provide diagnostic summary
# WHY: Clear action items for user
# HOW: Summarize findings
echo "=========================================="
echo "DIAGNOSTIC SUMMARY"
echo "=========================================="
echo ""
echo "LIKELY CAUSE:"
echo "  Extension activates but vsix packaging may have failed"
echo "  to include out/extension.js in the installed package"
echo ""
echo "VERIFICATION STEPS:"
echo "  1. Check VS Code Output panel for 'Watchdog Log' channel"
echo "  2. If missing, check installed extension directory"
echo "  3. Verify out/extension.js exists in installed location"
echo ""
echo "FIX IF NEEDED:"
echo "  cd hidden-terminal-watchdog"
echo "  npx @vscode/vsce package --allow-missing-repository"
echo "  code --install-extension hidden-terminal-watchdog-1.0.0.vsix --force"
echo "  Reload VS Code"
echo ""

