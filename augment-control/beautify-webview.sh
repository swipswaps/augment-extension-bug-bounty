#!/usr/bin/env bash
# Beautify Webpack-Bundled Webview Files
# Uses js-beautify to make minified code readable

set -euo pipefail

echo "╔════════════════════════════════════════════════════════════════════════════╗"
echo "║                    WEBVIEW BEAUTIFIER                                      ║"
echo "╚════════════════════════════════════════════════════════════════════════════╝"
echo ""

# Check if js-beautify is installed
if ! command -v js-beautify &> /dev/null; then
    echo "⚠️  js-beautify not found"
    echo ""
    echo "Install with:"
    echo "  npm install -g js-beautify"
    echo ""
    read -p "Install now? (yes/no): " INSTALL
    
    if [ "$INSTALL" = "yes" ]; then
        npm install -g js-beautify
    else
        echo "Cancelled"
        exit 1
    fi
fi

# Get active version
ACTIVE_VERSION=$(code --list-extensions --show-versions 2>/dev/null | grep augment | cut -d'@' -f2)
EXT_DIR="$HOME/.vscode/extensions/augment.vscode-augment-$ACTIVE_VERSION"

echo "Active version: $ACTIVE_VERSION"
echo ""

# Find webview bundle
WEBVIEW=$(find "$EXT_DIR/common-webviews" -name "extension-client-context-*.js" 2>/dev/null | head -1)

if [ -z "$WEBVIEW" ]; then
    echo "❌ Webview bundle not found"
    exit 1
fi

echo "Target: $WEBVIEW"
echo "Size: $(du -h "$WEBVIEW" | cut -f1)"
echo ""

# Create beautified version
BEAUTIFIED="${WEBVIEW}.beautified.js"

echo "Beautifying..."
js-beautify "$WEBVIEW" > "$BEAUTIFIED"

echo "✅ Beautified version created: $BEAUTIFIED"
echo "Size: $(du -h "$BEAUTIFIED" | cut -f1)"
echo ""
echo "To view:"
echo "  code '$BEAUTIFIED'"
echo ""
echo "⚠️  This is for READING ONLY - do not edit the beautified version"
echo "   Use patch scripts to make changes to the original minified file"

