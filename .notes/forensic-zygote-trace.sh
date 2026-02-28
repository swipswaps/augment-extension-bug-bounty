#!/usr/bin/env bash
#
# DEFINITIVE FORENSIC TRACE OF ZYGOTE SHARED MEMORY LEAK
#
# This script will capture the EXACT syscalls creating shared memory segments
# and prove which code path is responsible for the leak.
#

set -euo pipefail

LOGFILE=".notes/forensic-trace-$(date +%Y%m%d-%H%M%S).log"
ZYGOTE_PID=3552611

echo "========================================" | tee -a "$LOGFILE"
echo "FORENSIC TRACE: Zygote Shared Memory Leak" | tee -a "$LOGFILE"
echo "Date: $(date)" | tee -a "$LOGFILE"
echo "========================================" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"

# Step 1: Verify zygote still exists
echo "=== STEP 1: Verify zygote process exists ===" | tee -a "$LOGFILE"
if ps -p "$ZYGOTE_PID" > /dev/null 2>&1; then
    ps -p "$ZYGOTE_PID" -o pid,lstart,etime,pcpu,rss,nlwp,cmd | tee -a "$LOGFILE"
    echo "✅ Zygote process exists" | tee -a "$LOGFILE"
else
    echo "❌ Zygote process $ZYGOTE_PID does not exist" | tee -a "$LOGFILE"
    exit 1
fi
echo "" | tee -a "$LOGFILE"

# Step 2: Count current leaked shared memory segments
echo "=== STEP 2: Count leaked shared memory segments ===" | tee -a "$LOGFILE"
LEAK_COUNT=$(lsof -p "$ZYGOTE_PID" 2>/dev/null | grep -c "DEL.*shm.*Chromium" || echo "0")
echo "Current leaked segments: $LEAK_COUNT" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"

# Step 3: Sample of leaked segments
echo "=== STEP 3: Sample of leaked segments (first 10) ===" | tee -a "$LOGFILE"
lsof -p "$ZYGOTE_PID" 2>/dev/null | grep "DEL.*shm.*Chromium" | head -10 | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"

# Step 4: Check for AbortErrors in Augment logs
echo "=== STEP 4: Check for AbortErrors since restart ===" | tee -a "$LOGFILE"
AUGMENT_LOG=$(find ~/.config/Code/logs -name "Augment.log" -type f -newermt "2026-02-26 11:35" 2>/dev/null | head -1)
if [ -n "$AUGMENT_LOG" ]; then
    ABORT_COUNT=$(grep -c "AbortError" "$AUGMENT_LOG" 2>/dev/null || echo "0")
    echo "AbortError count: $ABORT_COUNT" | tee -a "$LOGFILE"
    echo "Log file: $AUGMENT_LOG" | tee -a "$LOGFILE"
else
    echo "No Augment log found" | tee -a "$LOGFILE"
fi
echo "" | tee -a "$LOGFILE"

# Step 5: Trace syscalls for 15 seconds to capture shared memory operations
echo "=== STEP 5: Tracing syscalls for 15 seconds ===" | tee -a "$LOGFILE"
echo "Looking for: memfd_create, openat(/dev/shm), unlink, mmap" | tee -a "$LOGFILE"
echo "This will capture the EXACT syscalls creating shared memory..." | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"

STRACE_LOG=".notes/strace-zygote-$(date +%Y%m%d-%H%M%S).log"
echo "Strace output will be saved to: $STRACE_LOG" | tee -a "$LOGFILE"

# Run strace with -f to follow threads, capture for 15 seconds
timeout 15 strace -f -p "$ZYGOTE_PID" -e trace=memfd_create,openat,unlink,mmap -s 200 -o "$STRACE_LOG" 2>&1 | tee -a "$LOGFILE" || true

echo "" | tee -a "$LOGFILE"
echo "Strace completed (or timed out)" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"

# Step 6: Analyze strace output
echo "=== STEP 6: Analyze strace output ===" | tee -a "$LOGFILE"
if [ -f "$STRACE_LOG" ]; then
    STRACE_LINES=$(wc -l < "$STRACE_LOG")
    echo "Strace captured $STRACE_LINES lines" | tee -a "$LOGFILE"
    echo "" | tee -a "$LOGFILE"
    
    echo "--- Searching for /dev/shm operations ---" | tee -a "$LOGFILE"
    grep -E "(shm|Chromium)" "$STRACE_LOG" | head -20 | tee -a "$LOGFILE" || echo "No /dev/shm operations found" | tee -a "$LOGFILE"
    echo "" | tee -a "$LOGFILE"
    
    echo "--- Searching for memfd_create ---" | tee -a "$LOGFILE"
    grep "memfd_create" "$STRACE_LOG" | head -10 | tee -a "$LOGFILE" || echo "No memfd_create calls found" | tee -a "$LOGFILE"
    echo "" | tee -a "$LOGFILE"
    
    echo "--- Searching for mmap ---" | tee -a "$LOGFILE"
    grep "mmap" "$STRACE_LOG" | head -10 | tee -a "$LOGFILE" || echo "No mmap calls found" | tee -a "$LOGFILE"
    echo "" | tee -a "$LOGFILE"
else
    echo "❌ Strace log file not created" | tee -a "$LOGFILE"
fi

# Step 7: Count leaked segments AFTER trace
echo "=== STEP 7: Count leaked segments AFTER trace ===" | tee -a "$LOGFILE"
LEAK_COUNT_AFTER=$(lsof -p "$ZYGOTE_PID" 2>/dev/null | grep -c "DEL.*shm.*Chromium" || echo "0")
echo "Leaked segments after trace: $LEAK_COUNT_AFTER" | tee -a "$LOGFILE"
echo "Change: $((LEAK_COUNT_AFTER - LEAK_COUNT))" | tee -a "$LOGFILE"
echo "" | tee -a "$LOGFILE"

# Step 8: Check RemoteAgentsMessenger activity
echo "=== STEP 8: Check RemoteAgentsMessenger activity ===" | tee -a "$LOGFILE"
if [ -n "$AUGMENT_LOG" ]; then
    echo "Recent RemoteAgentsMessenger events:" | tee -a "$LOGFILE"
    grep "RemoteAgentsMessenger" "$AUGMENT_LOG" | tail -10 | tee -a "$LOGFILE" || echo "No events found" | tee -a "$LOGFILE"
fi
echo "" | tee -a "$LOGFILE"

echo "========================================" | tee -a "$LOGFILE"
echo "FORENSIC TRACE COMPLETE" | tee -a "$LOGFILE"
echo "Main log: $LOGFILE" | tee -a "$LOGFILE"
echo "Strace log: $STRACE_LOG" | tee -a "$LOGFILE"
echo "========================================" | tee -a "$LOGFILE"

echo ""
echo "To view the full log:"
echo "  cat $LOGFILE"
echo ""
echo "To view the strace output:"
echo "  cat $STRACE_LOG"

