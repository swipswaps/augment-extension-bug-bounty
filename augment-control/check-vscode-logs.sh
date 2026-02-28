#!/usr/bin/env bash
# Programmatic VS Code Log Checker for Augment Extension Issues

set -euo pipefail

echo "╔════════════════════════════════════════════════════════════════════════════╗"
echo "║                    VS CODE LOG DIAGNOSTIC REPORT                           ║"
echo "╚════════════════════════════════════════════════════════════════════════════╝"
echo ""

# Find latest log directory
LATEST_LOG=$(ls -td ~/.config/Code/logs/*/ 2>/dev/null | head -1)

if [ -z "$LATEST_LOG" ]; then
    echo "❌ No VS Code logs found"
    exit 1
fi

echo "📁 Log directory: $LATEST_LOG"
echo ""

# Get active version
ACTIVE_VERSION=$(code --list-extensions --show-versions 2>/dev/null | grep augment | cut -d'@' -f2 || echo "unknown")
echo "🔍 Active Augment version: $ACTIVE_VERSION"
echo ""

# Check for extension load errors
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "1. EXTENSION LOAD ERRORS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

EXTHOST_LOG="${LATEST_LOG}exthost/exthost.log"
if [ -f "$EXTHOST_LOG" ]; then
    LOAD_ERRORS=$(grep -i "augment.*error\|augment.*failed\|augment.*cannot" "$EXTHOST_LOG" 2>/dev/null | tail -10 || echo "")
    if [ -n "$LOAD_ERRORS" ]; then
        echo "⚠️  Extension load errors found:"
        echo "$LOAD_ERRORS"
    else
        echo "✅ No extension load errors"
    fi
else
    echo "⚠️  Extension host log not found"
fi
echo ""

# Check for UNRESPONSIVE warnings
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "2. EXTENSION PERFORMANCE ISSUES"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

RENDERER_LOG="${LATEST_LOG}window1/renderer.log"
if [ -f "$RENDERER_LOG" ]; then
    UNRESPONSIVE=$(grep -i "UNRESPONSIVE.*augment" "$RENDERER_LOG" 2>/dev/null | tail -5 || echo "")
    if [ -n "$UNRESPONSIVE" ]; then
        echo "⚠️  Extension unresponsive warnings found:"
        echo "$UNRESPONSIVE"
    else
        echo "✅ No unresponsive warnings"
    fi
else
    echo "⚠️  Renderer log not found"
fi
echo ""

# Check Augment-specific logs
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "3. AUGMENT EXTENSION ERRORS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

AUGMENT_LOG=$(find "$LATEST_LOG" -path "*/Augment.vscode-augment/Augment.log" 2>/dev/null | head -1)
if [ -f "$AUGMENT_LOG" ]; then
    AUGMENT_ERRORS=$(grep -i "error\|failed\|cancelled" "$AUGMENT_LOG" 2>/dev/null | tail -10 || echo "")
    if [ -n "$AUGMENT_ERRORS" ]; then
        echo "⚠️  Augment errors found:"
        echo "$AUGMENT_ERRORS"
    else
        echo "✅ No Augment errors"
    fi
else
    echo "⚠️  Augment log not found"
fi
echo ""

# Check patch status
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "4. PATCH STATUS"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

EXT_DIR="$HOME/.vscode/extensions/augment.vscode-augment-$ACTIVE_VERSION"
if [ -d "$EXT_DIR" ]; then
    WEBVIEW=$(find "$EXT_DIR/common-webviews" -name "extension-client-context-*.js" 2>/dev/null | head -1)
    if [ -n "$WEBVIEW" ]; then
        if grep -q "je(500)" "$WEBVIEW" 2>/dev/null; then
            echo "❌ NOT PATCHED - je(500) found in webview bundle"
            echo "   Run: ./patch-active-version.sh"
        else
            echo "✅ PATCHED - je(500) removed from webview bundle"
        fi
        
        # Check for backups
        BACKUPS=$(ls -1 "$WEBVIEW".backup-* 2>/dev/null | wc -l)
        echo "   Backups available: $BACKUPS"
    else
        echo "⚠️  Webview bundle not found"
    fi
else
    echo "⚠️  Extension directory not found"
fi
echo ""

# Summary
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "SUMMARY"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Active version: $ACTIVE_VERSION"
echo "Log directory: $LATEST_LOG"
echo ""
echo "To fix issues:"
echo "  1. Apply patch: ./patch-active-version.sh"
echo "  2. Restart VS Code"
echo "  3. Re-run this script to verify"

