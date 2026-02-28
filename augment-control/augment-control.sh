#!/usr/bin/env bash
# Unified Augment Control Script
# Orchestrates detection, patching, and recovery

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "╔════════════════════════════════════════════════════════════════════════════════╗"
echo "║                        AUGMENT CONTROL SYSTEM                                  ║"
echo "╚════════════════════════════════════════════════════════════════════════════════╝"
echo ""

# Step 1: Detect VS Code sandbox
echo "STEP 1: Detecting VS Code sandbox status..."
"$SCRIPT_DIR/detect-vscode-sandbox.sh"
SANDBOX_STATUS=$?
echo ""

# Step 2: Detect timeout blocking code
echo "STEP 2: Detecting timeout blocking code..."
"$SCRIPT_DIR/detect-timeout-block.sh"
echo ""

# Step 3: Freeze current extension
echo "STEP 3: Creating backup of current extension..."
"$SCRIPT_DIR/freeze-augment.sh"
echo ""

# Step 4: Check if jq is installed
echo "STEP 4: Checking dependencies..."
if ! command -v jq &> /dev/null; then
    echo "⚠️  jq is not installed"
    echo "   Install with: sudo dnf install jq -y"
    echo ""
    read -p "Install jq now? (y/n) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sudo dnf install jq -y
    else
        echo "❌ Cannot proceed without jq"
        exit 1
    fi
fi
echo "✅ Dependencies OK"
echo ""

# Step 5: Offer to disable sandbox if enabled
if [ $SANDBOX_STATUS -eq 0 ]; then
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo "⚠️  SANDBOX IS ENABLED"
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo ""
    echo "This prevents sudo from working in VS Code terminals."
    echo ""
    read -p "Disable terminal sandbox? (y/n) " -n 1 -r
    echo ""
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        "$SCRIPT_DIR/disable-vscode-sandbox.sh"
        echo ""
        echo "✅ Sandbox disabled"
        echo "⚠️  RESTART VS Code for changes to take effect"
    fi
fi

echo ""
echo "════════════════════════════════════════════════════════════════════════════════"
echo "✅ AUGMENT CONTROL COMPLETE"
echo "════════════════════════════════════════════════════════════════════════════════"
echo ""
echo "Summary:"
echo "  - Sandbox status: $([ $SANDBOX_STATUS -eq 0 ] && echo 'ENABLED' || echo 'DISABLED')"
echo "  - Extension backup: Created"
echo "  - Timeout blocks: Detected (see output above)"
echo ""
echo "Next steps:"
echo "  1. Review timeout block detection output"
echo "  2. If sandbox was disabled, restart VS Code"
echo "  3. Test with: bash /tmp/test-timeout-behavior.sh"
echo ""

