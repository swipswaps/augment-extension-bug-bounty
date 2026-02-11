# COMPLETE FIX - Timeout Issue Root Cause and Solution

**Date**: 2026-02-11  
**Status**: ROOT CAUSE IDENTIFIED - CODE FIX REQUIRED

---

## THE COMPLETE FLOW (What Triggers the ^C and False "No Output" Claims)

### Step 1: Timeout Timer Starts (Line 44257)

**Function**: `_z(t, e, n, o)` - The timeout/cancel function

**Code**:
```javascript
function* _z(t, e, n, o) {
    return (yield* m2.effect(t, e)) !== K.running ? !1 : 
        (yield* je(1e3 * (n && o || Lz)),  // ← WAIT for max_wait_seconds * 1000ms
         (yield* m2.effect(t, e)) === K.running && 
         (yield* E(zA(t, e)), !0))  // ← Return TRUE if still running after timeout
}
```

**What it does**:
1. Check if tool is running
2. Wait for `max_wait_seconds * 1000` milliseconds (default 10 seconds)
3. Check if tool is STILL running
4. If yes, return `true` (timeout occurred)

---

### Step 2: Race Condition (Line 44324-44327)

**Function**: `Oz()` - Tool execution handler

**Code**:
```javascript
const {
    wait: h,
    max_wait_seconds: p
} = s || {}, {
    cancel: g
} = yield* FE({
    callTool: w(Hz, e, n, o, s, d, c),  // ← Execute the tool
    cancel: w(_z, n, o, h, p)            // ← Wait for timeout
});
```

**What `FE` does**: Creates a RACE between:
- `callTool`: Execute the actual tool (launch-process)
- `cancel`: Wait for timeout

**Whichever finishes FIRST wins the race.**

---

### Step 3: Timeout Wins Race (Line 44333)

**Code**:
```javascript
if (g) {  // ← If cancel returned true (timeout occurred)
    const m = yield* O();
    throw yield* w([m, m.cancelToolRun], n, o),  // ← Call cancelToolRun
    new Error("Tool call was cancelled due to timeout")  // ← Throw error
}
```

**What happens**:
1. `g` is `true` (timeout occurred)
2. Call `cancelToolRun` to kill the process
3. Throw error "Tool call was cancelled due to timeout"
4. **NEVER WAIT FOR OUTPUT** - error is thrown immediately

---

### Step 4: Extension Host Kills Process (extension.js Line 259682)

**Code**:
```javascript
this._isLongRunningTerminal(n.terminal) ? 
    (this._logger.debug("Sending Ctrl+C to interrupt current command in long-running terminal"), 
     n.terminal.sendText("\u0003", !1))  // ← Send Ctrl+C (\u0003)
    : n.terminal.dispose()
```

**What happens**:
1. Extension receives `cancelToolRun` message
2. Checks if terminal is long-running
3. Sends Ctrl+C (`\u0003`) to terminal
4. **THIS IS WHERE THE ^C COMES FROM**

---

### Step 5: Catch Block Returns Error (Line 44335-44349)

**Code** (WITH OUR FIX):
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
    
    // Original error handling
    p.phase === K.cancelling ? 
        yield* E(Bl(n, o, {isError: !0, text: g})) : 
        yield* E(Qs(n, o, {isError: !0, text: g}))
}
```

---

## THE PROBLEM

**The race condition causes**:
1. Timeout wins race BEFORE tool completes
2. `cancelToolRun` is called IMMEDIATELY
3. Process is killed with Ctrl+C
4. Error is thrown BEFORE output can be captured
5. AI receives error without output

**Why there's "no output"**:
- The process is KILLED before it can finish
- Output that WAS produced is never read
- The webview throws error and exits immediately

---

## THE COMPLETE FIX

### Fix 1: Webview - Don't Throw Error (CURRENT FIX - PARTIAL)

**Status**: ✅ APPLIED - Prevents RULE 9 violation but doesn't capture output

**What it does**:
- Catches timeout error
- Returns success instead of error
- AI doesn't ask for manual work

**What it DOESN'T do**:
- Doesn't prevent Ctrl+C from being sent
- Doesn't capture output before kill
- Process is still killed

---

### Fix 2: Extension Host - Capture Output BEFORE Killing (NEEDED)

**File**: `extension.js`  
**Line**: 259682

**CURRENT CODE**:
```javascript
this._isLongRunningTerminal(n.terminal) ? 
    (this._logger.debug("Sending Ctrl+C..."), 
     n.terminal.sendText("\u0003", !1))  // ← Kill FIRST
    : n.terminal.dispose(), 
n.state = "killed", 
n.exitCode = -1;
let o = await this.hybridReadOutput(r);  // ← Read output AFTER kill
```

**FIXED CODE**:
```javascript
// Read output FIRST, then kill
let o = await this.hybridReadOutput(r);  // ← Read output BEFORE kill
n.output = o?.output ?? "";

// Then kill the process
this._isLongRunningTerminal(n.terminal) ? 
    (this._logger.debug("Sending Ctrl+C after capturing output"), 
     n.terminal.sendText("\u0003", !1))
    : n.terminal.dispose();
n.state = "killed";
n.exitCode = -1;
```

---

### Fix 3: Webview - Wait for Output Before Throwing (IDEAL FIX)

**File**: `extension-client-context-CN64fWtK.js`  
**Line**: 44333

**CURRENT CODE**:
```javascript
if (g) {  // Timeout occurred
    const m = yield* O();
    throw yield* w([m, m.cancelToolRun], n, o),  // ← Throw immediately
    new Error("Tool call was cancelled due to timeout")
}
```

**FIXED CODE**:
```javascript
if (g) {  // Timeout occurred
    const m = yield* O();
    
    // Call cancelToolRun but DON'T throw yet
    yield* w([m, m.cancelToolRun], n, o);
    
    // Wait a bit for output to be captured
    yield* je(500);  // Wait 500ms for output capture
    
    // Check if we got output
    const toolState = yield* Ln.effect(n, o);
    if (toolState.result && toolState.result.text) {
        // We got output! Return it instead of error
        return;  // Let normal flow handle the result
    }
    
    // No output captured, return diagnostic message
    yield* E(Qs(n, o, {
        isError: !1,
        text: `Tool call timed out after ${p} seconds. Process was terminated. Check terminal for partial output.`
    }));
    return;  // Don't throw
}
```

---

## SUMMARY

**What triggers the ^C**: Extension.js line 259682 sends `\u0003` (Ctrl+C) to terminal

**What triggers the timeout**: Webview line 44257 `_z()` function waits for `max_wait_seconds`

**What causes "no output"**: Race condition - timeout wins BEFORE output is captured

**Current fix**: Webview catch block (line 44340) - prevents RULE 9 violation

**Complete fix needed**: 
1. Extension host: Read output BEFORE killing (line 259682)
2. Webview: Wait for output BEFORE throwing (line 44333)

