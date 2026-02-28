#!/usr/bin/env bash
# Static Race Condition Scanner - Detects unsafe Promise.race patterns
set -euo pipefail

EXT_DIR="$HOME/.vscode/extensions/augment.vscode-augment-0.779.0/out"
TARGET="$EXT_DIR/extension.js"

if [[ ! -f "$TARGET" ]]; then
  echo "[ERROR] extension.js not found at $TARGET"
  exit 1
fi

echo "=== SCANNING FOR RACE PATTERNS ==="
echo "Target: $TARGET"
echo ""

echo "[1] Promise.race occurrences:"
grep -n "Promise\.race" "$TARGET" | head -20 || echo "  None found"

echo ""
echo "[2] setTimeout near race (possible timeout wrapper):"
grep -n -E "setTimeout.*[0-9]{4,}" "$TARGET" | head -30 || echo "  None found"

echo ""
echo "[3] Cancellation keywords:"
grep -n -E "cancel.*user|timeout.*cancel|race.*timeout" "$TARGET" | head -30 || echo "  None found"

echo ""
echo "[4] Tool execution patterns:"
grep -n -E "callTool|executeTool|toolExecution" "$TARGET" | head -20 || echo "  None found"

echo ""
echo "=== SCAN COMPLETE ==="
echo ""
echo "To save results: ./scan-augment-race.sh | tee race-scan.log"

