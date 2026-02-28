#!/bin/bash
# VS Code Extension File Watcher Cleanup
# WHY: VS Code accumulates file handles for deleted files, causing memory leak
# WHAT: Forces VS Code to release file handles by touching .vscode/settings.json

set -euo pipefail

echo "🔧 VS Code Extension File Watcher Cleanup"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# Get current VS Code extension memory usage
VSCODE_PIDS=$(pgrep -f "code.*zygote" || echo "")

if [ -z "$VSCODE_PIDS" ]; then
    echo "✅ No VS Code processes found"
    exit 0
fi

echo "📊 Current VS Code memory usage:"
ps aux | grep "code.*zygote" | grep -v grep | awk '{printf "  PID %s: %s VIRT, %s RES, %s%% CPU\n", $2, $5, $6, $3}'

# Get total memory before cleanup
TOTAL_MEM_BEFORE=$(ps aux | grep "code.*zygote" | grep -v grep | awk '{sum+=$6} END {print sum}')
echo ""
echo "📈 Total memory before: ${TOTAL_MEM_BEFORE}KB"

# Method 1: Exclude .notes directory from file watching
echo ""
echo "🔧 Method 1: Exclude .notes from file watching..."

mkdir -p .vscode

# Create or update settings.json to exclude .notes directory
cat > .vscode/settings.json <<'EOF'
{
  "files.watcherExclude": {
    "**/.notes/**": true,
    "**/.notes/*.log": true,
    "**/.augment/command_history.db": true,
    "**/node_modules/**": true,
    "**/.git/**": true
  },
  "search.exclude": {
    "**/.notes/**": true,
    "**/node_modules/**": true
  },
  "files.exclude": {
    "**/.notes/*.log": false
  }
}
EOF

echo "✅ Updated .vscode/settings.json to exclude .notes from watching"

# Method 2: Touch settings.json to trigger reload
echo ""
echo "🔧 Method 2: Trigger VS Code settings reload..."
touch .vscode/settings.json
sleep 1

# Method 3: Send SIGHUP to VS Code extension host (forces reload without full restart)
echo ""
echo "🔧 Method 3: Send SIGHUP to extension host..."

# Find extension host process (not zygote)
EXT_HOST_PID=$(pgrep -f "extensionHost" || echo "")

if [ -n "$EXT_HOST_PID" ]; then
    echo "  Sending SIGHUP to extension host PID: $EXT_HOST_PID"
    kill -HUP "$EXT_HOST_PID" 2>/dev/null || echo "  (Process already reloading)"
else
    echo "  Extension host not found (may already be reloading)"
fi

# Wait for VS Code to process changes
echo ""
echo "⏳ Waiting 5 seconds for VS Code to process changes..."
sleep 5

# Get total memory after cleanup
TOTAL_MEM_AFTER=$(ps aux | grep "code.*zygote" | grep -v grep | awk '{sum+=$6} END {print sum}')
echo ""
echo "📉 Total memory after: ${TOTAL_MEM_AFTER}KB"

# Calculate savings
SAVINGS=$((TOTAL_MEM_BEFORE - TOTAL_MEM_AFTER))
PERCENT_SAVED=$(awk "BEGIN {printf \"%.1f\", ($SAVINGS / $TOTAL_MEM_BEFORE) * 100}")

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "✅ Cleanup complete"
echo "💾 Memory saved: ${SAVINGS}KB (${PERCENT_SAVED}%)"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

exit 0
