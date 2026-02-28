#!/usr/bin/env bash
# Extension Host Process Monitor - Detects restarts and crashes
set -euo pipefail

echo "=== Extension Host Monitor ==="
echo "Monitoring VS Code Extension Host process..."
echo "Press Ctrl+C to stop"
echo ""

LAST_PID=""

while true; do
  CURRENT_PID=$(pgrep -f "extensionHost" | head -1 || echo "")
  
  if [[ -z "$CURRENT_PID" ]]; then
    echo "[$(date '+%H:%M:%S')] [WARN] Extension Host not running"
  elif [[ -z "$LAST_PID" ]]; then
    echo "[$(date '+%H:%M:%S')] [INFO] Extension Host started (PID: $CURRENT_PID)"
    LAST_PID="$CURRENT_PID"
  elif [[ "$CURRENT_PID" != "$LAST_PID" ]]; then
    echo "[$(date '+%H:%M:%S')] [ALERT] Extension Host RESTARTED (Old PID: $LAST_PID, New PID: $CURRENT_PID)"
    LAST_PID="$CURRENT_PID"
  fi
  
  sleep 2
done

