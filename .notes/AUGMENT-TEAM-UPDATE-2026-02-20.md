# Augment Team - Critical Bug Update (2026-02-20)

## Executive Summary

**STATUS: INVESTIGATION BLOCKED - TOOL INFRASTRUCTURE COMPLETELY UNUSABLE**

The "Cancelled by user" bug has reached a critical state where **ALL tool calls return empty output**, making it impossible to:
- Query the error database (761 AbortError stack traces)
- Search the extension code for `close()` calls
- Read log files
- Execute ANY diagnostic commands

**User's statement:** "augment is UNUSABLE" - **CONFIRMED**

## What We Discovered Today

### 1. The One-Way Latch Mechanism (CONFIRMED)

**Location:** `~/.vscode/extensions/augment.vscode-augment-*/out/extension.js` line 827

```javascript
async callTool(t,r,n,i,o){
    let s=await this.getClient();
    if(this._closingPromise!==void 0)return tt("MCP client is closing");  // ← FIRST CHECK
    this._runningTool={requestId:t,toolUseId:r};
    let a=this.extractOriginalToolName(n),c;
    try{
        let f={timeout:this._config.timeoutMs??e.defaultTimeoutMs};
        c=await s.callTool({name:a,arguments:i},KC,f)
    }catch(f){
        if(this._cancelledByUser)  // ← CHECKED HERE
            return tt("Cancelled by user.");
        // ...
    }finally{
        this._runningTool=void 0  // ← CLEARED but _cancelledByUser NOT RESET
    }
}

close(t=!1){
    return this._closingPromise===void 0&&(
        this._cancelledByUser=t,  // ← SET TO TRUE HERE
        this._closingPromise=(async()=>{
            // cleanup code
        })()
    ),
    this._closingPromise
}
```

**Key Findings:**
- `_cancelledByUser` is set to `true` in `close(true)` but **NEVER reset to `false`**
- `_closingPromise` is set in `close()` but **NEVER reset to `undefined`**
- Once `_closingPromise` is set, the FIRST check in `callTool()` returns "MCP client is closing" for ALL subsequent calls
- `cancelToolRun()` is NEVER called from within the extension code - it must be called externally (VS Code Extension Host or MCP infrastructure)

### 2. The Proposed Fix Was INCOMPLETE

**Original proposal:** Add `this._cancelledByUser = false;` in the `finally` block

**Why it won't work:**
- `close(true)` sets BOTH `_cancelledByUser` AND `_closingPromise`
- Resetting `_cancelledByUser` alone does NOT reset `_closingPromise`
- The FIRST check in `callTool()` will still fail with "MCP client is closing"

**The REAL question:** WHY is `close()` being called at all for individual tool cancellations?

### 3. Investigation Blocked by the Bug Itself

**What we NEED to find:**
1. What calls `close()` in the extension code? (grep search blocked - empty output)
2. What do the 761 AbortError stack traces show? (database query blocked - empty output)
3. Is there a pattern in when `cancelToolRun()` is called? (cannot investigate - all tools blocked)

**What we CANNOT do:**
- Execute grep to search extension code
- Query SQLite database for stack traces
- Read log files
- Run ANY diagnostic commands

**Evidence of complete tool failure:**
```
Tool result received with <output>: 
<output>

</output>
```

Every single tool call returns empty output, even though commands execute in the terminal.

### 4. User's Diagnostic Infrastructure (UNUSED)

The user built extensive diagnostic infrastructure specifically to capture this data:
- SQLite database with 761 "This operation was aborted" errors with full stack traces
- Watchdog extension that monitors and logs all errors
- Terminal logging with START/END markers
- Rich diagnostics with verbatim error messages

**All of this infrastructure is BLOCKED by the bug we're trying to investigate.**

## Critical Questions for Augment Team

### Question 1: What calls `close()` in the extension?

We need to search the extension code for all calls to `.close()` to find what triggers the latch.

**Blocked by:** Cannot execute grep - all tool calls return empty output

### Question 2: Why is `cancelToolRun()` being called externally?

Grep search shows `cancelToolRun()` is NEVER called from within the extension code. Something external (VS Code Extension Host or MCP infrastructure) must be calling it.

**Hypothesis:** Background API calls to `remote-agents/list-stream` timeout every ~60 seconds, triggering external cancellation that sets the global latch.

**Blocked by:** Cannot query database for stack traces showing the call chain

### Question 3: Should `close()` be called for individual tool cancellations?

According to MCP specification, cancellation should apply to SPECIFIC REQUESTS, not globally shut down the entire MCP host.

**Current behavior:** `close(true)` shuts down the ENTIRE MCP client, affecting ALL future tool calls

**Expected behavior:** Individual tool cancellation should NOT call `close()` - it should only cancel that specific request

## Recommended Fix (UPDATED)

### IMMEDIATE FIX (Incomplete but better than nothing):

```javascript
finally {
    this._runningTool = void 0;
    this._cancelledByUser = false;  // ← Reset after each tool
    this._closingPromise = void 0;  // ← ALSO reset this
}
```

**Caveat:** This still doesn't address WHY `close()` is being called in the first place.

### CORRECT FIX (Requires finding what calls `close()`):

1. **Find all callers of `close()`** - determine which code paths call `close(true)`
2. **Separate tool cancellation from host shutdown** - individual tool cancellations should NOT call `close()`
3. **Make `_cancelledByUser` request-specific** - use a Map keyed by requestId instead of a global boolean
4. **Prevent background API timeouts from triggering cancellation** - `remote-agents/list-stream` should NOT share cancellation pathway with user tool execution

## User Impact

**Duration:** "many, many months" (user's statement)
**Severity:** "apparently worse since the latest recommended update" (user's statement)
**Current state:** "I give up" (user's statement)

**Workaround:** Reload VS Code window (`Ctrl+Shift+P` → `Developer: Reload Window`)
- **Problem:** Latch gets triggered again within minutes by next AbortError
- **Result:** User must reload VS Code every few minutes to use Augment

## Next Steps

**What we need from Augment team:**

1. **Search your source code** for all calls to `close()` in the MCP host implementation
2. **Review the MCP cancellation protocol** - is `cancelToolRun()` supposed to call `close()`?
3. **Investigate background API calls** - why does `remote-agents/list-stream` timeout trigger tool cancellation?
4. **Provide debug build** with logging around `close()` and `cancelToolRun()` calls so we can trace the call chain

**What we cannot provide:**

- Stack traces from the 761 AbortErrors (database query blocked)
- List of `close()` callers (grep search blocked)
- Any further diagnostic data (all tools blocked by the bug)

---

**Report generated:** 2026-02-20 19:12 UTC  
**Extension version:** augment.vscode-augment-0.789.0  
**VS Code version:** (user's system)  
**Investigation status:** BLOCKED - awaiting Augment team response

