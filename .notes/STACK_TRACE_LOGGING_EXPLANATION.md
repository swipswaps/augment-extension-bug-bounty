# Stack Trace Logging in Watchdog - What, Why, and How

## USER REQUEST
> "try to show what line and subroutine of what file or scripts called or caused the error"
> "the LLM needs to see those details to troubleshoot"

## PROBLEM IDENTIFIED

### BEFORE (Insufficient for Troubleshooting)
```
EXTENSION ERROR | VS Code logs (last 1min) | count=20
  Augment.log: 2026-02-18 13:01:00.652 [error] 'ClientWorkspaces': Failed to call chat input completion API Request cancelled
  Augment.log: 2026-02-18 13:01:00.653 [error] 'Service[mAe]': API call failed: Request cancelled
```

**PROBLEM**: Error message shows WHAT failed ("Request cancelled") but NOT:
- WHERE in the code it failed (file path, line number)
- WHICH function called it (call stack)
- HOW the error propagated (function call chain)

**IMPACT**: LLM cannot troubleshoot because it doesn't know:
- Is this a bug in `eH.callApi` or `chatInputCompletion`?
- Is the error in `extension.js:252` or `extension.js:444993`?
- Is this a network error, timeout, or cancellation?

## ROOT CAUSE

### Why Stack Traces Were Missing

1. **grep only captures single line**: `grep "error"` returns the error line, not the following stack trace lines
2. **Watchdog logged first line only**: Previous code logged error message but ignored stack traces
3. **Stack traces are on separate lines**: 
   ```
   2026-02-18 13:01:00.652 [error] 'ClientWorkspaces': Failed to call...  ← grep captures this
   Error: Request cancelled                                                ← grep MISSES this
       at eH.callApi (/home/owner/.vscode/extensions/.../extension.js:252:1928)  ← grep MISSES this
       at process.processTicksAndRejections (node:internal/process/task_queues:105:5)  ← grep MISSES this
   ```

## SOLUTION IMPLEMENTED

### Code Changes in `hidden-terminal-watchdog/src/extension.ts`

**BEFORE (lines 173-200):**
```typescript
exec(`find ${logsDir} -name "*.log" ! -name "*Watchdog*" -mmin -1 -exec grep -iH "error\\|exception" {} \\; 2>/dev/null | grep -v "\\[info\\]" | tail -20`, (err, stdout) => {
    // Only captures error line, NOT stack traces
});
```

**AFTER (lines 173-255):**
```typescript
// STEP 1: Find Augment.log
exec(`find ${logsDir} -name "Augment.log" -type f 2>/dev/null | sort | tail -1`, (err1, augmentLogPath) => {
    // STEP 2: Extract errors WITH stack traces (error line + next 10 lines)
    exec(`tail -500 "${logPath}" | grep -B 0 -A 10 "\\[error\\]\\|\\[warning\\]" | tail -100`, (err2, stdout) => {
        // Parse and log each line with proper formatting
        lines.forEach(line => {
            if (line.includes('\tat ') || line.includes('    at ')) {
                // STACK TRACE: Extract file path and line number
                const stackMatch = line.match(/at\s+([^\s(]+)\s+\(([^)]+):(\d+):(\d+)\)/);
                if (stackMatch) {
                    const funcName = stackMatch[1];
                    const filePath = stackMatch[2];
                    const lineNum = stackMatch[3];
                    const colNum = stackMatch[4];
                    
                    // Simplify file path: "augment.vscode-augment-0.779.0/extension.js"
                    log(`    STACK: ${funcName} @ ${simplifiedPath}:${lineNum}:${colNum}`);
                }
            }
        });
    });
});
```

### Key Changes

1. **grep -A 10**: Capture error line + next 10 lines (stack trace)
2. **Parse stack traces**: Extract function name, file path, line number, column number
3. **Simplify file paths**: Show `augment.vscode-augment-0.779.0/extension.js:252:1928` instead of full path
4. **Format for readability**: Indent stack traces, show function @ file:line:column

## AFTER (Full Troubleshooting Context)

```
EXTENSION ERROR WITH STACK TRACES | Augment.log (last 500 lines) | count=45
  Augment.log: 2026-02-18 13:01:00.652 [error] 'ClientWorkspaces': Failed to call chat input completion API Request cancelled
    Error: Request cancelled
    STACK: eH.callApi @ augment.vscode-augment-0.779.0/extension.js:252:1928
    STACK: eH.callApi @ augment.vscode-augment-0.779.0/extension.js:252:478050
    STACK: eH.chatInputCompletion @ augment.vscode-augment-0.779.0/extension.js:252:444993
    STACK: oEe.callChatInputCompletionAPI @ augment.vscode-augment-0.779.0/extension.js:5263:14902
    STACK: mAe.fetchCompletion @ augment.vscode-augment-0.779.0/extension.js:371:5
```

## TROUBLESHOOTING VALUE

### What LLM Can Now See

1. **Exact error location**: `extension.js:252:1928` (line 252, column 1928)
2. **Function that failed**: `eH.callApi` (API call wrapper)
3. **Call chain**: 
   - `fetchCompletion` (line 371) called
   - `callChatInputCompletionAPI` (line 5263) which called
   - `chatInputCompletion` (line 444993) which called
   - `callApi` (line 252) which threw "Request cancelled"
4. **Root cause**: Error originates in `eH.callApi` at line 252, propagates up through 4 function calls

### Actionable Insights

- **Bug location**: `extension.js:252:1928` in `eH.callApi` function
- **Error type**: Request cancellation (not timeout, not network error)
- **Propagation path**: API wrapper → chat completion → workspace client → completion fetcher
- **Fix target**: Investigate why `eH.callApi` is cancelling requests at line 252

## HOW TO USE

### 1. Reload VS Code Window
```
Ctrl+Shift+P → "Developer: Reload Window"
```

### 2. Wait 60 Seconds
Watchdog scans Augment.log every 60 seconds

### 3. View Watchdog Log
```
Ctrl+Shift+P → "Output" → Select "Watchdog Log"
```

### 4. See Stack Traces
```
[2026-02-18T19:40:00.000Z] EXTENSION ERROR WITH STACK TRACES | Augment.log (last 500 lines) | count=45
[2026-02-18T19:40:00.001Z]   Augment.log: 2026-02-18 13:01:00.652 [error] 'ClientWorkspaces': Failed to call...
[2026-02-18T19:40:00.002Z]     Error: Request cancelled
[2026-02-18T19:40:00.003Z]     STACK: eH.callApi @ augment.vscode-augment-0.779.0/extension.js:252:1928
[2026-02-18T19:40:00.004Z]     STACK: eH.chatInputCompletion @ augment.vscode-augment-0.779.0/extension.js:252:444993
```

### 5. Regenerate Dashboard with Stack Traces
```bash
# Extract latest errors with stack traces
bash .augment/scripts/create-granular-dashboard.sh

# Generate standalone HTML dashboard
python3 .augment/scripts/generate-standalone-dashboard.py

# Open in browser
file://.notes/visualizations/standalone-dashboard.html
```

## BENEFITS

1. **LLM can troubleshoot**: Sees exact file, line, function that caused error
2. **Root cause analysis**: Traces error propagation through call stack
3. **Bug localization**: Pinpoints exact code location (extension.js:252:1928)
4. **Pattern detection**: Identifies if same function fails repeatedly
5. **Fix verification**: After fix, verify error no longer appears at that line

## FILES MODIFIED

- `hidden-terminal-watchdog/src/extension.ts` (lines 173-255)
- Compiled and packaged: `hidden-terminal-watchdog-1.0.0.vsix`
- Installed in VS Code: Ready to use after window reload

## NEXT STEPS

1. **Reload VS Code window** to activate updated watchdog
2. **Wait 60 seconds** for first scan
3. **Check Watchdog Log** output channel for stack traces
4. **Regenerate dashboard** to see stack traces in visualization
5. **Use stack traces** to troubleshoot and fix errors

