#!/bin/bash
# Fix Method 5: Use Source Map to Find Exact Code
# Difficulty: Hard | Risk: Low (read-only) | Effectiveness: High (for diagnosis)

echo "=== Augment Extension Source Map Extraction ==="
echo ""

EXTENSION_DIR="/home/owner/.vscode/extensions/augment.vscode-augment-0.779.0"
SOURCE_MAP="$EXTENSION_DIR/out/extension.js.map"

if [ ! -f "$SOURCE_MAP" ]; then
  echo "ERROR: Source map not found at $SOURCE_MAP"
  exit 1
fi

echo "Source map found: $SOURCE_MAP (32.8 MB)"
echo ""

# Check if source-map-cli is installed
if ! command -v smc &> /dev/null; then
  echo "Installing source-map-cli..."
  npm install -g source-map-cli
  echo ""
fi

# Check if error stack trace file exists
if [ -f "error_stack.txt" ]; then
  echo "Extracting readable stack trace from error_stack.txt..."
  smc mapStackTrace "$SOURCE_MAP" < error_stack.txt > readable_stack.txt
  echo "Readable stack trace written to readable_stack.txt"
else
  echo "No error_stack.txt found. Creating example..."
  echo ""
  echo "To use this script:"
  echo "1. Copy the error stack trace from VS Code console"
  echo "2. Save it to error_stack.txt in this directory"
  echo "3. Run this script again"
  echo ""
  echo "Example error_stack.txt format:"
  echo "  Error: Cancelled by user"
  echo "    at Object.callTool (extension.js:12345:67)"
  echo "    at async runTool (extension.js:23456:78)"
fi

echo ""
echo "Source map file is available for manual inspection."
echo "You can also use tools like 'source-map-explorer' to visualize the bundle."

