# EXACT CODE FLOW - What Triggers Timeout and ^C

**Date**: 2026-02-11 12:50  
**Evidence**: Terminal output from actual test run

---

## The Complete Flow

### 1. User Runs Command (t=0s)
```
AI calls: launch-process with max_wait_seconds=10
Command: /tmp/test-timeout-behavior.sh
```

### 2. Webview Starts Race (t=0s)

**File**: `extension-client-context-CN64fWtK.js`  
**Line**: 44324-44328

```javascript
const {
    wait: h,
    max_wait_seconds: p
} = s || {}, {
    cancel: g
} = yield* FE({
    callTool: w(Hz, e, n, o, s, d, c),  // ← Execute command
    cancel: w(_z, n, o, h, p)            // ← Wait for timeout
});
```

**What happens**: Two generator functions race:
- `callTool` - Executes the command
- `cancel` - Waits `max_wait_seconds` then returns `true`

### 3. Timeout Function Waits (t=0s to t=10s)

**File**: `extension-client-context-CN64fWtK.js`  
**Line**: 44257-44259

```javascript
function* _z(t, e, n, o) {
    return (yield* m2.effect(t, e)) !== K.running ? !1 : 
        (yield* je(1e3 * (n && o || Lz)),  // ← WAIT 10,000 milliseconds
         (yield* m2.effect(t, e)) === K.running && 
         (yield* E(zA(t, e)), !0))  // ← Return TRUE if still running
}
```

**What happens**:
- `je(1e3 * 10)` = `je(10000)` = Wait 10 seconds
- If process still running after 10s, return `true`
- This sets `cancel: g` to `true` in the race result

### 4. Command Produces Output (t=0s to t=8s)

**Terminal output**:
```
START: timeout-test
Line 1 - immediate output        ← t=0s
Line 2 - after 2 seconds         ← t=2s
Line 3 - after 4 seconds         ← t=4s
Line 4 - after 6 seconds         ← t=6s
Line 5 - after 8 seconds         ← t=8s
```

**What happens**: Command is running normally, producing output

### 5. Timeout Wins Race (t=10s)

**File**: `extension-client-context-CN64fWtK.js`  
**Line**: 44333

```javascript
if (g) {  // ← g = true (timeout occurred)
    const m = yield* O();
    throw yield* w([m, m.cancelToolRun], n, o),  // ← Call cancelToolRun
    new Error("Tool call was cancelled due to timeout")  // ← Throw error
}
```

**What happens**:
- `cancel: g` is `true` (timeout won the race)
- Webview calls `cancelToolRun` message to extension host
- Webview throws error IMMEDIATELY (doesn't wait for output)

### 6. Extension Host Sends Ctrl+C (t=10.001s)

**File**: `extension.js`  
**Line**: 259682

```javascript
this._logger.verbose(`Killing process ${r}`);
let i = this._processPollers.get(r);
i && (clearInterval(i), this._processPollers.delete(r)), 
this._isLongRunningTerminal(n.terminal) ? 
    (this._logger.debug("Sending Ctrl+C to interrupt current command in long-running terminal"), 
     n.terminal.sendText("\u0003", !1))  // ← LINE 259682: Send Ctrl+C (\u0003)
    : n.terminal.dispose(), 
n.state = "killed", 
n.exitCode = -1;
let o = await this.hybridReadOutput(r);  // ← Read output AFTER killing
return n.output = o?.output ?? "", {
    output: n.output,
    killed: !0,
    returnCode: n.exitCode
}
```

**What happens**:
- Extension receives `cancelToolRun` message
- Sends `\u0003` (Ctrl+C) to terminal
- Sets state to "killed"
- THEN reads output (too late - process is dead)

### 7. Terminal Shows ^C (t=10.001s)

**Terminal output**:
```
Line 5 - after 8 seconds
^C                               ← Ctrl+C sent by extension
```

**What happens**: User sees `^C` in terminal (not typed by user)

### 8. Webview Catch Block Intercepts Error (t=10.002s)

**File**: `extension-client-context-CN64fWtK.js`  
**Line**: 44340-44348

```javascript
} catch (h) {
    const p = yield* Ln.effect(n, o);
    if (p.phase === K.new || p.phase === K.cancelled) return;
    const g = h instanceof Error ? h.message : String(h);
    // RULE 9 BLOCKING FIX: Detect and override timeout errors
    if (g.includes("cancelled due to timeout") || g.includes("canceled due to timeout") || g.includes("timed out")) {
        console.log(`[RULE 9 BLOCKING - WEBVIEW] Detected timeout error: "${g}" - overriding to return success`);
        yield* E(Qs(n, o, {
            isError: !1,  // ← Override to false
            text: `RULE 9 BLOCKING FIX (WEBVIEW): Tool call timed out. Output may exist in terminal but was not captured before timeout. Check user's visible terminal for actual command output. Original error: ${g}`
        }));
        return;
    }
    // ... rest of error handling
}
```

**What happens**:
- Catch block detects "cancelled due to timeout" error
- Overrides `isError: true` to `isError: false`
- Returns diagnostic message instead of error
- AI receives this message (not an error)

### 9. AI Receives Result (t=10.003s)

**Tool result**:
```
RULE 9 BLOCKING FIX (WEBVIEW): Tool call timed out. Output may exist in terminal but was not captured before timeout. Check user's visible terminal for actual command output. Original error: Tool call was cancelled due to timeout
```

**What happens**:
- AI receives diagnostic message
- NO `<output>` section with actual output
- AI does NOT ask user to manually run command (RULE 9 fix working)
- But AI has NO visibility into Lines 1-5 that were produced

---

## Summary

**What triggers the ^C**: Line 259682 in extension.js sends `\u0003` (Ctrl+C)

**What triggers the timeout**: Line 44257 in webview waits `1e3 * max_wait_seconds` milliseconds

**What causes "no output"**: 
1. Webview throws error immediately (line 44333)
2. Extension kills process first (line 259682)
3. Extension reads output after killing (too late)
4. Output exists in terminal but not captured

**What the RULE 9 fix does**:
- Prevents AI from asking for manual work
- Doesn't capture the output
- This is a WORKAROUND, not a complete fix

---

## Evidence

**Terminal output** (what user saw):
```
START: timeout-test
Line 1 - immediate output
Line 2 - after 2 seconds
Line 3 - after 4 seconds
Line 4 - after 6 seconds
Line 5 - after 8 seconds
^C
```

**Tool result** (what AI received):
```
RULE 9 BLOCKING FIX (WEBVIEW): Tool call timed out...
```

**Conclusion**: Output exists but is not captured.

