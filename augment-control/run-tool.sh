#!/usr/bin/env bash
# External Deterministic Controller - Tool Runner (v2 - Deterministic State Machine)
# Guarantees file-backed output capture with atomic state transitions

set -euo pipefail

if [ $# -eq 0 ]; then
    echo "Usage: $0 <command>"
    echo "Example: $0 'ls -la'"
    exit 1
fi

CMD="$*"
RUN_ID=$(date +%s%N)
BASE="$HOME/.edc/runs"
RUN_DIR="$BASE/$RUN_ID"
mkdir -p "$RUN_DIR"

STATE_FILE="$RUN_DIR/state.txt"
META_FILE="$RUN_DIR/meta.txt"
STDOUT_FILE="$RUN_DIR/stdout.txt"
STDERR_FILE="$RUN_DIR/stderr.txt"
PID_FILE="$RUN_DIR/pid.txt"

# Atomic state transitions
log_state() {
    echo "$1" > "$STATE_FILE"
    echo "$(date +%s.%N)|STATE=$1" >> "$META_FILE"
}

log_meta() {
    echo "$1" >> "$META_FILE"
}

# Initialize
log_state "NEW"
log_meta "run_id=$RUN_ID"
log_meta "cmd=$CMD"
log_meta "start_time=$(date +%s)"
log_meta "start_timestamp=$(date '+%Y-%m-%d %H:%M:%S.%N')"

log_state "QUEUED"

# Launch process in background with PID capture
log_state "RUNNING"
(
    bash -c "$CMD"
) >"$STDOUT_FILE" 2>"$STDERR_FILE" &

CHILD_PID=$!
echo "$CHILD_PID" > "$PID_FILE"
log_meta "child_pid=$CHILD_PID"

# Timeout watchdog with grace period
TIMEOUT=15
GRACE=3

(
    sleep "$TIMEOUT"
    if kill -0 "$CHILD_PID" 2>/dev/null; then
        log_state "TIMEOUT"
        log_meta "timeout_triggered=$(date +%s)"
        kill -TERM "$CHILD_PID" 2>/dev/null || true
        sleep "$GRACE"
        if kill -0 "$CHILD_PID" 2>/dev/null; then
            kill -KILL "$CHILD_PID" 2>/dev/null || true
            log_meta "force_killed=true"
        fi
    fi
) &

WATCHDOG_PID=$!

# Wait for child process
wait "$CHILD_PID" 2>/dev/null || true
EXIT_CODE=$?

# Kill watchdog if still running
kill "$WATCHDOG_PID" 2>/dev/null || true
wait "$WATCHDOG_PID" 2>/dev/null || true

# Ensure stdout/stderr files are flushed
sync

# Determine final state (only if not already TIMEOUT)
CURRENT_STATE=$(cat "$STATE_FILE")
if [ "$CURRENT_STATE" = "TIMEOUT" ]; then
    FINAL_STATE="TIMEOUT"
    log_meta "exit_code=124"
elif [ "$EXIT_CODE" -eq 0 ]; then
    log_state "COMPLETED"
    FINAL_STATE="COMPLETED"
    log_meta "exit_code=$EXIT_CODE"
else
    log_state "ERROR"
    FINAL_STATE="ERROR"
    log_meta "exit_code=$EXIT_CODE"
fi

END_TIME=$(date +%s)
START_TIME=$(grep "^start_time=" "$META_FILE" | cut -d= -f2)
DURATION=$((END_TIME - START_TIME))

log_meta "end_time=$END_TIME"
log_meta "end_timestamp=$(date '+%Y-%m-%d %H:%M:%S.%N')"
log_meta "duration=$DURATION"

# Output summary for easy parsing
echo "╔════════════════════════════════════════════════════════════════════════════╗"
echo "║                    TOOL EXECUTION COMPLETE                                 ║"
echo "╚════════════════════════════════════════════════════════════════════════════╝"
echo ""
echo "RUN_ID=$RUN_ID"
echo "STATE=$FINAL_STATE"
echo "EXIT_CODE=$EXIT_CODE"
echo "DURATION=${DURATION}s"
echo ""
echo "OUTPUT FILES:"
echo "  STDOUT: $STDOUT_FILE"
echo "  STDERR: $STDERR_FILE"
echo "  META:   $META_FILE"
echo ""
echo "STDOUT SIZE: $(wc -c < "$STDOUT_FILE") bytes"
echo "STDERR SIZE: $(wc -c < "$STDERR_FILE") bytes"
echo ""

if [ "$FINAL_STATE" = "TIMEOUT" ]; then
    echo "⚠️  TIMEOUT OCCURRED - Output captured before timeout:"
    if [ -s "$STDOUT_FILE" ]; then
        echo "✅ STDOUT contains $(wc -l < "$STDOUT_FILE") lines"
    else
        echo "❌ STDOUT is empty"
    fi
fi

echo ""
echo "To read output:"
echo "  cat $STDOUT_FILE"
echo "  cat $STDERR_FILE"
echo "  cat $META_FILE"

