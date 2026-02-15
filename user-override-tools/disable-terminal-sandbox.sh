#!/usr/bin/env bash
# Disable VS Code 1.109+ terminal sandboxing to restore sudo functionality

set -euo pipefail

echo "╔════════════════════════════════════════════════════════════════════════════════╗"
echo "║                    DISABLE TERMINAL SANDBOXING                                 ║"
echo "║                                                                                ║"
echo "║  Disables VS Code 1.109+ terminal sandboxing to restore sudo functionality    ║"
echo "╚════════════════════════════════════════════════════════════════════════════════╝"
echo ""

SETTINGS_FILE="$HOME/.config/Code/User/settings.json"

echo "📄 VS Code settings file: $SETTINGS_FILE"
echo ""

# Check if settings file exists
if [ ! -f "$SETTINGS_FILE" ]; then
    echo "⚠️  Settings file doesn't exist, creating new one..."
    mkdir -p "$(dirname "$SETTINGS_FILE")"
    echo "{}" > "$SETTINGS_FILE"
fi

# Create backup
BACKUP_FILE="$SETTINGS_FILE.backup-$(date +%Y%m%d-%H%M%S)"
echo "💾 Creating backup: $BACKUP_FILE"
cp "$SETTINGS_FILE" "$BACKUP_FILE"
echo "   ✅ Backup created"
echo ""

# Check if setting already exists
if grep -q "chat.tools.terminal.sandbox.enabled" "$SETTINGS_FILE"; then
    echo "⚠️  Terminal sandbox setting already exists in settings.json"
    echo ""
    echo "Current value:"
    grep "chat.tools.terminal.sandbox.enabled" "$SETTINGS_FILE"
    echo ""
    read -p "Do you want to update it to false? (y/n) " -n 1 -r
    echo ""
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "❌ Cancelled"
        exit 1
    fi
    
    # Update existing setting
    sed -i.tmp 's/"chat.tools.terminal.sandbox.enabled".*/"chat.tools.terminal.sandbox.enabled": false,/' "$SETTINGS_FILE"
    rm -f "$SETTINGS_FILE.tmp"
else
    # Add new setting
    echo "➕ Adding terminal sandbox setting..."
    
    # Use Python to properly add the setting to JSON
    python3 << 'EOF'
import json
import sys

settings_file = sys.argv[1]

with open(settings_file, 'r') as f:
    settings = json.load(f)

settings["chat.tools.terminal.sandbox.enabled"] = False

with open(settings_file, 'w') as f:
    json.dump(settings, f, indent=2)

print("✅ Setting added")
EOF
fi

echo ""
echo "════════════════════════════════════════════════════════════════════════════════"
echo "✅ TERMINAL SANDBOXING DISABLED"
echo "════════════════════════════════════════════════════════════════════════════════"
echo ""
echo "⚠️  IMPORTANT: Reload VS Code for changes to take effect"
echo "   Press Ctrl+Shift+P → 'Developer: Reload Window'"
echo ""
echo "After reload, sudo should work normally in VS Code terminals."
echo ""
echo "To verify:"
echo "  sudo echo 'test'"
echo ""
echo "If you still get 'no new privileges' error, check:"
echo "  cat /proc/self/status | grep NoNewPrivs"
echo ""
echo "Expected: NoNewPrivs: 0"

