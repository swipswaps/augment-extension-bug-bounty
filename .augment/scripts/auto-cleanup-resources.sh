#!/usr/bin/env bash
# Auto-cleanup resources when thresholds exceeded
# Usage: bash .augment/scripts/auto-cleanup-resources.sh

set -euo pipefail

echo "═══════════════════════════════════════════════════════════════════"
echo "🔍 RESOURCE USAGE CHECK"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

# Check log file count
LOG_COUNT=$(ls -1 .notes/terminal-*.log 2>/dev/null | wc -l)
echo "📁 Log files: $LOG_COUNT"

if [ $LOG_COUNT -gt 25 ]; then
    echo "  ⚠️  Threshold exceeded (25)"
    echo "  🧹 Running cleanup..."
    bash .augment/scripts/cleanup-old-logs.sh
    NEW_COUNT=$(ls -1 .notes/terminal-*.log 2>/dev/null | wc -l)
    echo "  ✅ Cleanup complete: $LOG_COUNT → $NEW_COUNT files"
else
    echo "  ✅ Within threshold (25)"
fi

echo ""

# Check VS Code memory
TOTAL_MEM=$(ps aux | grep -E "/usr/share/code|/proc/self/ex" | grep -v grep | awk '{sum+=$6} END {print int(sum/1024)}' || echo "0")
echo "💾 VS Code memory: ${TOTAL_MEM} MB"

if [ $TOTAL_MEM -gt 4000 ]; then
    echo "  ⚠️  Threshold exceeded (4000 MB)"
    echo "  💡 Recommendation: Reload VS Code window"
    echo "     Press Ctrl+Shift+P → 'Developer: Reload Window'"
    echo "     Expected reduction: 30-40% memory, 60% CPU"
else
    echo "  ✅ Within threshold (4000 MB)"
fi

echo ""

# Check process count
PROC_COUNT=$(ps aux | grep -E "/usr/share/code|/proc/self/ex" | grep -v grep | wc -l || echo "0")
echo "🔢 VS Code processes: $PROC_COUNT"

if [ $PROC_COUNT -gt 15 ]; then
    echo "  ⚠️  Threshold exceeded (15)"
    echo "  💡 Recommendation: Close unused VS Code windows"
    echo "     Or disable unused extensions"
else
    echo "  ✅ Within threshold (15)"
fi

echo ""

# Check swap usage
SWAP_USED=$(free -m | grep Swap | awk '{print $3}')
SWAP_TOTAL=$(free -m | grep Swap | awk '{print $2}')
SWAP_PCT=$(awk "BEGIN {printf \"%.1f\", ($SWAP_USED/$SWAP_TOTAL)*100}")
echo "💿 Swap usage: ${SWAP_USED} MB / ${SWAP_TOTAL} MB (${SWAP_PCT}%)"

if [ $SWAP_USED -gt 1000 ]; then
    echo "  ⚠️  High swap usage (> 1000 MB)"
    echo "  💡 Recommendation: Close applications or add more RAM"
else
    echo "  ✅ Normal swap usage"
fi

echo ""
echo "═══════════════════════════════════════════════════════════════════"
echo "✅ RESOURCE CHECK COMPLETE"
echo "═══════════════════════════════════════════════════════════════════"

exit 0

