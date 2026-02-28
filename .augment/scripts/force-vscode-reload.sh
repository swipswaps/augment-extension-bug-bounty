#!/bin/bash
# Force VS Code to Reload and Release Memory
# WHY: Settings changes don't take effect until VS Code reloads
# WHAT: Kills extension host processes to force clean restart

set -euo pipefail

echo "🔥 FORCE VS CODE RELOAD - MEMORY LEAK FIX"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Check current memory
echo "📊 Current VS Code memory usage:"
ps aux | grep "code" | grep -v grep | grep -E "(zygote|extensionHost)" | awk '{printf "  PID %s: %sMB RES, %s%% CPU - %s\n", $2, int($6/1024), $3, $11}'

TOTAL_MEM_BEFORE=$(ps aux | grep "code.*zygote" | grep -v grep | awk '{sum+=$6} END {print int(sum/1024)}')
echo ""
echo "📈 Total memory before: ${TOTAL_MEM_BEFORE}MB"
echo ""

# Warn user
echo "⚠️  WARNING: This will kill VS Code extension host processes"
echo "⚠️  VS Code will automatically restart them with new settings"
echo "⚠️  You may see a brief notification in VS Code"
echo ""
read -p "Continue? (y/N): " -n 1 -r
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Cancelled by user"
    exit 0
fi

echo ""
echo "🔧 Step 1: Killing extension host processes..."

# Kill extension host processes (VS Code will auto-restart them)
pkill -f "extensionHost" 2>/dev/null && echo "  ✅ Extension host killed" || echo "  ℹ️  No extension host found"

# Kill shared process (handles file watching)
pkill -f "code.*shared-process" 2>/dev/null && echo "  ✅ Shared process killed" || echo "  ℹ️  No shared process found"

echo ""
echo "⏳ Waiting 3 seconds for VS Code to restart processes..."
sleep 3

echo ""
echo "🔧 Step 2: Verifying new memory usage..."

# Check memory after reload
TOTAL_MEM_AFTER=$(ps aux | grep "code.*zygote" | grep -v grep | awk '{sum+=$6} END {print int(sum/1024)}')

echo ""
echo "📊 New VS Code memory usage:"
ps aux | grep "code" | grep -v grep | grep -E "(zygote|extensionHost)" | awk '{printf "  PID %s: %sMB RES, %s%% CPU - %s\n", $2, int($6/1024), $3, $11}'

echo ""
echo "📉 Total memory after: ${TOTAL_MEM_AFTER}MB"

# Calculate savings
SAVINGS=$((TOTAL_MEM_BEFORE - TOTAL_MEM_AFTER))
PERCENT_SAVED=$(awk "BEGIN {printf \"%.1f\", ($SAVINGS / $TOTAL_MEM_BEFORE) * 100}")

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ VS Code reload complete"
echo "💾 Memory saved: ${SAVINGS}MB (${PERCENT_SAVED}%)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "📝 VERIFICATION:"
echo "  1. Check VS Code is still responsive"
echo "  2. Verify .notes directory is excluded from search"
echo "  3. Monitor memory: watch -n 5 'ps aux | grep code | grep zygote'"
echo ""

exit 0

