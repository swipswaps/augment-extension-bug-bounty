#!/bin/bash
# WHAT: Install git hooks to enforce linting on commit
# WHY: Prevent commits with missing error handling patterns
# HOW: Copy pre-commit script to .git/hooks/

set -euo pipefail

echo "=========================================="
echo "INSTALL GIT HOOKS FOR MANDATORY LINTING"
echo "=========================================="
echo ""

# WHAT: Find git repository root
# WHY: .git/hooks directory is at repo root
# HOW: git rev-parse --show-toplevel
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || echo ".")

# WHAT: Check if we're in a git repository
# WHY: Can't install hooks without .git directory
# HOW: Test if .git exists
if [ ! -d "$REPO_ROOT/.git" ]; then
    echo "❌ Not a git repository - cannot install hooks"
    exit 1
fi

echo "Repository root: $REPO_ROOT"
echo ""

# WHAT: Create .git/hooks directory if it doesn't exist
# WHY: Some repos don't have hooks directory
# HOW: mkdir -p
mkdir -p "$REPO_ROOT/.git/hooks"

# WHAT: Copy pre-commit hook
# WHY: Git executes .git/hooks/pre-commit before allowing commit
# HOW: cp with executable permissions
echo "Installing pre-commit hook..."
cp "$REPO_ROOT/.augment/linting/pre-commit-lint.sh" "$REPO_ROOT/.git/hooks/pre-commit"
chmod +x "$REPO_ROOT/.git/hooks/pre-commit"
echo "✅ Pre-commit hook installed"
echo ""

# WHAT: Make linter executable
# WHY: Hook needs to execute linter script
# HOW: chmod +x
chmod +x "$REPO_ROOT/.augment/linting/mandatory-patterns.js"
echo "✅ Linter script made executable"
echo ""

echo "=========================================="
echo "INSTALLATION COMPLETE"
echo "=========================================="
echo ""
echo "WHAT: Git pre-commit hook now enforces mandatory patterns"
echo "WHY: Prevents commits with missing error handling"
echo "HOW: Runs .augment/linting/mandatory-patterns.js on staged .ts files"
echo ""
echo "PATTERNS ENFORCED:"
echo "  1. All exported functions must have try-catch"
echo "  2. All catch blocks must log to console.error"
echo "  3. All async functions must handle promise rejections"
echo "  4. All setInterval calls must be clearable"
echo ""
echo "TEST: Try committing a file without try-catch to see hook in action"
echo ""

