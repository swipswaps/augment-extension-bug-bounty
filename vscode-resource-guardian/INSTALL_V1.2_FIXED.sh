#!/usr/bin/env bash
#
# Install Resource Guardian v1.2 - FIXED VERSION
#
# WHAT WAS FIXED:
# - Monitor interval: 5s → 30s (less aggressive)
# - CPU threshold: 10% → 25% (only kill truly runaway processes)
# - Memory threshold: 400MB → 800MB (allow normal memory usage)
# - Extension host threshold: 400MB → 600MB (allow normal memory usage)
# - Startup grace period: 2 minutes (don't kill during VS Code startup)
# - Process min age: 30 seconds (don't kill young processes)
# - Violation counting: Must violate 3 times in a row before flagging
# - Ignore list: User can ignore specific PIDs for 5 minutes
# - NEVER auto-kill: Always ask user confirmation (even if autoKillRunaway=true)
#
# WHY v1.0 FAILED:
# - TOO AGGRESSIVE: Killed processes during normal VS Code startup
# - Caused VS Code to crash repeatedly
# - User cannot work (VS Code keeps closing)
# - Popups every 5 seconds
#
# WHY v1.2 SHOULD WORK:
# - Less frequent monitoring (30s not 5s)
# - Higher thresholds (only kill truly runaway processes)
# - Startup grace period (don't kill during first 2 minutes)
# - Violation counting (must violate 3 times before flagging)
# - Always ask user (never auto-kill)

set -euo pipefail

echo "================================================================================"
echo "RESOURCE GUARDIAN v1.2 - FIXED VERSION INSTALLATION"
echo "================================================================================"
echo ""

# Step 1: Check prerequisites
echo "🔍 Step 1: Checking prerequisites..."
if ! command -v npm &> /dev/null; then
    echo "❌ npm not found. Please install Node.js and npm first."
    exit 1
fi

if ! command -v code &> /dev/null; then
    echo "❌ VS Code not found. Please install VS Code first."
    exit 1
fi

echo "✅ Prerequisites OK"
echo ""

# Step 2: Install dependencies
echo "📦 Step 2: Installing dependencies..."
npm install
echo "✅ Dependencies installed"
echo ""

# Step 3: Compile TypeScript
echo "🔨 Step 3: Compiling TypeScript..."
npm run compile
echo "✅ Compilation complete"
echo ""

# Step 4: Create symlink for VS Code extensions directory
echo "📦 Step 4: Installing extension (development mode)..."

# Get VS Code extensions directory
VSCODE_EXTENSIONS_DIR="$HOME/.vscode/extensions"
EXTENSION_NAME="resource-guardian.vscode-resource-guardian-1.2.0"
EXTENSION_PATH="$VSCODE_EXTENSIONS_DIR/$EXTENSION_NAME"

# Remove old version if exists
if [ -d "$EXTENSION_PATH" ] || [ -L "$EXTENSION_PATH" ]; then
    echo "  Removing old version..."
    rm -rf "$EXTENSION_PATH"
fi

# Create symlink to current directory
echo "  Creating symlink: $EXTENSION_PATH -> $(pwd)"
ln -s "$(pwd)" "$EXTENSION_PATH"

echo "✅ Extension installed (development mode)"
echo ""

# Step 5: Show current runaway processes
echo "📊 Step 5: Current system state..."
free -h | head -2
echo ""
uptime
echo ""

echo "🔍 Runaway processes (CPU > 20% OR memory > 600MB):"
ps aux | grep -E "(code|/proc/self/exe)" | grep -v grep | \
    awk '$3 > 20.0 || $6 > 600000 {print "PID", $2, "CPU:", $3 "%", "MEM:", int($6/1024) "MB", $11}' || echo "  None found"
echo ""

echo "================================================================================"
echo "✅ INSTALLATION COMPLETE"
echo "================================================================================"
echo ""
echo "NEXT STEPS:"
echo "  1. Reload VS Code: Ctrl+Shift+P → 'Reload Window'"
echo "  2. Extension will activate after reload"
echo "  3. Monitor for 2 minutes (startup grace period)"
echo "  4. Extension will start monitoring after grace period"
echo ""
echo "WHAT'S DIFFERENT IN v1.2:"
echo "  ✅ Monitor interval: 30 seconds (was 5s)"
echo "  ✅ CPU threshold: 25% (was 10%)"
echo "  ✅ Memory threshold: 800MB (was 400MB)"
echo "  ✅ Startup grace period: 2 minutes (NEW)"
echo "  ✅ Violation counting: 3 strikes before flagging (NEW)"
echo "  ✅ Ignore list: User can ignore PIDs for 5 min (NEW)"
echo "  ✅ NEVER auto-kill: Always ask user (FIXED)"
echo ""
echo "EXPECTED BEHAVIOR:"
echo "  - No popups during first 2 minutes (startup grace period)"
echo "  - Fewer popups (30s interval, not 5s)"
echo "  - Only alerts for truly runaway processes (25% CPU, 800MB RAM)"
echo "  - Always asks before killing (never auto-kill)"
echo "  - VS Code should NOT crash"
echo ""
echo "IF PROBLEMS PERSIST:"
echo "  - Disable extension: ./.augment/scripts/disable-resource-guardian.sh"
echo "  - Use manual cleanup: ./.augment/scripts/emergency-vscode-cleanup.sh"
echo ""

