# Stack Trace Dashboard Implementation - Complete

## Summary
Implemented click-to-expand stack trace visualization in granular dashboard.

## Files Modified

### 1. `.augment/scripts/create-granular-dashboard.sh`
**Problem**: STACK: entries in watchdog log have timestamps, parser expected raw text
**Fix**: Extract content after timestamp before checking `startswith('STACK:')`
**Result**: 60 events with stack traces extracted

### 2. `.augment/scripts/generate-standalone-dashboard.py`
**Added**:
- CSS for expandable stack traces (`.stack-trace`, `.stack-trace-line`)
- JavaScript click handlers to toggle visibility
- Stack trace parsing: `STACK: funcName @ file.js:line:col`
- Async function indicators
- Orange badge showing stack line count

## Evidence

```bash
# Events with stack traces
$ jq '[.[] | select(.stack_trace | length > 0)] | length' .notes/visualizations/application-logs.json
60

# Sample entry
$ jq '.[] | select(.stack_trace | length > 0) | {msg: .message[0:60], stacks: (.stack_trace | length), files: (.files | length)}' .notes/visualizations/application-logs.json | head -5
{
  "msg": "Error: Request cancelled",
  "stacks": 9,
  "files": 7
}

# Dashboard generated
$ ls -lh .notes/visualizations/standalone-dashboard.html
-rw-r--r--. 1 owner owner 950K Feb 18 21:06 standalone-dashboard.html
```

## Usage

1. Open: `file://.notes/visualizations/standalone-dashboard.html`
2. Filter: Severity = ERROR
3. Look for: Orange badge "9 STACK LINES"
4. Click: Row to expand
5. See: Full stack trace with file:line:col

## Example Output

```
Error: Request cancelled
📍 STACK TRACE (Click to toggle)
  ▶ eH.callApi @ extension.js:252:1928
  ▶ eH.callApi @ extension.js:252:478050 (async)
  ▶ eH.chatInputCompletion @ extension.js:252:444993 (async)
  ▶ oEe.callChatInputCompletionAPI @ extension.js:5263:14902 (async)
  ▶ mAe.fetchCompletion @ extension.js:371:5 (async)
  ▶ SBe @ extension.js:64:4481 (async)
```

## LLM Troubleshooting Value

✅ Exact file: `extension.js`
✅ Exact line: `252`, `444993`, `5263`, `371`, `64`
✅ Exact function: `eH.callApi`, `eH.chatInputCompletion`, `oEe.callChatInputCompletionAPI`
✅ Complete call chain showing error propagation
✅ Async function indicators

## Status: COMPLETE ✅
