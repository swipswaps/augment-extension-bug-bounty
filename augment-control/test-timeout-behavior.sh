#!/usr/bin/env bash
# Test if AI can read output when command times out

echo "╔════════════════════════════════════════════════════════════════════════════╗"
echo "║                    TIMEOUT BEHAVIOR TEST                                   ║"
echo "╚════════════════════════════════════════════════════════════════════════════╝"
echo ""
echo "This script will:"
echo "  1. Print output immediately"
echo "  2. Sleep for 15 seconds (longer than typical timeout)"
echo "  3. Print final message"
echo ""
echo "If the patch works, the AI should see the first output even if timeout occurs."
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "START: timeout-test"
echo "✅ IMMEDIATE OUTPUT - If you see this, output capture works"
echo "⏱️  Now sleeping for 15 seconds..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

sleep 15

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ FINAL OUTPUT - If you see this, command completed without timeout"
echo "END: timeout-test"

