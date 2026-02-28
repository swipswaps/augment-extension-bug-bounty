#!/usr/bin/env bash
# kill-hidden-terminals.sh
# PRF-HARDENED: Detect and safely terminate hidden VS Code terminals and extension hosts
# Root Cause: RULE 22 violation - terminal accumulation causes MCP instability
set -euo pipefail

LOGFILE="./kill-hidden-terminals-$(date '+%Y%m%d_%H%M%S').log"

FORCE_MODE=false
if [[ "${1:-}" == "--force" ]]; then
    FORCE_MODE=true
fi

echo "=== Hidden Terminal Cleanup ===" | tee -a "$LOGFILE"
echo "Date: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"

# Timeout-protected process detection (5s for reliability)
echo "[INFO] Detecting hidden VS Code terminals and extension hosts..." | tee -a "$LOGFILE"

# Detect VS Code extension hosts and terminal processes ONLY
# Do NOT detect shell processes - they're too broad and cause false positives
TERMINAL_PIDS=$(timeout 5s pgrep -u "$USER" -f "code.*--ms-enable-electron-run-as-node|extensionHost" 2>/dev/null || true)

if [[ -z "$TERMINAL_PIDS" ]]; then
    echo "[INFO] No hidden terminals found (or detection timed out)." | tee -a "$LOGFILE"
    exit 0
fi

TERMINAL_COUNT=$(echo "$TERMINAL_PIDS" | wc -w)
echo "[INFO] Found $TERMINAL_COUNT hidden terminals/processes." | tee -a "$LOGFILE"
echo "[DETAILS] PIDs: $TERMINAL_PIDS" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"

# Ask for confirmation if not forced AND stdin is a terminal
if [[ "$FORCE_MODE" == false ]]; then
    if [[ -t 0 ]]; then
        read -t 5 -p "Kill all hidden terminals? (y/N): " -n 1 -r || true
        echo
        if [[ ! ${REPLY:-N} =~ ^[Yy]$ ]]; then
            echo "[INFO] Aborting cleanup." | tee -a "$LOGFILE"
            echo "To force cleanup, run: $0 --force" | tee -a "$LOGFILE"
            exit 0
        fi
    else
        echo "[INFO] Non-interactive environment detected. Aborting." | tee -a "$LOGFILE"
        echo "To force cleanup, run: $0 --force" | tee -a "$LOGFILE"
        exit 0
    fi
fi

# Kill detected processes safely (SIGTERM first, then SIGKILL)
echo "[INFO] Killing hidden terminals safely..." | tee -a "$LOGFILE"

# Send SIGTERM to all processes first
for PID in $TERMINAL_PIDS; do
    if kill -0 "$PID" 2>/dev/null; then
        echo "[INFO] Sending SIGTERM to PID $PID" | tee -a "$LOGFILE"
        kill -15 "$PID" 2>/dev/null || echo "[WARN] Failed to SIGTERM $PID" | tee -a "$LOGFILE"
    fi
done

# Wait briefly for graceful shutdown
sleep 1

# Send SIGKILL to any survivors
for PID in $TERMINAL_PIDS; do
    if kill -0 "$PID" 2>/dev/null; then
        echo "[INFO] PID $PID still alive, sending SIGKILL" | tee -a "$LOGFILE"
        kill -9 "$PID" 2>/dev/null || echo "[WARN] Failed to SIGKILL $PID" | tee -a "$LOGFILE"
    else
        echo "[INFO] PID $PID terminated gracefully" | tee -a "$LOGFILE"
    fi
done

echo "[INFO] Cleanup complete at $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"
echo "=== Root Cause Analysis ===" | tee -a "$LOGFILE"
echo "1. launch-process with wait=false creates persistent terminals" | tee -a "$LOGFILE"
echo "2. Each tool call spawns a new terminal instead of reusing" | tee -a "$LOGFILE"
echo "3. MCP client doesn't clean up on timeout" | tee -a "$LOGFILE"
echo "4. RULE 22 violation: Terminal accumulation causes instability" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"
echo "Evidence: If this script timed out during pgrep, that timeout is PROOF of the race condition." | tee -a "$LOGFILE"
echo "=== End of Cleanup ===" | tee -a "$LOGFILE"

