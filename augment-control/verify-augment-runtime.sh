#!/usr/bin/env bash
# Runtime Verification Script - ChatGPT Strict Enforcement Protocol
# NO SPECULATION - ONLY FACTS

set -euo pipefail

EXT_BASE="$HOME/.vscode/extensions"
ACTIVE_EXT=$(ls -d $EXT_BASE/augment.vscode-augment-* | sort -V | tail -1)

echo "╔════════════════════════════════════════════════════════════════════════════╗"
echo "║                    AUGMENT RUNTIME VERIFICATION                            ║"
echo "╚════════════════════════════════════════════════════════════════════════════╝"
echo ""

echo "1. Active extension directory:"
echo "$ACTIVE_EXT"
echo ""

EXT_JS="$ACTIVE_EXT/out/extension.js"

echo "2. SHA256 of extension.js:"
sha256sum "$EXT_JS"
echo ""

echo "3. Checking for deterministic patch marker..."
grep -n "DETERMINISTIC_PATCH_MARKER" "$EXT_JS" || echo "❌ Marker NOT found"
echo ""

echo "4. Checking webview bundle for timeout heuristic..."
WEBVIEW=$(find "$ACTIVE_EXT/common-webviews" -name "extension-client-context-*.js" | head -1)
if [ -n "$WEBVIEW" ]; then
    echo "Webview file: $WEBVIEW"
    grep -n "je(500)" "$WEBVIEW" || echo "✅ No je(500) found"
else
    echo "❌ Webview bundle not found"
fi
echo ""

echo "5. VS Code process verification:"
pgrep -a code | head -5
echo ""

echo "6. VS Code active extension version:"
code --list-extensions --show-versions | grep augment
echo ""

echo "╔════════════════════════════════════════════════════════════════════════════╗"
echo "║                         VERIFICATION COMPLETE                              ║"
echo "╚════════════════════════════════════════════════════════════════════════════╝"

