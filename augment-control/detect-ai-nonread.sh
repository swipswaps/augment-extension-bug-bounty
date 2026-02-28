#!/usr/bin/env bash
# Detect AI Non-Read Behavior
# Checks if Augment claimed "no output" but files exist on disk

set -euo pipefail

BASE_DIR="$HOME/.edc/runs"

if [ ! -d "$BASE_DIR" ]; then
    echo "❌ No runs found - EDC not used yet"
    echo "Run commands via: ./run-tool.sh '<command>'"
    exit 1
fi

LATEST_RUN=$(ls -td "$BASE_DIR"/* 2>/dev/null | head -1)

if [ -z "$LATEST_RUN" ]; then
    echo "❌ No runs found"
    exit 1
fi

echo "╔════════════════════════════════════════════════════════════════════════════╗"
echo "║                    AI NON-READ DETECTOR                                    ║"
echo "╚════════════════════════════════════════════════════════════════════════════╝"
echo ""
echo "Inspecting: $LATEST_RUN"
echo ""

STDOUT_FILE="$LATEST_RUN/stdout.txt"
STDERR_FILE="$LATEST_RUN/stderr.txt"
META_FILE="$LATEST_RUN/meta.txt"

# Read metadata
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "METADATA"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
cat "$META_FILE"
echo ""

# Check file sizes
STDOUT_SIZE=$(wc -c < "$STDOUT_FILE")
STDERR_SIZE=$(wc -c < "$STDERR_FILE")

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "OUTPUT VERIFICATION"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "STDOUT size: $STDOUT_SIZE bytes"
echo "STDERR size: $STDERR_SIZE bytes"
echo ""

# Determine if AI should have read output
if [ "$STDOUT_SIZE" -gt 0 ]; then
    echo "✅ STDOUT EXISTS ON DISK ($STDOUT_SIZE bytes)"
    echo ""
    echo "⚠️  AI MUST READ THIS OUTPUT"
    echo ""
    echo "If AI claims 'no output captured', that is a VIOLATION."
    echo ""
    echo "STDOUT preview (first 20 lines):"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    head -20 "$STDOUT_FILE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
else
    echo "❌ STDOUT IS EMPTY"
fi

if [ "$STDERR_SIZE" -gt 0 ]; then
    echo ""
    echo "⚠️  STDERR EXISTS ($STDERR_SIZE bytes)"
    echo ""
    echo "STDERR preview (first 20 lines):"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    head -20 "$STDERR_FILE"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "COMPLIANCE CHECK"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

STATE=$(grep "^state=" "$META_FILE" | cut -d= -f2)

if [ "$STATE" = "TIMEOUT" ] && [ "$STDOUT_SIZE" -gt 0 ]; then
    echo "🔴 CRITICAL: Command timed out BUT output exists"
    echo ""
    echo "AI MUST:"
    echo "  1. Acknowledge timeout occurred"
    echo "  2. Read and show STDOUT content"
    echo "  3. NOT claim 'no output captured'"
    echo ""
    echo "Forensic truth: $STDOUT_FILE exists with $STDOUT_SIZE bytes"
elif [ "$STDOUT_SIZE" -eq 0 ] && [ "$STDERR_SIZE" -eq 0 ]; then
    echo "✅ No output captured (both stdout and stderr empty)"
else
    echo "✅ Output exists - AI should read and present it"
fi

echo ""
echo "Full files available at:"
echo "  $STDOUT_FILE"
echo "  $STDERR_FILE"
echo "  $META_FILE"

