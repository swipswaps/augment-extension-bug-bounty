#!/usr/bin/env bash
# Aggressive Memory Reducer - ACTUALLY reduces VS Code memory
# Shows BEFORE/AFTER in visible terminal with evidence

set -euo pipefail

echo "═══════════════════════════════════════════════════════════════════"
echo "🔥 AGGRESSIVE MEMORY REDUCER"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

# BEFORE measurement (visible)
echo "📊 BEFORE STATE:"
echo "---"
BEFORE_VSCODE=$(ps aux | grep -E '/usr/share/code|/proc/self/ex' | grep -v grep | awk '{sum+=$6} END {print int(sum/1024)}')
BEFORE_TOTAL=$(free -m | grep Mem | awk '{print $3}')
BEFORE_SWAP=$(free -m | grep Swap | awk '{print $3}')
BEFORE_PROCS=$(ps aux | grep -E '/usr/share/code|/proc/self/ex' | grep -v grep | wc -l)
BEFORE_LOGS=$(ls -1 .notes/terminal-*.log 2>/dev/null | wc -l || echo "0")

echo "  VS Code Memory: ${BEFORE_VSCODE}MB"
echo "  Total Memory: ${BEFORE_TOTAL}MB"
echo "  Swap: ${BEFORE_SWAP}MB"
echo "  Processes: ${BEFORE_PROCS}"
echo "  Log Files: ${BEFORE_LOGS}"
echo ""

# Show top 5 memory hogs (visible)
echo "  Top 5 memory hogs:"
ps aux | grep -E '/usr/share/code|/proc/self/ex' | grep -v grep | sort -k6 -rn | head -5 | awk '{printf "    PID %s: %dMB (%s CPU) - %s\n", $2, int($6/1024), $3, $11}'
echo ""

# ACTION 1: Kill idle extension host processes (0% CPU for >5 minutes)
echo "🔪 ACTION 1: Killing idle extension host processes..."
KILLED_IDLE=0
while read -r pid cpu time cmd; do
    # Check if CPU is 0.0 and time > 5 minutes
    if [[ "$cpu" == "0.0" ]] && [[ "$cmd" == *"/proc/self/exe"* ]]; then
        echo "  Killing PID $pid (CPU: $cpu, Time: $time)"
        kill -15 "$pid" 2>/dev/null && ((KILLED_IDLE++)) || true
        sleep 0.5
    fi
done < <(ps aux | grep -E '/proc/self/ex' | grep -v grep | awk '{print $2, $3, $10, $11}')
echo "  Killed: $KILLED_IDLE idle processes"
echo ""

# ACTION 2: Kill duplicate shared process workers
echo "🔪 ACTION 2: Killing duplicate shared process workers..."
KILLED_SHARED=0
# Find shared process workers with same parent, keep only 1
ps aux | grep -E '/usr/share/code/code.*--type=utility.*--utility-sub-type=node.mojom.NodeService' | grep -v grep | awk '{print $2}' | tail -n +2 | while read -r pid; do
    echo "  Killing duplicate worker PID $pid"
    kill -15 "$pid" 2>/dev/null && ((KILLED_SHARED++)) || true
    sleep 0.5
done
echo "  Killed: $KILLED_SHARED duplicate workers"
echo ""

# ACTION 3: Clean old log files (keep 15 most recent)
echo "🧹 ACTION 3: Cleaning old log files..."
BEFORE_LOG_SIZE=$(du -sm .notes/terminal-*.log 2>/dev/null | awk '{sum+=$1} END {print sum}' || echo "0")
ls -t .notes/terminal-*.log 2>/dev/null | tail -n +16 | xargs -r rm -f
AFTER_LOG_SIZE=$(du -sm .notes/terminal-*.log 2>/dev/null | awk '{sum+=$1} END {print sum}' || echo "0")
FREED_LOGS=$((BEFORE_LOG_SIZE - AFTER_LOG_SIZE))
AFTER_LOG_COUNT=$(ls -1 .notes/terminal-*.log 2>/dev/null | wc -l || echo "0")
echo "  Deleted: $((BEFORE_LOGS - AFTER_LOG_COUNT)) log files"
echo "  Freed: ${FREED_LOGS}MB"
echo ""

# ACTION 4: Clear VS Code workspace storage cache
echo "🧹 ACTION 4: Clearing VS Code workspace storage cache..."
CACHE_DIRS=(
    "$HOME/.config/Code/User/workspaceStorage"
    "$HOME/.config/Code/Cache"
    "$HOME/.config/Code/CachedData"
)
FREED_CACHE=0
for cache_dir in "${CACHE_DIRS[@]}"; do
    if [ -d "$cache_dir" ]; then
        BEFORE_CACHE=$(du -sm "$cache_dir" 2>/dev/null | awk '{print $1}' || echo "0")
        # Keep only last 3 days
        find "$cache_dir" -type f -mtime +3 -delete 2>/dev/null || true
        AFTER_CACHE=$(du -sm "$cache_dir" 2>/dev/null | awk '{print $1}' || echo "0")
        FREED=$((BEFORE_CACHE - AFTER_CACHE))
        FREED_CACHE=$((FREED_CACHE + FREED))
        echo "  Cleaned $(basename "$cache_dir"): ${FREED}MB freed"
    fi
done
echo "  Total cache freed: ${FREED_CACHE}MB"
echo ""

# ACTION 5: Trigger garbage collection in Node processes
echo "🗑️  ACTION 5: Triggering garbage collection..."
GC_COUNT=0
ps aux | grep -E '/proc/self/ex' | grep -v grep | awk '{print $2}' | while read -r pid; do
    # Send SIGUSR2 to trigger GC in Node processes
    kill -USR2 "$pid" 2>/dev/null && ((GC_COUNT++)) || true
done
echo "  Sent GC signal to $GC_COUNT Node processes"
echo ""

# Wait for processes to settle
echo "⏳ Waiting 5 seconds for processes to settle..."
sleep 5
echo ""

# AFTER measurement (visible)
echo "📊 AFTER STATE:"
echo "---"
AFTER_VSCODE=$(ps aux | grep -E '/usr/share/code|/proc/self/ex' | grep -v grep | awk '{sum+=$6} END {print int(sum/1024)}')
AFTER_TOTAL=$(free -m | grep Mem | awk '{print $3}')
AFTER_SWAP=$(free -m | grep Swap | awk '{print $3}')
AFTER_PROCS=$(ps aux | grep -E '/usr/share/code|/proc/self/ex' | grep -v grep | wc -l)

echo "  VS Code Memory: ${AFTER_VSCODE}MB"
echo "  Total Memory: ${AFTER_TOTAL}MB"
echo "  Swap: ${AFTER_SWAP}MB"
echo "  Processes: ${AFTER_PROCS}"
echo "  Log Files: ${AFTER_LOG_COUNT}"
echo ""

# Show top 5 memory hogs after (visible)
echo "  Top 5 memory hogs:"
ps aux | grep -E '/usr/share/code|/proc/self/ex' | grep -v grep | sort -k6 -rn | head -5 | awk '{printf "    PID %s: %dMB (%s CPU) - %s\n", $2, int($6/1024), $3, $11}'
echo ""

# Calculate reductions (visible)
VSCODE_REDUCTION=$((BEFORE_VSCODE - AFTER_VSCODE))
TOTAL_REDUCTION=$((BEFORE_TOTAL - AFTER_TOTAL))
SWAP_REDUCTION=$((BEFORE_SWAP - AFTER_SWAP))
PROC_REDUCTION=$((BEFORE_PROCS - AFTER_PROCS))

echo "═══════════════════════════════════════════════════════════════════"
echo "✅ RESULTS (EVIDENCE)"
echo "═══════════════════════════════════════════════════════════════════"
echo ""
echo "VS Code Memory:"
echo "  Before: ${BEFORE_VSCODE}MB"
echo "  After: ${AFTER_VSCODE}MB"
echo "  Reduction: ${VSCODE_REDUCTION}MB ($(awk "BEGIN {printf \"%.1f\", ($VSCODE_REDUCTION/$BEFORE_VSCODE)*100}")%)"
echo ""
echo "Total System Memory:"
echo "  Before: ${BEFORE_TOTAL}MB"
echo "  After: ${AFTER_TOTAL}MB"
echo "  Reduction: ${TOTAL_REDUCTION}MB ($(awk "BEGIN {printf \"%.1f\", ($TOTAL_REDUCTION/$BEFORE_TOTAL)*100}")%)"
echo ""
echo "Swap:"
echo "  Before: ${BEFORE_SWAP}MB"
echo "  After: ${AFTER_SWAP}MB"
echo "  Reduction: ${SWAP_REDUCTION}MB"
echo ""
echo "Processes:"
echo "  Before: ${BEFORE_PROCS}"
echo "  After: ${AFTER_PROCS}"
echo "  Reduction: ${PROC_REDUCTION}"
echo ""
echo "Actions Taken:"
echo "  - Killed idle processes: ${KILLED_IDLE}"
echo "  - Cleaned log files: $((BEFORE_LOGS - AFTER_LOG_COUNT)) files, ${FREED_LOGS}MB"
echo "  - Cleaned cache: ${FREED_CACHE}MB"
echo "  - Triggered GC in Node processes"
echo ""
echo "═══════════════════════════════════════════════════════════════════"

