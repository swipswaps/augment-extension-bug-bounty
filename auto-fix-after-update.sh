#!/usr/bin/env bash
# Auto-fix script that detects extension architecture and applies appropriate fixes
# Works after VS Code updates that wipe out manual patches

set -euo pipefail

echo "╔════════════════════════════════════════════════════════════════════════════════╗"
echo "║                    AUTO-FIX AFTER VS CODE UPDATE                               ║"
echo "║                                                                                ║"
echo "║  Detects extension architecture and applies fixes to restore output reading   ║"
echo "║  functionality after VS Code updates.                                         ║"
echo "╚════════════════════════════════════════════════════════════════════════════════╝"
echo ""

# Find Augment extension
AUGMENT_EXT=$(find ~/.vscode/extensions -maxdepth 1 -type d -name "augment.vscode-augment-*" | head -1)

if [ -z "$AUGMENT_EXT" ]; then
    echo "❌ ERROR: Augment extension not found"
    exit 1
fi

EXTENSION_JS="$AUGMENT_EXT/out/extension.js"

if [ ! -f "$EXTENSION_JS" ]; then
    echo "❌ ERROR: extension.js not found at $EXTENSION_JS"
    exit 1
fi

echo "📦 Extension: $(basename "$AUGMENT_EXT")"
echo "📄 File: $EXTENSION_JS"
echo ""

# Detect architecture
LINE_COUNT=$(wc -l < "$EXTENSION_JS")
FILE_SIZE=$(stat -f%z "$EXTENSION_JS" 2>/dev/null || stat -c%s "$EXTENSION_JS" 2>/dev/null)

echo "📊 Analysis:"
echo "   Lines: $LINE_COUNT"
echo "   Size: $(numfmt --to=iec-i --suffix=B $FILE_SIZE 2>/dev/null || echo "$FILE_SIZE bytes")"
echo ""

if [ "$LINE_COUNT" -lt 10000 ]; then
    ARCH="webpack"
    echo "🔍 Detected: WEBPACK-BUNDLED (minified)"
else
    ARCH="line-based"
    echo "🔍 Detected: LINE-BASED (readable)"
fi
echo ""

# Create backup
BACKUP_FILE="$EXTENSION_JS.backup-$(date +%Y%m%d-%H%M%S)"
echo "💾 Creating backup: $BACKUP_FILE"
cp "$EXTENSION_JS" "$BACKUP_FILE"
echo "   ✅ Backup created"
echo ""

# Apply fixes based on architecture
if [ "$ARCH" = "webpack" ]; then
    echo "⚠️  WEBPACK-BUNDLED VERSION DETECTED"
    echo ""
    echo "Webpack-bundled versions are minified and cannot be reliably patched with"
    echo "line-based tools. The following options are available:"
    echo ""
    echo "OPTION 1: Disable auto-update and downgrade to line-based version"
    echo "   1. Disable VS Code auto-update:"
    echo "      Add to settings.json: \"extensions.autoUpdate\": false"
    echo "   2. Uninstall current Augment extension"
    echo "   3. Install older version with line-based code"
    echo "   4. Apply fixes using apply-cancelToolRun-fix.py"
    echo ""
    echo "OPTION 2: Use workaround scripts (see user-override-tools/)"
    echo "   - manual-output-reader.sh: Manually read terminal output"
    echo "   - force-continue.sh: Override AI's \"no output\" claims"
    echo ""
    echo "OPTION 3: Wait for official fix from Augment Code team"
    echo "   - Submit bug report package to Augment Code"
    echo "   - See: augment-extension-bug-bounty/SUBMIT_TO_AUGMENT_TEAM.md"
    echo ""
    echo "❌ AUTOMATIC FIX NOT POSSIBLE FOR WEBPACK-BUNDLED VERSION"
    exit 1
else
    echo "✅ LINE-BASED VERSION - APPLYING FIXES"
    echo ""
    
    # Check if Python fix script exists
    FIX_SCRIPT="$(dirname "$0")/fixes/apply-cancelToolRun-fix.py"
    
    if [ ! -f "$FIX_SCRIPT" ]; then
        echo "❌ ERROR: Fix script not found: $FIX_SCRIPT"
        exit 1
    fi
    
    echo "🔧 Running Python fix script..."
    python3 "$FIX_SCRIPT"
    
    if [ $? -eq 0 ]; then
        echo ""
        echo "✅ FIXES APPLIED SUCCESSFULLY"
        echo ""
        echo "⚠️  IMPORTANT: Reload VS Code for changes to take effect"
        echo "   Press Ctrl+Shift+P → 'Developer: Reload Window'"
        echo ""
    else
        echo ""
        echo "❌ FIX FAILED"
        echo ""
        echo "Restoring backup..."
        cp "$BACKUP_FILE" "$EXTENSION_JS"
        echo "✅ Backup restored"
        exit 1
    fi
fi

