#!/usr/bin/env bash
#
# VS Code Resource Guardian - Installation and Immediate Activation
#
# PURPOSE:
# - Install dependencies
# - Compile TypeScript
# - Package extension
# - Install to VS Code
# - Kill current runaway processes
# - Reload VS Code to activate extension
#
# USAGE:
#   chmod +x INSTALL_AND_ACTIVATE.sh
#   ./INSTALL_AND_ACTIVATE.sh
#
# CRITICAL: This script addresses IMMEDIATE resource contention
# - Load average: 5.83 (nearly 3x CPU capacity)
# - PID 815364: 27% CPU, 1GB RAM (zygote runaway)
# - PID 813994: 13% CPU, 640MB RAM (zygote runaway)
# - PID 814088: 11% CPU, 551MB RAM (utility runaway)
# - Swap: 1.4GB used (18%)

set -euo pipefail

echo "================================================================================"
echo "VS CODE RESOURCE GUARDIAN - INSTALLATION AND ACTIVATION"
echo "================================================================================"
echo ""

# Step 1: Check prerequisites
echo "🔍 Step 1: Checking prerequisites..."
if ! command -v npm &> /dev/null; then
    echo "❌ ERROR: npm not found. Install Node.js first."
    exit 1
fi

if ! command -v code &> /dev/null; then
    echo "❌ ERROR: VS Code CLI not found. Install VS Code first."
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
EXTENSION_NAME="resource-guardian.vscode-resource-guardian-1.0.0"
EXTENSION_PATH="$VSCODE_EXTENSIONS_DIR/$EXTENSION_NAME"

# Remove old version if exists
if [ -d "$EXTENSION_PATH" ]; then
    echo "  Removing old version..."
    rm -rf "$EXTENSION_PATH"
fi

# Create symlink to current directory
echo "  Creating symlink: $EXTENSION_PATH -> $(pwd)"
ln -s "$(pwd)" "$EXTENSION_PATH"

echo "✅ Extension installed (development mode)"
echo ""

# Step 5: IMMEDIATE ACTION - Kill runaway processes
echo "🚨 Step 5: EMERGENCY - Killing runaway processes NOW..."
echo ""

# Get current runaway processes (CPU > 10% OR memory > 400MB)
echo "Current runaway processes:"
ps aux | grep -E "(code|/proc/self/exe)" | grep -v grep | awk '$3 > 10.0 || $6 > 400000 {print "  PID", $2, "CPU:", $3 "%", "MEM:", int($6/1024) "MB", $11}'

echo ""
echo "Killing processes with CPU > 10% OR memory > 400MB..."

# Kill zygote processes with high CPU
for pid in $(ps aux | grep "code.*zygote" | grep -v grep | awk '$3 > 10.0 {print $2}'); do
    echo "  Killing zygote PID $pid (high CPU)..."
    kill -15 "$pid" 2>/dev/null || true
done

# Kill utility processes with high CPU
for pid in $(ps aux | grep "/proc/self/exe.*utility" | grep -v grep | awk '$3 > 10.0 {print $2}'); do
    echo "  Killing utility PID $pid (high CPU)..."
    kill -15 "$pid" 2>/dev/null || true
done

# Kill processes with high memory
for pid in $(ps aux | grep -E "(code|/proc/self/exe)" | grep -v grep | awk '$6 > 400000 {print $2}'); do
    echo "  Killing PID $pid (high memory)..."
    kill -15 "$pid" 2>/dev/null || true
done

echo ""
echo "⏳ Waiting 3 seconds for graceful shutdown..."
sleep 3

# Force kill if still alive
for pid in $(ps aux | grep -E "(code.*zygote|/proc/self/exe.*utility)" | grep -v grep | awk '$3 > 10.0 || $6 > 400000 {print $2}'); do
    echo "  Force killing PID $pid (still alive)..."
    kill -9 "$pid" 2>/dev/null || true
done

echo "✅ Runaway processes killed"
echo ""

# Step 6: Show current resource usage
echo "📊 Step 6: Current resource usage after cleanup..."
echo ""
free -h
echo ""
echo "Load average:"
uptime | awk -F'load average:' '{print $2}'
echo ""

# Step 7: Reload VS Code
echo "🔄 Step 7: Reloading VS Code to activate extension..."
echo ""
echo "⚠️  IMPORTANT: You must manually reload VS Code now:"
echo "   1. Press Ctrl+Shift+P"
echo "   2. Type 'Reload Window'"
echo "   3. Press Enter"
echo ""
echo "After reload, Resource Guardian will:"
echo "  - Monitor every 5 seconds (configurable)"
echo "  - Alert when CPU > 10% or memory > 400MB"
echo "  - Auto-trigger GC when extension host > 400MB"
echo "  - Detect memory leaks using linear regression"
echo "  - Emergency cleanup if load > 5.0"
echo ""
echo "Commands available:"
echo "  - Resource Guardian: Show Resource Status"
echo "  - Resource Guardian: Kill Runaway Processes"
echo "  - Resource Guardian: Force Garbage Collection"
echo "  - Resource Guardian: EMERGENCY Cleanup"
echo ""
echo "================================================================================"
echo "✅ INSTALLATION COMPLETE"
echo "================================================================================"

