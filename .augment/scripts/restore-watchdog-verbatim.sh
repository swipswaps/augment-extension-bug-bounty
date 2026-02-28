#!/usr/bin/env bash
set -euo pipefail

LOGFILE=".notes/restore-watchdog-$(date +%Y%m%d-%H%M%S).log"
mkdir -p .notes
exec > >(tee -a "$LOGFILE") 2>&1

echo "START: restore-watchdog-verbatim"
echo ""

# Find Augment extension logs
echo "📋 FINDING AUGMENT EXTENSION LOGS:"
AUGMENT_LOGS=$(find ~/.config/Code/logs -name "*Augment*" -type f 2>/dev/null)
if [ -z "$AUGMENT_LOGS" ]; then
    echo "  ⚠️  No Augment logs found"
else
    echo "$AUGMENT_LOGS" | while read logfile; do
        echo "  ✅ $(basename "$logfile")"
    done
fi
echo ""

# Show watchdog messages
echo "📊 WATCHDOG VERBATIM MESSAGES (last 50 lines):"
find ~/.config/Code/logs -name "*Augment*" -type f -exec tail -100 {} \; 2>/dev/null | \
    grep -E "TERMINAL OUTPUT|HEARTBEAT|Watchdog|INFO \|" | tail -50 || echo "  (no watchdog messages)"
echo ""

# Show terminal output logs
echo "📁 TERMINAL OUTPUT LOGS:"
find ~/.config/Code/logs -name "*Augment*" -type f -exec grep "TERMINAL OUTPUT" {} \; 2>/dev/null | tail -20 || echo "  (no terminal output logs)"
echo ""

# Show heartbeat messages
echo "💓 HEARTBEAT MESSAGES:"
find ~/.config/Code/logs -name "*Augment*" -type f -exec grep "HEARTBEAT" {} \; 2>/dev/null | tail -10 || echo "  (no heartbeat messages)"
echo ""

# Show terminal count tracking
echo "🔢 TERMINAL COUNT TRACKING:"
find ~/.config/Code/logs -name "*Augment*" -type f -exec grep "Terminal opened\|Terminal closed" {} \; 2>/dev/null | tail -20 || echo "  (no terminal tracking)"
echo ""

# Show cancellation tracking
echo "❌ CANCELLATION TRACKING:"
find ~/.config/Code/logs -name "*Augment*" -type f -exec grep "cancellation" {} \; 2>/dev/null | tail -10 || echo "  (no cancellation tracking)"
echo ""

# Verify watchdog is active
echo "═══════════════════════════════════════════════════════════════════"
echo "🔍 WATCHDOG STATUS"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

LATEST_HEARTBEAT=$(find ~/.config/Code/logs -name "*Augment*" -type f -exec grep "HEARTBEAT" {} \; 2>/dev/null | tail -1)
if [ -z "$LATEST_HEARTBEAT" ]; then
    echo "  ⚠️  NO HEARTBEAT DETECTED - Watchdog may not be active"
else
    echo "  ✅ Latest heartbeat:"
    echo "    $LATEST_HEARTBEAT"
fi
echo ""

LATEST_TERMINAL_OUTPUT=$(find ~/.config/Code/logs -name "*Augment*" -type f -exec grep "TERMINAL OUTPUT" {} \; 2>/dev/null | tail -1)
if [ -z "$LATEST_TERMINAL_OUTPUT" ]; then
    echo "  ⚠️  NO TERMINAL OUTPUT LOGGED - Watchdog may not be capturing"
else
    echo "  ✅ Latest terminal output:"
    echo "    $LATEST_TERMINAL_OUTPUT"
fi
echo ""

# Show full Augment log (last 100 lines)
echo "═══════════════════════════════════════════════════════════════════"
echo "📄 FULL AUGMENT LOG (last 100 lines)"
echo "═══════════════════════════════════════════════════════════════════"
echo ""
find ~/.config/Code/logs -name "*Augment*" -type f -exec tail -100 {} \; 2>/dev/null | tail -100
echo ""

echo "END: restore-watchdog-verbatim"

