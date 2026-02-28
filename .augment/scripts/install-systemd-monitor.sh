#!/usr/bin/env bash
set -euo pipefail

LOGFILE=".notes/install-systemd-$(date +%Y%m%d-%H%M%S).log"
mkdir -p .notes
exec > >(tee -a "$LOGFILE") 2>&1

echo "START: install-systemd-monitor"

# Create systemd user service
mkdir -p ~/.config/systemd/user

cat > ~/.config/systemd/user/vscode-resource-monitor.service <<'EOF'
[Unit]
Description=VS Code Resource Monitor
After=default.target

[Service]
Type=simple
WorkingDirectory=%h/Documents/6984bd27-4494-8330-9803-7b6895a48aa5
ExecStart=/bin/bash %h/Documents/6984bd27-4494-8330-9803-7b6895a48aa5/.augment/scripts/resolve-contention-with-events.sh
Restart=always
RestartSec=10

[Install]
WantedBy=default.target
EOF

echo "Created: ~/.config/systemd/user/vscode-resource-monitor.service"

# Reload systemd
systemctl --user daemon-reload
echo "Reloaded systemd user daemon"

# Enable and start service
systemctl --user enable vscode-resource-monitor.service
systemctl --user start vscode-resource-monitor.service
echo "Enabled and started vscode-resource-monitor.service"

# Show status
systemctl --user status vscode-resource-monitor.service --no-pager

echo ""
echo "✅ Systemd monitor installed"
echo ""
echo "Commands:"
echo "  Status:  systemctl --user status vscode-resource-monitor.service"
echo "  Logs:    journalctl --user -u vscode-resource-monitor.service -f"
echo "  Stop:    systemctl --user stop vscode-resource-monitor.service"
echo "  Disable: systemctl --user disable vscode-resource-monitor.service"
echo ""
echo "END: install-systemd-monitor"

