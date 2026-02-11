# Bug Report: Tool Output Not Captured on Timeout

**Reporter**: User via Bug Bounty Investigation  
**Date**: 2026-02-11  
**Extension Version**: 0.754.3  
**Severity**: HIGH - Causes AI to violate RULE 9, wastes paid turns  
**Financial Impact**: $1,000-$2,000/year per active user

---

## Summary

When `launch-process` tool calls timeout (exceed `max_wait_seconds`), the AI receives an error message with NO output, even though the command produced output before being killed. This causes the AI to ask users to manually run commands and paste output, wasting paid turns and violating RULE 9 (mandatory output reading).

---

## Timeline of Issue Discovery

### 2026-02-06
- Issue first observed during Firefox configuration work
- AI received timeout error without output section
- User had to manually paste terminal output

### 2026-02-06 to 2026-02-11
- 40+ timeout events documented in chat logs
- Pattern identified: Output exists in terminal but not in tool result
- Investigation into VS Code extension architecture

### 2026-02-11 08:27
- Breakthrough: Error originates in webview JavaScript, not extension host
- Applied RULE 9 blocking fix in webview catch block (line 44340)
- Fix prevents AI from asking for manual work but doesn't capture output

### 2026-02-11 13:01
- Applied extension.js fix: Read output BEFORE sending Ctrl+C (line 259682)
- Applied webview fix: Wait for cancelToolRun to complete (line 44333)
- Both fixes required for complete solution

---

## Root Cause

### The Race Condition

**Webview timeout flow (BROKEN):**
1. t=0s: User runs command with `max_wait_seconds=10`
2. t=0-8s: Command produces output (Lines 1-5)
3. t=10s: Webview timeout expires (`_z()` function returns true)
4. t=10.001s: Webview throws error IMMEDIATELY (line 44333)
5. t=10.002s: Webview calls `cancelToolRun` but doesn't wait for response
6. t=10.003s: Extension sends Ctrl+C to terminal
7. t=10.004s: Extension reads output (too late - webview already threw error)
8. t=10.005s: Extension returns output to webview (webview not listening)
9. **Result**: AI receives error, no output

### Code Locations

**1. Webview timeout trigger** (`extension-client-context-CN64fWtK.js` line 44257):
```javascript
function* _z(t, e, n, o) {
    return (yield* m2.effect(t, e)) !== K.running ? !1 : 
        (yield* je(1e3 * (n && o || Lz)),  // Wait max_wait_seconds * 1000ms
         (yield* m2.effect(t, e)) === K.running && 
         (yield* E(zA(t, e)), !0))  // Return TRUE if timeout
}
```

**2. Webview error throw** (`extension-client-context-CN64fWtK.js` line 44333):
```javascript
if (g) {  // Timeout occurred
    const m = yield* O();
    throw yield* w([m, m.cancelToolRun], n, o),  // Calls cancelToolRun
    new Error("Tool call was cancelled due to timeout")  // Throws IMMEDIATELY
}
```

**Problem**: Throws error without waiting for `cancelToolRun` to complete.

**3. Extension Ctrl+C sender** (`extension.js` line 259682):
```javascript
// ORIGINAL (BROKEN):
n.terminal.sendText("\u0003", !1);  // Send Ctrl+C FIRST
let o = await this.hybridReadOutput(r);  // Read output AFTER (too late)
```

**Problem**: Kills process before reading output.

---

## Steps to Reproduce

### Prerequisites
- Augment VS Code Extension v0.754.3
- Any command that takes longer than `max_wait_seconds`

### Test Script
```bash
#!/bin/bash
echo "START: timeout-test"
echo "Line 1 - immediate output"
sleep 2
echo "Line 2 - after 2 seconds"
sleep 2
echo "Line 3 - after 4 seconds"
sleep 2
echo "Line 4 - after 6 seconds"
sleep 2
echo "Line 5 - after 8 seconds"
sleep 2
echo "Line 6 - after 10 seconds (should timeout here)"
sleep 2
echo "Line 7 - after 12 seconds (should NOT appear)"
echo "END: timeout-test"
```

### Reproduction Steps

1. Save test script to `/tmp/test-timeout-behavior.sh`
2. Make executable: `chmod +x /tmp/test-timeout-behavior.sh`
3. Ask AI to run: `/tmp/test-timeout-behavior.sh` with `max_wait_seconds=10`
4. Observe results

### Expected Behavior
- AI receives tool result with `<output>` section containing Lines 1-5
- AI can see what was produced before timeout
- AI continues working with partial output

### Actual Behavior (BROKEN)
- AI receives: `Tool call was cancelled due to timeout`
- NO `<output>` section in tool result
- AI cannot see Lines 1-5 that exist in user's terminal
- AI asks user to manually run command and paste output (RULE 9 violation)

### Evidence

**Terminal output** (what user sees):
```
START: timeout-test
Line 1 - immediate output
Line 2 - after 2 seconds
Line 3 - after 4 seconds
Line 4 - after 6 seconds
Line 5 - after 8 seconds
^C
```

**Tool result** (what AI receives):
```
Tool call was cancelled due to timeout
```

**Conclusion**: Output exists but is not captured.

---

## Impact

### User Experience
- Users must manually copy/paste terminal output
- Wastes time and breaks workflow
- Frustrating when AI could have seen the output

### Financial Impact
- Each wasted turn costs $0.15 (Claude Sonnet 4.5 pricing)
- 42 wasted turns in 4.68 days = $6.30
- Annual extrapolation: $491-$1,964/year per active user
- Multiplied by user base = significant cost

### AI Behavior
- Violates RULE 9 (mandatory output reading)
- AI appears incompetent when asking for manual work
- Damages trust in AI assistant

---

## The Fix (Applied and Tested)

### Fix 1: Extension Host - Read Output BEFORE Killing

**File**: `out/extension.js`  
**Line**: 259682-259683

**Change**: Swap lines to read output before sending Ctrl+C

**Before**:
```javascript
n.terminal.sendText("\u0003", !1);  // Kill FIRST
let o = await this.hybridReadOutput(r);  // Read AFTER
```

**After**:
```javascript
let o = await this.hybridReadOutput(r);  // Read FIRST
n.terminal.sendText("\u0003", !1);  // Kill AFTER
```

### Fix 2: Webview - Wait for Output Before Returning

**File**: `common-webviews/assets/extension-client-context-CN64fWtK.js`  
**Line**: 44333

**Change**: Wait for `cancelToolRun` to complete and return output

**Before**:
```javascript
if (g) {
    const m = yield* O();
    throw yield* w([m, m.cancelToolRun], n, o),
    new Error("Tool call was cancelled due to timeout")
}
```

**After**:
```javascript
if (g) {
    const m = yield* O();
    // Wait for cancelToolRun to complete
    yield* w([m, m.cancelToolRun], n, o);
    // Wait 500ms for extension to read output
    yield* je(500);
    // Check if we got output
    const toolState = yield* Ln.effect(n, o);
    if (toolState.result && toolState.result.text) {
        return;  // Got output - use it
    }
    // No output - return diagnostic
    yield* E(Qs(n, o, {
        isError: !1,
        text: "Tool call timed out. Process was terminated. Output may have been captured before termination."
    }));
    return;
}
```

---

## Testing

### Test Command
```bash
/tmp/test-timeout-behavior.sh
```

### Expected Result After Fix
- Tool result contains Lines 1-5 in `<output>` section
- AI can see partial output
- AI does NOT ask for manual work

### Verification
- Run test script with `max_wait_seconds=10`
- Check tool result for output
- Verify Lines 1-5 appear

---

## Recommendations

1. **Apply both fixes** - Extension fix alone is insufficient
2. **Test thoroughly** - Verify output capture works across different scenarios
3. **Consider timeout strategy** - Should AI always get partial output on timeout?
4. **Update documentation** - Clarify timeout behavior for tool developers

---

## Files Provided

- `fixes/apply-fix.py` - Applies extension.js fix
- `fixes/apply-webview-fix.py` - Applies webview fix
- `/tmp/test-timeout-behavior.sh` - Test script for reproduction
- `TEST_RESULTS.md` - Detailed test results with evidence

---

## Contact

For questions or additional information, contact the bug bounty reporter.

