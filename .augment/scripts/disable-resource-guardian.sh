#!/usr/bin/env bash
#
# Disable Resource Guardian Extension - IMMEDIATE
#
# PURPOSE:
# - Resource Guardian is TOO AGGRESSIVE
# - Killing processes VS Code needs
# - Causing VS Code to crash/close
# - Need to disable extension NOW
#
# ROOT CAUSE:
# - Extension monitoring every 5 seconds
# - Killing zygote processes that are NORMAL during startup
# - VS Code spawns new processes, extension kills them
# - Infinite loop of spawn → kill → crash
#
# SOLUTION:
# - Disable Resource Guardian extension
# - Use manual cleanup scripts instead
# - Only kill processes when load > 3.0

set -euo pipefail

echo "================================================================================"
echo "DISABLE RESOURCE GUARDIAN EXTENSION"
echo "================================================================================"
echo ""

# Step 1: Find Resource Guardian extension
echo "🔍 Step 1: Finding Resource Guardian extension..."
EXTENSION_DIR="$HOME/.vscode/extensions"
GUARDIAN_EXT=$(find "$EXTENSION_DIR" -maxdepth 1 -name "*resource-guardian*" 2>/dev/null | head -1)

if [ -n "$GUARDIAN_EXT" ]; then
    echo "  Found: $GUARDIAN_EXT"
    echo ""
    
    # Step 2: Disable by renaming
    echo "🚫 Step 2: Disabling extension..."
    mv "$GUARDIAN_EXT" "${GUARDIAN_EXT}.DISABLED" 2>/dev/null || true
    echo "  ✓ Extension disabled (renamed to .DISABLED)"
else
    echo "  ℹ️  Resource Guardian not found in extensions directory"
    echo "  Checking if installed via symlink..."
    
    # Check for symlink
    SYMLINK=$(find "$EXTENSION_DIR" -maxdepth 1 -type l -name "*resource-guardian*" 2>/dev/null | head -1)
    if [ -n "$SYMLINK" ]; then
        echo "  Found symlink: $SYMLINK"
        rm "$SYMLINK"
        echo "  ✓ Symlink removed"
    else
        echo "  ℹ️  Extension not installed"
    fi
fi

echo ""

# Step 3: Kill any running monitoring processes
echo "🔪 Step 3: Stopping monitoring processes..."
pkill -f "kill-vscode-runaway" 2>/dev/null && echo "  ✓ Stopped kill-vscode-runaway.sh" || echo "  ℹ️  No monitoring processes running"
echo ""

# Step 4: Show current VS Code processes
echo "📋 Step 4: Current VS Code processes..."
ps aux | grep -E "(code|/proc/self/exe)" | grep -v grep | \
    awk '{print "PID", $2, "CPU:", $3 "%", "MEM:", int($6/1024) "MB"}' | head -10
echo ""

echo "================================================================================"
echo "✅ RESOURCE GUARDIAN DISABLED"
echo "================================================================================"
echo ""
echo "NEXT STEPS:"
echo "  1. Reload VS Code: Ctrl+Shift+P → 'Reload Window'"
echo "  2. Let VS Code stabilize for 2 minutes"
echo "  3. Monitor with: watch -n 5 'ps aux | grep code | grep -v grep'"
echo "  4. Only kill processes manually if load > 3.0"
echo ""
echo "MANUAL CLEANUP (when needed):"
echo "  ./.augment/scripts/emergency-vscode-cleanup.sh"
echo ""

