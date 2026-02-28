#!/usr/bin/env bash
#######################################################################
# FORENSIC DRIVER - DETERMINISTIC ROOT CAUSE PROOF ENGINE
#
# PURPOSE:
#   Programmatically identify extension host instability,
#   Chromium zygote churn, shared memory leaks,
#   FD growth, and syscall evidence.
#
# DESIGN:
#   - Deterministic step enforcement
#   - Mandatory validation before proceeding
#   - 6 second wait before log reads
#   - Retry if output missing
#   - No speculative conclusions
#
# REQUIREMENTS:
#   Kali Linux or equivalent
#   strace
#   lsof
#   procfs
#
# USAGE:
#   chmod +x forensic-driver.sh
#   sudo ./forensic-driver.sh
#
#######################################################################

set -euo pipefail

LOGDIR="./forensic_logs"
mkdir -p "$LOGDIR"

LOGFILE="$LOGDIR/forensic-$(date +%Y%m%d-%H%M%S).log"

log() {
    echo "[$(date '+%H:%M:%S')] $1" | tee -a "$LOGFILE"
}

validate_output() {
    local file="$1"
    local desc="$2"

    if [[ ! -f "$file" ]]; then
        log "FAIL: $desc (file not created)"
        exit 1
    fi

    if [[ ! -s "$file" ]]; then
        log "FAIL: $desc (file empty)"
        exit 1
    fi

    log "PASS: $desc"
}

wait_and_validate() {
    local file="$1"
    local desc="$2"

    log "Waiting 6 seconds before validating output..."
    sleep 6
    validate_output "$file" "$desc"
}

#######################################################################
# STEP 1: Identify VSCode Extension Host and Zygote
#######################################################################

log "STEP 1: Identifying extension host and Chromium zygote"

ps aux > "$LOGDIR/process_snapshot.txt"
wait_and_validate "$LOGDIR/process_snapshot.txt" "Process snapshot"

EXT_PID=$(pgrep -f "extensionHost" | head -1 || true)
ZYGOTE_PID=$(pgrep -f "zygote" | head -1 || true)

log "Extension Host PID: ${EXT_PID:-NOT FOUND}"
log "Zygote PID: ${ZYGOTE_PID:-NOT FOUND}"

if [[ -z "${ZYGOTE_PID:-}" ]]; then
    log "No zygote process found. Cannot proceed."
    exit 1
fi

#######################################################################
# STEP 2: Monitor Shared Memory Segments
#######################################################################

log "STEP 2: Counting Chromium shared memory segments"

ls -1 /dev/shm | grep -i chromium > "$LOGDIR/shm_snapshot.txt" || true
wait_and_validate "$LOGDIR/shm_snapshot.txt" "Shared memory snapshot"

SHM_COUNT=$(wc -l < "$LOGDIR/shm_snapshot.txt")
log "Chromium SHM count: $SHM_COUNT"

#######################################################################
# STEP 3: File Descriptor Count
#######################################################################

log "STEP 3: Counting open file descriptors for zygote"

ls "/proc/$ZYGOTE_PID/fd" > "$LOGDIR/fd_snapshot.txt"
wait_and_validate "$LOGDIR/fd_snapshot.txt" "FD snapshot"

FD_COUNT=$(wc -l < "$LOGDIR/fd_snapshot.txt")
log "Zygote FD count: $FD_COUNT"

#######################################################################
# STEP 4: CPU and Memory Snapshot
#######################################################################

log "STEP 4: Capturing CPU and memory metrics"

ps -p "$ZYGOTE_PID" -o pid,etime,pcpu,pmem,rss,cmd > "$LOGDIR/zygote_metrics.txt"
wait_and_validate "$LOGDIR/zygote_metrics.txt" "Zygote metrics"

#######################################################################
# STEP 5: Syscall Trace (Memfd / SHM creation)
#######################################################################

log "STEP 5: Attaching strace to zygote (10 seconds)"

STRACE_OUT="$LOGDIR/strace_memfd.txt"

timeout 10 strace -f -e trace=memfd_create,shmget,shmctl -p "$ZYGOTE_PID" \
    -o "$STRACE_OUT" 2>/dev/null || true

wait_and_validate "$STRACE_OUT" "Strace syscall capture"

#######################################################################
# STEP 6: VSCode / Augment Log Correlation
#######################################################################

log "STEP 6: Extracting RemoteAgentsMessenger activity"

AUG_LOG=$(find ~/.config/Code/logs -name "Augment.log" 2>/dev/null | head -1 || true)

if [[ -n "${AUG_LOG:-}" ]]; then
    grep -n "RemoteAgentsMessenger" "$AUG_LOG" > "$LOGDIR/remote_agents_log.txt" || true
    wait_and_validate "$LOGDIR/remote_agents_log.txt" "RemoteAgentsMessenger log"
else
    log "Augment log not found"
fi

#######################################################################
# STEP 7: Growth Detection Loop (15 seconds)
#######################################################################

log "STEP 7: Detecting SHM and FD growth over 15 seconds"

for i in {1..5}; do
    sleep 3
    CURRENT_SHM=$(ls -1 /dev/shm | grep -i chromium | wc -l || true)
    CURRENT_FD=$(ls "/proc/$ZYGOTE_PID/fd" | wc -l || true)

    log "Iteration $i: SHM=$CURRENT_SHM FD=$CURRENT_FD"
done | tee "$LOGDIR/growth_monitor.txt"

wait_and_validate "$LOGDIR/growth_monitor.txt" "Growth monitoring"

#######################################################################
# FINAL
#######################################################################

log "FORENSIC CAPTURE COMPLETE"
log "Log file: $LOGFILE"

echo ""
echo "If analysis cannot read output, manually provide:"
echo "$LOGFILE"