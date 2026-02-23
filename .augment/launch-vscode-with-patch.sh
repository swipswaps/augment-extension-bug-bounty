#!/usr/bin/env bash
###############################################################################
# LAUNCH VS CODE WITH RUNTIME PATCH
#
# PURPOSE:
#   Start VS Code with augment-runtime-patch.js preloaded
#   Fixes fetch leaks without modifying extension.js
#
# USAGE:
#   ./.augment/launch-vscode-with-patch.sh
#
# WHAT IT DOES:
#   1. Sets NODE_OPTIONS to preload runtime patch
#   2. Launches VS Code with current workspace
#   3. Monitors FD count in background
#   4. Logs all activity to .notes/vscode-launch.log
#
# EXPECTED RESULTS:
#   - FD count stabilizes at ~8,000
#   - No monotonic increase
#   - AbortError frequency drops
#   - No truncation
#   - Tool calls work after errors
###############################################################################

set -euo pipefail

WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PATCH_FILE="$WORKSPACE_DIR/.augment/augment-runtime-patch.js"
LOGFILE="$WORKSPACE_DIR/.notes/vscode-launch-$(date +%Y%m%d-%H%M%S).log"

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE"
}

log "========================================================================"
log "LAUNCHING VS CODE WITH RUNTIME PATCH"
log "========================================================================"
log "Workspace: $WORKSPACE_DIR"
log "Patch file: $PATCH_FILE"
log "Log file: $LOGFILE"
log ""

# Verify patch file exists
if [ ! -f "$PATCH_FILE" ]; then
  log "ERROR: Patch file not found: $PATCH_FILE"
  exit 1
fi

log "✓ Patch file found"

# Check if VS Code is already running
if pgrep -f "code.*$WORKSPACE_DIR" > /dev/null; then
  log "⚠ WARNING: VS Code already running with this workspace"
  log "  You should close it first for clean startup"
  read -p "Continue anyway? (y/N) " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    log "Aborted by user"
    exit 1
  fi
fi

# Set NODE_OPTIONS to preload patch
export NODE_OPTIONS="--require $PATCH_FILE"

log "✓ NODE_OPTIONS set: $NODE_OPTIONS"
log ""
log "Starting VS Code..."
log ""

# Launch VS Code
code "$WORKSPACE_DIR" &

VSCODE_PID=$!

log "✓ VS Code launched (PID: $VSCODE_PID)"
log ""
log "========================================================================"
log "MONITORING STARTED"
log "========================================================================"
log ""
log "Watch these files for diagnostics:"
log "  - .notes/runtime-patch.log (fetch monitoring)"
log "  - .notes/stream-guard.log (stream cleanup)"
log "  - augment-latch-debug.log (latch events)"
log ""
log "To monitor FD count in real-time:"
log "  watch -n 10 'lsof 2>/dev/null | grep -c code'"
log ""
log "To check if patch is active:"
log "  grep 'RUNTIME_PATCH' .notes/runtime-patch.log"
log ""
log "To stop monitoring:"
log "  pkill -f 'code.*$WORKSPACE_DIR'"
log ""
log "========================================================================"
log "LAUNCH COMPLETE"
log "========================================================================"

