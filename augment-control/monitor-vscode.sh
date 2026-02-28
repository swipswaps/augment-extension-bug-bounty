#!/usr/bin/env bash
# VS Code + Extension Log Mirror - Continuous tee monitoring
set -euo pipefail

LOG_ROOT="$HOME/.config/Code/logs"

echo "=== VS Code Log Monitor ==="
echo "Waiting for VS Code logs at $LOG_ROOT..."
echo ""

# Wait for VS Code to start
while [[ ! -d "$LOG_ROOT" ]]; do
  sleep 1
done

# Find latest session
LATEST_SESSION=$(ls -td "$LOG_ROOT"/* 2>/dev/null | head -1)

if [[ -z "$LATEST_SESSION" ]]; then
  echo "[ERROR] No log sessions found"
  exit 1
fi

echo "Monitoring session: $LATEST_SESSION"
echo ""
echo "Watching for:"
echo "  - Extension crashes"
echo "  - Unhandled promise rejections"
echo "  - Timeout messages"
echo "  - Cancellation events"
echo ""
echo "Press Ctrl+C to stop"
echo "========================================"
echo ""

# Monitor all relevant logs
tail -F \
  "$LATEST_SESSION/exthost.log" \
  "$LATEST_SESSION/main.log" \
  "$LATEST_SESSION/renderer.log" 2>/dev/null \
| grep --line-buffered -E "timeout|cancel|error|reject|crash|augment" -i \
| while IFS= read -r line; do
    echo "[$(date '+%H:%M:%S')] $line"
  done

