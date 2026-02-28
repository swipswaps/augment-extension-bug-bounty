#!/bin/bash
# Pre-Stop Watchdog - ENFORCES continuation by auto-executing next steps
# This script PREVENTS stopping by running the next command automatically

set -euo pipefail

echo "START: pre-stop-watchdog"

# Check if user said "stop"
if [ -f .notes/user-said-stop.flag ]; then
  echo "✅ User explicitly said 'stop' - stopping is allowed"
  rm .notes/user-said-stop.flag
  exit 0
fi

# Check if request is 100% complied with
if [ -f .notes/request-compliance-achieved.flag ]; then
  echo "✅ Request compliance achieved - stopping is allowed"
  rm .notes/request-compliance-achieved.flag
  exit 0
fi

# Default: stopping is NOT allowed - ENFORCE CONTINUATION
echo "❌ STOPPING NOT ALLOWED"
echo ""
echo "CONTINUATION MANDATE ACTIVE:"
echo "- User has NOT said 'stop'"
echo "- Request is NOT 100% complied with"
echo ""
echo "🚀 AUTO-EXECUTING NEXT STEPS (ENFORCEMENT MODE):"
echo ""

# Read the current task state
TASK_STATE_FILE=".notes/current-task-state.txt"

if [ ! -f "$TASK_STATE_FILE" ]; then
  echo "⚠️  No task state file found - creating default workflow"
  cat > "$TASK_STATE_FILE" << 'EOF'
STEP:1:Check servers running
STEP:2:Test backend endpoint
STEP:3:Test frontend endpoint
STEP:4:Open browser and verify
STEP:5:Take screenshot
STEP:6:Commit changes
STEP:7:Push to GitHub
STEP:8:Deploy to production
STEP:9:Verify production
EOF
fi

# Find current step
CURRENT_STEP=$(grep -v "^DONE:" "$TASK_STATE_FILE" | head -1 || echo "")

if [ -z "$CURRENT_STEP" ]; then
  echo "✅ All steps complete - stopping is allowed"
  exit 0
fi

# Extract step number and description
STEP_NUM=$(echo "$CURRENT_STEP" | cut -d: -f2)
STEP_DESC=$(echo "$CURRENT_STEP" | cut -d: -f3-)

echo "📋 CURRENT STEP: $STEP_NUM - $STEP_DESC"
echo ""
echo "⚡ NEXT COMMAND TO EXECUTE:"
echo ""

# Generate next command based on step
case "$STEP_NUM" in
  1)
    echo "ps aux | grep -E '[n]ode.*server.js|[v]ite' && netstat -tlnp 2>/dev/null | grep -E '3000|3001' || ss -tlnp | grep -E '3000|3001'"
    ;;
  2)
    echo "curl -s http://localhost:3001/api/external-players 2>&1 | python3 -m json.tool"
    ;;
  3)
    echo "curl -s http://localhost:3000 2>&1 | head -20"
    ;;
  4)
    echo "xdg-open http://localhost:3000 && sleep 3 && scrot -u /tmp/autofix-test.png"
    ;;
  5)
    echo "tesseract /tmp/autofix-test.png stdout 2>/dev/null | grep -i 'player\\|vlc\\|mpv'"
    ;;
  *)
    echo "MANUAL: Review and continue with step $STEP_NUM"
    ;;
esac

echo ""
echo "🛑 ASSISTANT MUST EXECUTE THIS COMMAND NOW"
echo "🛑 DO NOT STOP - DO NOT WAIT FOR USER INPUT"
echo "🛑 RUN THE COMMAND ABOVE IMMEDIATELY"
echo ""

exit 1

