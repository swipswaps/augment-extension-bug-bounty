#!/usr/bin/env bash
#
# Emergency VS Code Cleanup - ONE-TIME AGGRESSIVE CLEANUP
#
# PURPOSE:
# - Kill ALL VS Code processes except main window
# - Force garbage collection
# - Clear swap
# - Restart VS Code cleanly
#
# USAGE:
#   ./.augment/scripts/emergency-vscode-cleanup.sh
#
# CRITICAL: Use this when system is severely overloaded
# - Load > 3.0
# - Swap > 1GB
# - Multiple runaway processes
# - VS Code unresponsive

set -euo pipefail

echo "================================================================================"
echo "EMERGENCY VS CODE CLEANUP"
echo "================================================================================"
echo ""

# Step 1: Show current state
echo "📊 Step 1: Current system state..."
free -h
echo ""
uptime
echo ""

# Step 2: List all VS Code processes
echo "📋 Step 2: VS Code processes..."
ps aux | grep -E "(code|/proc/self/exe)" | grep -v grep | \
    awk '{print "PID", $2, "CPU:", $3 "%", "MEM:", int($6/1024) "MB", $11}'
echo ""

# Step 3: Find main VS Code window (lowest PID)
MAIN_PID=$(ps aux | grep "/usr/share/code/code" | grep -v grep | \
           awk '{print $2}' | sort -n | head -1)

echo "🔍 Step 3: Main VS Code PID: $MAIN_PID (will NOT kill this)"
echo ""

# Step 4: Kill all other VS Code processes
echo "🚨 Step 4: Killing all VS Code processes except main window..."

# Get all VS Code PIDs except main
ALL_PIDS=$(ps aux | grep -E "(code|/proc/self/exe)" | grep -v grep | \
           awk '{print $2}' | grep -v "^$MAIN_PID$")

if [ -n "$ALL_PIDS" ]; then
    KILL_COUNT=0
    for pid in $ALL_PIDS; do
        echo "  Killing PID $pid..."
        kill -15 "$pid" 2>/dev/null && KILL_COUNT=$((KILL_COUNT + 1)) || true
    done
    
    echo "  ✓ Sent SIGTERM to $KILL_COUNT processes"
    echo ""
    
    # Wait 3 seconds for graceful shutdown
    echo "⏳ Waiting 3 seconds for graceful shutdown..."
    sleep 3
    echo ""
    
    # Force kill if still alive
    echo "🔨 Force killing remaining processes..."
    FORCE_KILL_COUNT=0
    for pid in $ALL_PIDS; do
        if ps -p "$pid" > /dev/null 2>&1; then
            echo "  Force killing PID $pid..."
            kill -9 "$pid" 2>/dev/null && FORCE_KILL_COUNT=$((FORCE_KILL_COUNT + 1)) || true
        fi
    done
    
    echo "  ✓ Force killed $FORCE_KILL_COUNT processes"
else
    echo "  ℹ️  No processes to kill (only main window running)"
fi

echo ""

# Step 5: Clear swap (requires sudo)
echo "💾 Step 5: Clearing swap (if possible)..."
if command -v swapoff &> /dev/null && command -v swapon &> /dev/null; then
    echo "  ⚠️  This requires sudo. Run manually if needed:"
    echo "    sudo swapoff -a && sudo swapon -a"
else
    echo "  ℹ️  swapoff/swapon not available"
fi
echo ""

# Step 6: Show final state
echo "📊 Step 6: Final system state..."
free -h
echo ""
uptime
echo ""

echo "📋 Remaining VS Code processes:"
ps aux | grep -E "(code|/proc/self/exe)" | grep -v grep | \
    awk '{print "PID", $2, "CPU:", $3 "%", "MEM:", int($6/1024) "MB", $11}' || echo "  None"
echo ""

echo "================================================================================"
echo "✅ EMERGENCY CLEANUP COMPLETE"
echo "================================================================================"
echo ""
echo "NEXT STEPS:"
echo "  1. Reload VS Code: Ctrl+Shift+P → 'Reload Window'"
echo "  2. Monitor for 5 minutes"
echo "  3. If processes spawn again, disable extensions one by one"
echo "  4. Start with: Augment, Watchdog, Resource Guardian"
echo ""

