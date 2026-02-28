#!/usr/bin/env bash
# Detect Active Augment Extension Version

set -euo pipefail

echo "╔════════════════════════════════════════════════════════════════════════════╗"
echo "║                    AUGMENT VERSION DETECTION                               ║"
echo "╚════════════════════════════════════════════════════════════════════════════╝"
echo ""

# Get all installed versions
echo "Installed versions:"
ls -ld ~/.vscode/extensions/augment.vscode-augment-* | awk '{print $9}' | xargs -n1 basename
echo ""

# Get active version from VS Code
ACTIVE_VERSION=$(code --list-extensions --show-versions | grep augment | cut -d'@' -f2)
echo "Active version (per VS Code): $ACTIVE_VERSION"
echo ""

# Get extension directory
EXT_DIR="$HOME/.vscode/extensions/augment.vscode-augment-$ACTIVE_VERSION"

if [ ! -d "$EXT_DIR" ]; then
    echo "❌ Active extension directory not found: $EXT_DIR"
    exit 1
fi

echo "✅ Active extension directory: $EXT_DIR"
echo ""

# Check if it's pre-release
if [[ "$ACTIVE_VERSION" =~ ^0\.[0-9]+\.[0-9]+$ ]]; then
    echo "Type: RELEASE version"
else
    echo "Type: PRE-RELEASE version"
fi
echo ""

# Output for scripting
echo "ACTIVE_VERSION=$ACTIVE_VERSION"
echo "EXT_DIR=$EXT_DIR"

