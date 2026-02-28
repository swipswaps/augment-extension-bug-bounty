#!/bin/bash
# WHAT: Pre-commit hook to enforce mandatory error handling patterns
# WHY: Prevent commits that introduce silent failures
# HOW: Run custom linter before allowing commit

set -euo pipefail

# WHAT: Color codes for output
# WHY: Visual distinction between pass/fail
# HOW: ANSI escape codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=========================================="
echo "PRE-COMMIT LINTING"
echo "=========================================="
echo ""

# WHAT: Find all staged TypeScript files
# WHY: Only lint files being committed
# HOW: git diff --cached --name-only --diff-filter=ACM
STAGED_TS_FILES=$(git diff --cached --name-only --diff-filter=ACM | grep '\.ts$' | grep -v '\.d\.ts$' || true)

if [ -z "$STAGED_TS_FILES" ]; then
    echo -e "${GREEN}✅ No TypeScript files staged - skipping lint${NC}"
    exit 0
fi

echo "Staged TypeScript files:"
echo "$STAGED_TS_FILES"
echo ""

# WHAT: Run custom mandatory pattern linter
# WHY: Enforce error handling patterns
# HOW: Execute Node.js linter script
echo "Running mandatory pattern checks..."
echo ""

VIOLATIONS=0

for FILE in $STAGED_TS_FILES; do
    if [ -f "$FILE" ]; then
        # WHAT: Lint individual file
        # WHY: Check for mandatory patterns
        # HOW: Call linter with file path
        if ! node .augment/linting/mandatory-patterns.js "$FILE" 2>&1; then
            VIOLATIONS=$((VIOLATIONS + 1))
        fi
    fi
done

echo ""

if [ "$VIOLATIONS" -gt 0 ]; then
    echo -e "${RED}❌ COMMIT BLOCKED - Fix violations above${NC}"
    echo ""
    echo "MANDATORY PATTERNS REQUIRED:"
    echo "  1. All exported functions must have try-catch"
    echo "  2. All catch blocks must log to console.error"
    echo "  3. All async functions must handle promise rejections"
    echo "  4. All setInterval calls must be clearable"
    echo ""
    echo "WHY: These patterns prevent silent failures that waste user time"
    echo ""
    exit 1
else
    echo -e "${GREEN}✅ All mandatory patterns present - commit allowed${NC}"
    exit 0
fi

