#!/usr/bin/env bash

EXT=$(ls -d ~/.vscode/extensions/augment.vscode-augment-* | sort -V | tail -1)
FILE="$EXT/common-webviews/assets"

echo "Scanning for heuristic timeout blocks..."

grep -R "je(500)" "$FILE" 2>/dev/null
grep -R "Tool call timed out" "$FILE" 2>/dev/null
grep -R "markToolAsError" "$FILE" 2>/dev/null

echo
echo "Scan complete."
