#!/bin/bash
# Test dashboard stack trace functionality

echo "=== STACK TRACE DASHBOARD VERIFICATION ==="
echo ""

echo "1. JSON Data Verification"
echo "   Events with stack traces:"
jq '[.[] | select(.stack_trace | length > 0)] | length' .notes/visualizations/application-logs.json

echo ""
echo "2. Sample Stack Trace Entry"
jq '.[] | select(.stack_trace | length > 0) | {
  message: (.message[0:60]),
  stack_lines: (.stack_trace | length),
  first_3_stacks: .stack_trace[0:3],
  first_3_files: .files[0:3]
}' .notes/visualizations/application-logs.json | head -40

echo ""
echo "3. Dashboard File"
ls -lh .notes/visualizations/standalone-dashboard.html

echo ""
echo "4. Stack Trace Badge Count"
grep -c 'badge-has-stack' .notes/visualizations/standalone-dashboard.html || echo "0"

echo ""
echo "5. Click Handler Verification"
grep -c "addEventListener('click'" .notes/visualizations/standalone-dashboard.html || echo "0"

echo ""
echo "6. Async Pattern Detection"
grep -c 'isAsync' .notes/visualizations/standalone-dashboard.html || echo "0"

echo ""
echo "=== MANUAL TEST INSTRUCTIONS ==="
echo "1. Open: file://$PWD/.notes/visualizations/standalone-dashboard.html"
echo "2. Filter: Severity = ERROR"
echo "3. Look for: Orange badge '9 STACK LINES'"
echo "4. Click: Any row with stack badge"
echo "5. Verify: Stack trace expands showing:"
echo "   ▶ eH.callApi @ extension.js:252:1928"
echo "   ▶ eH.callApi @ extension.js:252:478050 (async)"
echo "   ▶ eH.chatInputCompletion @ extension.js:252:444993 (async)"
echo ""
