#!/usr/bin/env bash
# Force Continue - Override AI's "no output" claims and force it to continue
# Use this when AI stops working due to timeout errors

set -euo pipefail

echo "╔════════════════════════════════════════════════════════════════════════════════╗"
echo "║                           FORCE CONTINUE                                       ║"
echo "║                                                                                ║"
echo "║  Override AI's 'no output' claims and force it to continue working            ║"
echo "╚════════════════════════════════════════════════════════════════════════════════╝"
echo ""

echo "This script helps you override the AI when it claims 'no output was captured'"
echo "but you can see the output in your terminal."
echo ""

# Check if command provided
if [ $# -eq 0 ]; then
    echo "Usage: $0 <command_to_run>"
    echo ""
    echo "Example: $0 'npm test'"
    echo ""
    echo "This will:"
    echo "  1. Run the command"
    echo "  2. Capture ALL output to a file"
    echo "  3. Display the output"
    echo "  4. Provide instructions to paste into chat"
    exit 1
fi

COMMAND="$*"
OUTPUT_FILE="/tmp/force-continue-$(date +%Y%m%d-%H%M%S).log"

echo "🚀 Running command: $COMMAND"
echo "📝 Output will be saved to: $OUTPUT_FILE"
echo ""
echo "════════════════════════════════════════════════════════════════════════════════"
echo "COMMAND OUTPUT:"
echo "════════════════════════════════════════════════════════════════════════════════"
echo ""

# Run command and capture output
set +e
eval "$COMMAND" 2>&1 | tee "$OUTPUT_FILE"
EXIT_CODE=${PIPESTATUS[0]}
set -e

echo ""
echo "════════════════════════════════════════════════════════════════════════════════"
echo "✅ COMMAND COMPLETED"
echo "════════════════════════════════════════════════════════════════════════════════"
echo ""
echo "Exit code: $EXIT_CODE"
echo "Output saved to: $OUTPUT_FILE"
echo ""
echo "────────────────────────────────────────────────────────────────────────────────"
echo "COPY THIS MESSAGE TO PASTE INTO CHAT:"
echo "────────────────────────────────────────────────────────────────────────────────"
echo ""
echo "The command completed successfully. Here is the ACTUAL output:"
echo ""
echo "\`\`\`"
cat "$OUTPUT_FILE"
echo "\`\`\`"
echo ""
echo "Exit code: $EXIT_CODE"
echo ""
echo "Please read this output and continue with the task. Do NOT claim 'no output'"
echo "was captured. The output is shown above."
echo ""
echo "────────────────────────────────────────────────────────────────────────────────"
echo ""
echo "💡 TIP: Copy everything between the dashed lines and paste into the chat"
echo "        to force the AI to acknowledge the output and continue working."

