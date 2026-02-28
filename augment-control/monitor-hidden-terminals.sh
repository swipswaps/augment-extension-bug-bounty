#!/usr/bin/env bash
# monitor-hidden-terminals.sh
# PRF-HARDENED: Detect and log hidden VS Code terminals and extension hosts without killing
# Root Cause: RULE 22 violation - terminal accumulation causes MCP instability
set -euo pipefail

LOGFILE="./monitor-hidden-terminals-$(date '+%Y%m%d_%H%M%S').log"

echo "=== Hidden Terminal Monitor ===" | tee -a "$LOGFILE"
echo "Date: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"

# Timeout-protected detection (5s for reliability)
echo "[INFO] Detecting VS Code terminals and extension hosts..." | tee -a "$LOGFILE"

# Detect VS Code extension hosts and terminal processes ONLY
# Do NOT detect shell processes - they're too broad and cause false positives
TERMINAL_PIDS=$(timeout 5s pgrep -u "$USER" -f "code.*--ms-enable-electron-run-as-node|extensionHost" 2>/dev/null || true)

if [[ -z "$TERMINAL_PIDS" ]]; then
    echo "[INFO] No hidden terminals detected (or detection timed out)." | tee -a "$LOGFILE"
    exit 0
fi

# Count and list hidden terminals
TERMINAL_COUNT=$(echo "$TERMINAL_PIDS" | wc -w)
echo "[INFO] Found $TERMINAL_COUNT hidden terminals/processes." | tee -a "$LOGFILE"
echo "[DETAILS] PIDs: $TERMINAL_PIDS" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"

# List command lines for forensic analysis
echo "[DETAILS] Command lines:" | tee -a "$LOGFILE"
for PID in $TERMINAL_PIDS; do
    if [[ -r /proc/$PID/cmdline ]]; then
        CMD=$(tr '\0' ' ' < /proc/$PID/cmdline)
        echo "  PID $PID: $CMD" | tee -a "$LOGFILE"
    else
        echo "  PID $PID: [cmdline unavailable]" | tee -a "$LOGFILE"
    fi
done

echo "" | tee -a "$LOGFILE"
echo "=== End of Monitoring ===" | tee -a "$LOGFILE"
echo "Date: $(date '+%Y-%m-%d %H:%M:%S')" | tee -a "$LOGFILE"
echo ""
echo "To cleanup these terminals safely, run:"
echo "  ./kill-hidden-terminals.sh --force"

