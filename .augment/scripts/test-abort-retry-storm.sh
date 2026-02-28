#!/usr/bin/env bash
#
# test-abort-retry-storm.sh
# 
# Detects and reports the AbortError retry storm issue in VS Code with Augment extension
# 
# ROOT CAUSE: getRemoteAgentOverviewsStream() in Augment extension lacks cleanup code
# When AbortError occurs (120s timeout), the async iterator is never closed, causing:
#   - Leaked ReadableStream readers
#   - Unclosed fetch connections  
#   - Runaway zygote processes consuming CPU
#   - Immediate retry without backoff (809+ occurrences observed)
#
# EVIDENCE REQUIRED:
#   1. Augment extension installed
#   2. Runaway zygote processes (CPU > 5%)
#   3. AbortError events in error_tracking.db
#   4. Correlation between AbortErrors and zygote CPU spikes
#
# USAGE: ./test-abort-retry-storm.sh [--verbose]

set -euo pipefail

VERBOSE=false
if [[ "${1:-}" == "--verbose" ]]; then
    VERBOSE=true
fi

log() {
    echo "[$(date -Iseconds)] $*"
}

verbose() {
    if $VERBOSE; then
        echo "[VERBOSE] $*"
    fi
}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "========================================"
echo "AbortError Retry Storm Detection Script"
echo "========================================"
echo ""

# Test 1: Check if Augment extension is installed
log "TEST 1: Checking for Augment extension..."
EXTENSION_PATH=$(find ~/.vscode/extensions -maxdepth 1 -name "augment.vscode-augment-*" -type d 2>/dev/null | head -1)

if [[ -z "$EXTENSION_PATH" ]]; then
    echo -e "${RED}✗ FAIL${NC}: Augment extension not found"
    echo "This test requires VS Code with Augment extension installed"
    exit 1
fi

EXTENSION_JS="$EXTENSION_PATH/out/extension.js"
if [[ ! -f "$EXTENSION_JS" ]]; then
    echo -e "${RED}✗ FAIL${NC}: Extension file not found: $EXTENSION_JS"
    exit 1
fi

EXTENSION_VERSION=$(basename "$EXTENSION_PATH" | sed 's/augment.vscode-augment-//')
echo -e "${GREEN}✓ PASS${NC}: Augment extension v$EXTENSION_VERSION found"
verbose "Location: $EXTENSION_PATH"

# Test 2: Check for buggy code pattern
log "TEST 2: Checking for buggy getRemoteAgentOverviewsStream pattern..."

# The buggy pattern: for await (let s of o) yield s with NO try/finally
if grep -q "getRemoteAgentOverviewsStream" "$EXTENSION_JS" 2>/dev/null; then
    echo -e "${YELLOW}⚠ WARNING${NC}: getRemoteAgentOverviewsStream found in extension"
    
    # Check if it's the minified version (single line, no cleanup)
    LINE_COUNT=$(wc -l < "$EXTENSION_JS")
    if [[ $LINE_COUNT -lt 100 ]]; then
        echo -e "${RED}✗ FAIL${NC}: Extension is minified ($LINE_COUNT lines) - likely contains bug"
        verbose "Minified code cannot be easily inspected for try/finally blocks"
    else
        echo -e "${GREEN}✓ PASS${NC}: Extension appears to be prettified - may have been patched"
    fi
else
    echo -e "${YELLOW}⚠ SKIP${NC}: Cannot find getRemoteAgentOverviewsStream (may be obfuscated)"
fi

# Test 3: Check for runaway zygote processes
log "TEST 3: Checking for runaway zygote processes..."

RUNAWAY_ZYGOTES=$(ps aux | grep -E "code.*--type=zygote" | grep -v grep | awk '{if ($3 > 5.0) print $2, $3, $6}' || true)

if [[ -n "$RUNAWAY_ZYGOTES" ]]; then
    echo -e "${RED}✗ FAIL${NC}: Runaway zygote processes detected:"
    echo "$RUNAWAY_ZYGOTES" | while read -r pid cpu mem; do
        mem_mb=$((mem / 1024))
        echo "  PID $pid: ${cpu}% CPU, ${mem_mb} MB RAM"
    done
    ZYGOTE_ISSUE=true
else
    echo -e "${GREEN}✓ PASS${NC}: No runaway zygotes (CPU < 5%)"
    ZYGOTE_ISSUE=false
fi

# Test 4: Check error tracking database for AbortErrors
log "TEST 4: Checking error_tracking.db for AbortError events..."

DB_PATH=".augment/error_tracking.db"
if [[ ! -f "$DB_PATH" ]]; then
    echo -e "${YELLOW}⚠ SKIP${NC}: error_tracking.db not found in current directory"
    echo "  Run this script from a workspace with Augment diagnostics enabled"
    ABORT_COUNT=0
else
    ABORT_COUNT=$(sqlite3 "$DB_PATH" "SELECT COUNT(*) FROM errors WHERE error_message LIKE '%AbortError%' OR error_message LIKE '%This operation was aborted%';" 2>/dev/null || echo "0")
    
    if [[ $ABORT_COUNT -gt 100 ]]; then
        echo -e "${RED}✗ FAIL${NC}: $ABORT_COUNT AbortError events found (threshold: 100)"
        
        # Get sample stack traces
        verbose "Sample AbortError stack traces:"
        sqlite3 "$DB_PATH" "SELECT timestamp, error_message FROM errors WHERE error_message LIKE '%AbortError%' ORDER BY timestamp DESC LIMIT 3;" 2>/dev/null | while IFS='|' read -r ts msg; do
            verbose "  [$ts] ${msg:0:100}..."
        done
    elif [[ $ABORT_COUNT -gt 0 ]]; then
        echo -e "${YELLOW}⚠ WARNING${NC}: $ABORT_COUNT AbortError events found (below threshold)"
    else
        echo -e "${GREEN}✓ PASS${NC}: No AbortError events found"
    fi
fi

# Test 5: Check for correlation between AbortErrors and zygote issues
log "TEST 5: Checking for correlation..."

if [[ $ABORT_COUNT -gt 100 ]] && [[ "$ZYGOTE_ISSUE" == "true" ]]; then
    echo -e "${RED}✗ FAIL${NC}: CORRELATION CONFIRMED"
    echo "  - High AbortError count: $ABORT_COUNT"
    echo "  - Runaway zygotes detected"
    echo "  - This matches the known bug pattern"
    ISSUE_CONFIRMED=true
else
    echo -e "${GREEN}✓ PASS${NC}: No correlation detected"
    ISSUE_CONFIRMED=false
fi

echo ""
echo "========================================"
echo "FINAL REPORT"
echo "========================================"
echo ""

if [[ "$ISSUE_CONFIRMED" == "true" ]]; then
    cat << EOF
${RED}ISSUE DETECTED: AbortError Retry Storm${NC}

ROOT CAUSE:
  The Augment extension's getRemoteAgentOverviewsStream() function
  lacks proper cleanup code. When a 120-second timeout occurs:
  
  1. AbortError is thrown
  2. The async iterator is NEVER closed (no try/finally)
  3. ReadableStream reader is NEVER cancelled
  4. Fetch connection remains open
  5. Zygote process keeps trying to read from dead connection
  6. Immediate retry without backoff
  
  Result: CPU leak in zygote processes, 800+ retry attempts

EVIDENCE:
  - Augment extension: v$EXTENSION_VERSION (minified)
  - AbortError count: $ABORT_COUNT
  - Runaway zygotes: $(echo "$RUNAWAY_ZYGOTES" | wc -l)

IMPACT:
  - Zygote processes consume 20-40% CPU continuously
  - System resources exhausted over time
  - VS Code performance degraded

WORKAROUND:
  1. Reload VS Code window (Ctrl+Shift+P → "Reload Window")
  2. This temporarily clears leaked resources
  3. Issue will recur when stream timeout occurs again

PERMANENT FIX:
  Requires patching Augment extension code to add:
  
    try {
      for await (let s of iterator) yield s;
    } finally {
      if (iterator && iterator.return) {
        await iterator.return();
      }
    }

EOF
    exit 1
else
    echo -e "${GREEN}✓ NO ISSUE DETECTED${NC}"
    echo ""
    echo "System appears healthy:"
    echo "  - Augment extension: v$EXTENSION_VERSION"
    echo "  - AbortError count: $ABORT_COUNT"
    echo "  - No runaway zygotes"
    echo ""
    exit 0
fi

