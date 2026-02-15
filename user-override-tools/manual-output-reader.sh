#!/usr/bin/env bash
# Manual output reader - Read terminal output when AI claims "no output"
# Use this when the AI says "no output was captured" but you can see output in the terminal

set -euo pipefail

echo "╔════════════════════════════════════════════════════════════════════════════════╗"
echo "║                        MANUAL OUTPUT READER                                    ║"
echo "║                                                                                ║"
echo "║  Use this when AI claims 'no output' but you can see output in terminal       ║"
echo "╚════════════════════════════════════════════════════════════════════════════════╝"
echo ""

# Check if terminal ID provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <terminal_id>"
    echo ""
    echo "Example: $0 123456"
    echo ""
    echo "To find terminal ID:"
    echo "  1. Look at the terminal tab in VS Code"
    echo "  2. The ID is shown in the terminal title or prompt"
    echo "  3. Or check the AI's last tool call output for 'Terminal ID'"
    exit 1
fi

TERMINAL_ID="$1"

echo "🔍 Searching for terminal output..."
echo "   Terminal ID: $TERMINAL_ID"
echo ""

# Try to find terminal output in various locations
FOUND=0

# Location 1: VS Code terminal buffer files
VSCODE_TERMINALS="$HOME/.config/Code/User/workspaceStorage/*/state.vscdb"
if ls $VSCODE_TERMINALS 2>/dev/null >/dev/null; then
    echo "📂 Checking VS Code terminal buffers..."
    for db in $VSCODE_TERMINALS; do
        if strings "$db" 2>/dev/null | grep -q "$TERMINAL_ID"; then
            echo "   ✅ Found terminal $TERMINAL_ID in $(dirname "$db")"
            FOUND=1
        fi
    done
fi

# Location 2: Augment extension logs
AUGMENT_LOGS="$HOME/.config/Code/logs/*/exthost*/output_logging_*/*/Augment*"
if ls $AUGMENT_LOGS 2>/dev/null >/dev/null; then
    echo "📂 Checking Augment extension logs..."
    for log in $AUGMENT_LOGS; do
        if grep -q "$TERMINAL_ID" "$log" 2>/dev/null; then
            echo "   ✅ Found terminal $TERMINAL_ID in $log"
            echo ""
            echo "════════════════════════════════════════════════════════════════════════════════"
            echo "OUTPUT FROM LOG:"
            echo "════════════════════════════════════════════════════════════════════════════════"
            grep -A 50 "$TERMINAL_ID" "$log" | head -100
            FOUND=1
        fi
    done
fi

# Location 3: Script output files (if using our test scripts)
SCRIPT_OUTPUTS="/tmp/test-*.log"
if ls $SCRIPT_OUTPUTS 2>/dev/null >/dev/null; then
    echo "📂 Checking script output files..."
    for output in $SCRIPT_OUTPUTS; do
        echo "   📄 $output"
        cat "$output"
        FOUND=1
    done
fi

if [ $FOUND -eq 0 ]; then
    echo "❌ Could not find output for terminal $TERMINAL_ID"
    echo ""
    echo "MANUAL STEPS:"
    echo "  1. Look at the VS Code terminal window"
    echo "  2. Scroll up to see the command output"
    echo "  3. Copy the output manually"
    echo "  4. Paste it into the chat to show the AI"
    echo ""
    echo "ALTERNATIVE:"
    echo "  Re-run the command in a regular terminal (not VS Code integrated terminal)"
    echo "  and capture the output to a file:"
    echo ""
    echo "  your-command 2>&1 | tee /tmp/output.log"
    echo ""
else
    echo ""
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo "✅ OUTPUT FOUND ABOVE"
    echo "════════════════════════════════════════════════════════════════════════════════"
fi

