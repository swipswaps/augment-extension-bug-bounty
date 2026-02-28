#!/usr/bin/env bash
#
# FIX EXTENSION.JS - Apply fixes for "Cancelled by user" false positives
#
# ROOT CAUSE (from forensic analysis):
# - updateStatusTrace() fires multiple times simultaneously (no mutex)
# - Completion requests overlap (no queue)
# - Webview messages fire rapidly (no debouncing)
# - RemoteAgentsMessenger initializes multiple times creating IPC contexts
#
# FIXES:
# 1. Add mutex to updateStatusTrace()
# 2. Add queue to completion requests
# 3. Add debouncing to webview messages
#
# EVIDENCE:
# - 106-117 leaked Chromium shared memory segments
# - 0 AbortErrors (async iterator fix works)
# - RemoteAgentsMessenger initialized 5x in rapid succession
# - strace shows mmap on FDs 41,42,43,44 creating shared memory
#

set -euo pipefail

echo "========================================"
echo "EXTENSION.JS FIX APPLICATION"
echo "Date: $(date)"
echo "========================================"
echo ""

# Find Augment extension
EXTENSION_DIR=$(find ~/.vscode/extensions -maxdepth 1 -name "augment.vscode-augment-*" -type d | head -1)

if [ -z "$EXTENSION_DIR" ]; then
    echo "❌ Augment extension not found"
    exit 1
fi

EXTENSION_JS="$EXTENSION_DIR/out/extension.js"

if [ ! -f "$EXTENSION_JS" ]; then
    echo "❌ extension.js not found at $EXTENSION_JS"
    exit 1
fi

echo "✅ Found extension: $EXTENSION_DIR"
echo "✅ extension.js: $EXTENSION_JS"
echo ""

# Backup
BACKUP="$EXTENSION_JS.backup-$(date +%Y%m%d-%H%M%S)"
echo "📦 Creating backup: $BACKUP"
cp "$EXTENSION_JS" "$BACKUP"
echo "✅ Backup created"
echo ""

# The file is minified - we need to pretty-print it first to find the patterns
echo "🔍 Searching for code patterns..."
echo ""

# Search for RemoteAgentsMessenger initialization
echo "=== RemoteAgentsMessenger initialization (line ~275878) ==="
grep -n "RemoteAgentsMessenger initialized" "$EXTENSION_JS" | head -5
echo ""

# Search for updateStatusTrace
echo "=== updateStatusTrace pattern ==="
grep -n "updateStatusTrace" "$EXTENSION_JS" | head -5
echo ""

# Search for _apiServer.complete
echo "=== _apiServer.complete pattern ==="
grep -n "_apiServer.complete" "$EXTENSION_JS" | head -5
echo ""

# Search for webview message firing
echo "=== Webview message firing pattern ==="
grep -n "_nextEditVSCodeToWebviewMessage.fire" "$EXTENSION_JS" | head -5
echo ""

echo "========================================"
echo "ANALYSIS COMPLETE"
echo "========================================"
echo ""
echo "The extension.js file is minified (15MB, single line)."
echo "To apply fixes, we need to:"
echo "1. Pretty-print the file"
echo "2. Find exact code locations"
echo "3. Apply the three fixes"
echo "4. Re-minify (or use pretty-printed version)"
echo ""
echo "Opening extension.js in VS Code for manual inspection..."
echo ""

# Open in VS Code
code "$EXTENSION_JS"

echo "✅ File opened in VS Code"
echo ""
echo "NEXT STEPS:"
echo "1. The file is now open in VS Code"
echo "2. Use Ctrl+Shift+P → 'Format Document' to pretty-print"
echo "3. Search for the patterns shown above"
echo "4. Apply the fixes from .notes/699eec25-5120-832b-9948-5e142d18cd90_0128.txt lines 1334-1441"
echo ""
echo "Backup location: $BACKUP"

