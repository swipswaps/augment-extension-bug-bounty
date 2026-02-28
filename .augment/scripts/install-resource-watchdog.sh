#!/usr/bin/env bash
# Install resource watchdog into hidden-terminal-watchdog extension
# Production installation script

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WATCHDOG_REPO="./hidden-terminal-watchdog"
INSTALL_TARGET="$WATCHDOG_REPO/src/resource-watchdog.sh"

echo "═══════════════════════════════════════════════════════════════════"
echo "🔧 INSTALLING RESOURCE WATCHDOG"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

# Check if watchdog repo exists
if [ ! -d "$WATCHDOG_REPO" ]; then
    echo "❌ ERROR: hidden-terminal-watchdog repo not found at $WATCHDOG_REPO"
    exit 1
fi

# Create src directory if needed
mkdir -p "$WATCHDOG_REPO/src"

# Copy resource watchdog
echo "📋 Copying resource-watchdog.sh..."
cp "$SCRIPT_DIR/resource-watchdog.sh" "$INSTALL_TARGET"
chmod +x "$INSTALL_TARGET"
echo "✅ Installed to $INSTALL_TARGET"
echo ""

# Create systemd service file
echo "📋 Creating systemd service..."
cat > "$WATCHDOG_REPO/resource-watchdog.service" <<'EOF'
[Unit]
Description=VS Code Resource Watchdog
After=graphical.target

[Service]
Type=simple
ExecStart=/bin/bash %h/Documents/6984bd27-4494-8330-9803-7b6895a48aa5/hidden-terminal-watchdog/src/resource-watchdog.sh
WorkingDirectory=%h/Documents/6984bd27-4494-8330-9803-7b6895a48aa5
Restart=always
RestartSec=10

[Install]
WantedBy=default.target
EOF
echo "✅ Created resource-watchdog.service"
echo ""

# Create installation instructions
cat > "$WATCHDOG_REPO/INSTALL_RESOURCE_WATCHDOG.md" <<'EOF'
# Resource Watchdog Installation

## Quick Start

```bash
# Install as systemd user service
mkdir -p ~/.config/systemd/user
cp resource-watchdog.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user enable resource-watchdog
systemctl --user start resource-watchdog

# Check status
systemctl --user status resource-watchdog

# View logs
journalctl --user -u resource-watchdog -f
```

## Manual Start

```bash
# Run once
bash src/resource-watchdog.sh --once

# Run continuously
bash src/resource-watchdog.sh
```

## Configuration

Edit `src/resource-watchdog.sh`:

```bash
MEMORY_THRESHOLD_MB=4000    # Trigger cleanup at 4GB
LOG_FILE_THRESHOLD=25       # Trigger cleanup at 25 log files
PROCESS_THRESHOLD=20        # Trigger cleanup at 20 processes
CHECK_INTERVAL=60           # Check every 60 seconds
```

## Database Queries

```bash
# View recent checks
sqlite3 .augment/resource_watchdog.db "SELECT * FROM resource_checks ORDER BY id DESC LIMIT 10;"

# View cleanup actions
sqlite3 .augment/resource_watchdog.db "SELECT * FROM cleanup_actions ORDER BY id DESC LIMIT 10;"

# Get statistics
sqlite3 .augment/resource_watchdog.db "SELECT 
    COUNT(*) as total_checks,
    SUM(threshold_exceeded) as threshold_violations,
    AVG(vscode_memory_mb) as avg_memory_mb,
    MAX(vscode_memory_mb) as max_memory_mb
FROM resource_checks;"
```

## Integration with Existing Watchdog

Add to `package.json`:

```json
{
  "scripts": {
    "watch:resources": "bash src/resource-watchdog.sh",
    "check:resources": "bash src/resource-watchdog.sh --once"
  }
}
```

## Uninstall

```bash
systemctl --user stop resource-watchdog
systemctl --user disable resource-watchdog
rm ~/.config/systemd/user/resource-watchdog.service
systemctl --user daemon-reload
```
EOF
echo "✅ Created INSTALL_RESOURCE_WATCHDOG.md"
echo ""

# Update package.json
if [ -f "$WATCHDOG_REPO/package.json" ]; then
    echo "📋 Updating package.json..."
    
    # Add scripts using jq if available, otherwise manual
    if command -v jq &>/dev/null; then
        jq '.scripts["watch:resources"] = "bash src/resource-watchdog.sh" | .scripts["check:resources"] = "bash src/resource-watchdog.sh --once"' \
            "$WATCHDOG_REPO/package.json" > "$WATCHDOG_REPO/package.json.tmp"
        mv "$WATCHDOG_REPO/package.json.tmp" "$WATCHDOG_REPO/package.json"
        echo "✅ Updated package.json with npm scripts"
    else
        echo "⚠️  jq not found, skipping package.json update"
        echo "   Add manually:"
        echo '   "watch:resources": "bash src/resource-watchdog.sh"'
        echo '   "check:resources": "bash src/resource-watchdog.sh --once"'
    fi
    echo ""
fi

# Test run
echo "🧪 Testing resource watchdog..."
bash "$INSTALL_TARGET" --once
echo ""

echo "═══════════════════════════════════════════════════════════════════"
echo "✅ INSTALLATION COMPLETE"
echo "═══════════════════════════════════════════════════════════════════"
echo ""
echo "Next steps:"
echo "  1. cd $WATCHDOG_REPO"
echo "  2. cat INSTALL_RESOURCE_WATCHDOG.md"
echo "  3. bash src/resource-watchdog.sh --once  # Test"
echo "  4. bash src/resource-watchdog.sh         # Run continuously"
echo ""
echo "Or install as systemd service:"
echo "  mkdir -p ~/.config/systemd/user"
echo "  cp resource-watchdog.service ~/.config/systemd/user/"
echo "  systemctl --user enable --now resource-watchdog"
echo ""

