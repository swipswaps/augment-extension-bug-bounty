#!/usr/bin/env bash
# Unified Monitor Runner - Runs all monitoring scripts in parallel
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== Augment Timeout Forensic Monitor Suite ==="
echo "Starting all monitors..."
echo ""
echo "Monitors:"
echo "  1. Static race pattern scanner"
echo "  2. VS Code log monitor"
echo "  3. Extension host process monitor"
echo "  4. Event loop stall detector"
echo "  5. Hardened correlator (JSON output)"
echo ""
echo "All output will be saved to: full-debug-session.log"
echo "Press Ctrl+C to stop all monitors"
echo ""
echo "========================================"
echo ""

# Run static scan first
echo "[STATIC SCAN]"
"$SCRIPT_DIR/scan-augment-race.sh" 2>&1 | tee -a full-debug-session.log
echo ""

# Start background monitors
echo "[STARTING BACKGROUND MONITORS]"

# VS Code log monitor
"$SCRIPT_DIR/monitor-vscode.sh" 2>&1 | tee -a full-debug-session.log &
PID_VSCODE=$!

# Extension host monitor
"$SCRIPT_DIR/monitor-extension-host.sh" 2>&1 | tee -a full-debug-session.log &
PID_EXTHOST=$!

# Event loop monitor
node "$SCRIPT_DIR/event-loop-monitor.js" 2>&1 | tee -a full-debug-session.log &
PID_EVENTLOOP=$!

# Hardened correlator
node "$SCRIPT_DIR/vscode-correlator-hardened.js" 2>&1 | tee -a full-debug-session.log &
PID_CORRELATOR=$!

echo "Background monitors started:"
echo "  VS Code logs: PID $PID_VSCODE"
echo "  Extension host: PID $PID_EXTHOST"
echo "  Event loop: PID $PID_EVENTLOOP"
echo "  Correlator: PID $PID_CORRELATOR"
echo ""

# Cleanup on exit
cleanup() {
  echo ""
  echo "[STOPPING ALL MONITORS]"
  kill $PID_VSCODE $PID_EXTHOST $PID_EVENTLOOP $PID_CORRELATOR 2>/dev/null || true
  echo "All monitors stopped"
  echo "Full log saved to: full-debug-session.log"
}

trap cleanup EXIT INT TERM

# Wait for all background processes
wait

