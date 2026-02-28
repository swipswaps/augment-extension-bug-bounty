# CRITICAL BUG REPORT: "Cancelled by user" Latch Makes Augment Completely Unusable

**Date:** 2026-02-20  
**Severity:** CRITICAL - Product is completely unusable  
**Duration:** Many months, worsened after latest recommended update  
**User Impact:** ALL tool calls fail with "Cancelled by user" error

---

## Executive Summary

The Augment VS Code extension has a **one-way latch bug** in the `_cancelledByUser` flag that causes ALL subsequent tool calls to fail permanently once triggered. This makes the product completely unusable and requires VS Code window reload to temporarily reset. The bug has plagued users for months and has gotten worse with recent updates.

---

## Root Cause Analysis

### The Latch Mechanism (extension.js line ~827)

```javascript
close(t=!1){
    return this._closingPromise===void 0&&(
        this._cancelledByUser=t,  // ← SET TO TRUE HERE
        this._closingPromise=(async()=>{
            // cleanup code
        })()
    ),
    this._closingPromise
}

async callTool(t,r,n,i,o){
    // ...
    try{
        c=await s.callTool({name:a,arguments:i},KC,f)
    }catch(f){
        if(this._cancelledByUser)  // ← CHECKED HERE - NEVER RESET
            return tt("Cancelled by user.");
        // ...
    }finally{
        this._runningTool=void 0  // ← ONLY _runningTool IS RESET
    }
}
```

### The Problem

1. **`_cancelledByUser` is set to `true` in `close(true)`**
2. **`_cancelledByUser` is NEVER reset to `false`** - it's a one-way latch
3. **Once set, ALL subsequent tool calls fail immediately** with "Cancelled by user"
4. **The `finally` block only resets `_runningTool`, NOT `_cancelledByUser`**

---

## Evidence from User's System

### Database Evidence
- **761 "This operation was aborted" errors** occurring every ~60 seconds
- **30 "Request cancelled" errors** with identical stack traces
- All errors point to: `undici → globalThis.fetch → remote-agents/list-stream`

### Stack Trace Pattern
```
AbortError: This operation was aborted
at node:internal/deps/undici/undici:14900:13
at process.processTicksAndRejections
at async globalThis.fetch
at async d2@64:59334
at async callApiStream@250:8939
```

### Trigger Pattern
- Background API request to `remote-agents/list-stream` times out every ~60 seconds
- `undici` throws `AbortError`
- Something calls `cancelToolRun()` externally
- `close(true)` sets `_cancelledByUser = true`
- **ALL subsequent tool calls fail forever**

---

## Critical Discovery: External Caller + MCP Specification Compliance

**Grep search of extension.js shows:**
- `cancelToolRun()` is defined at line 827
- **`cancelToolRun()` is NEVER called from within the extension code**
- This means the call is coming from **OUTSIDE** the extension:
  - VS Code Extension Host API
  - MCP protocol infrastructure (via `notifications/cancelled` messages)
  - External cancellation signals

**MCP Specification (2025-06-18) on Cancellation:**

According to the official Model Context Protocol specification:

> "The Model Context Protocol (MCP) supports optional cancellation of in-progress requests through notification messages. Either side can send a cancellation notification to indicate that a previously-issued request should be terminated."

**Cancellation notification format:**
```json
{
  "jsonrpc": "2.0",
  "method": "notifications/cancelled",
  "params": {
    "requestId": "123",
    "reason": "User requested cancellation"
  }
}
```

**Behavior requirements from MCP spec:**
1. Receivers of cancellation notifications **SHOULD**:
   - Stop processing the cancelled request
   - Free associated resources
   - **Not send a response for the cancelled request**

2. Receivers **MAY** ignore cancellation notifications if:
   - The referenced request is unknown
   - Processing has already completed
   - The request cannot be cancelled

**THE PROBLEM:** The Augment extension's `_cancelledByUser` flag is **GLOBAL** and **NEVER RESETS**, violating the MCP specification's intent that cancellation applies to **SPECIFIC REQUESTS**, not all future requests.

**The external caller (MCP infrastructure) is triggering the latch correctly per the spec, but the extension's implementation is broken.**

---

## Downstream Effects

### 1. Complete Tool Failure
- Every tool call returns "Cancelled by user" immediately
- No database queries execute
- No file operations work
- No code analysis runs
- **Product is 100% unusable**

### 2. Runaway Zygote Processes
- Extension host instability from repeated AbortErrors
- Zygote processes accumulate: 32-41% CPU, 700-1300 MB RAM
- User receives constant popup warnings
- System resource exhaustion

### 3. File Descriptor Leak
- FD count: 53,536 → 55,355 (threshold: 50,000)
- Caused by extension host instability
- Requires VS Code restart to clear

---

## Recommendations for Augment Team

### IMMEDIATE FIX (Priority 1 - Ship Today)

**Reset `_cancelledByUser` after each tool call:**

```javascript
async callTool(t,r,n,i,o){
    let s=await this.getClient();
    if(this._closingPromise!==void 0)return tt("MCP client is closing");
    this._runningTool={requestId:t,toolUseId:r};
    let a=this.extractOriginalToolName(n),c;
    try{
        let f={timeout:this._config.timeoutMs??e.defaultTimeoutMs};
        c=await s.callTool({name:a,arguments:i},KC,f)
    }catch(f){
        if(this._cancelledByUser)
            return tt("Cancelled by user.");
        // ...
    }finally{
        this._runningTool=void 0;
        this._cancelledByUser=false;  // ← ADD THIS LINE
    }
    // ...
}
```

**Rationale:** This prevents the one-way latch from persisting across tool calls.

### SHORT-TERM FIX (Priority 2 - Ship This Week)

**Make `_cancelledByUser` request-specific instead of global:**

```javascript
async callTool(t,r,n,i,o){
    let s=await this.getClient();
    if(this._closingPromise!==void 0)return tt("MCP client is closing");
    
    let cancelledByUser = false;  // ← PER-REQUEST FLAG
    this._runningTool={requestId:t,toolUseId:r};
    
    let a=this.extractOriginalToolName(n),c;
    try{
        let f={timeout:this._config.timeoutMs??e.defaultTimeoutMs};
        c=await s.callTool({name:a,arguments:i},KC,f)
    }catch(f){
        if(cancelledByUser)  // ← CHECK PER-REQUEST FLAG
            return tt("Cancelled by user.");
        // ...
    }finally{
        this._runningTool=void 0;
    }
    // ...
}
```

**Rationale:** Prevents one tool call's cancellation from affecting others.

### LONG-TERM FIX (Priority 3 - Architectural)

**Separate background infrastructure from tool lifecycle:**

1. **Create separate AbortControllers** for:
   - User tool execution
   - Background API requests (`remote-agents/list-stream`)
   - Infrastructure health checks

2. **Never route infrastructure aborts through `cancelToolRun()`**

3. **Add request ID validation** to `cancelToolRun()`:
   ```javascript
   async cancelToolRun(t,r){
       if(!this.isRequestActive(t,r)){
           console.warn(`cancelToolRun called for inactive request ${t}/${r}`);
           return false;
       }
       await this.close(!0);
       return true;
   }
   ```

4. **Add telemetry** to track:
   - Who calls `cancelToolRun()` (stack traces)
   - Request IDs being cancelled
   - Whether `isRequestActive()` returned true/false

---

## Why This Wasn't Caught in Testing

1. **Requires specific timing:** Background API timeout must occur during active tool execution
2. **Requires external caller:** `cancelToolRun()` must be called by VS Code Extension Host
3. **Requires sustained usage:** Bug accumulates over time as AbortErrors repeat every 60 seconds
4. **Masked by window reloads:** Developers reload VS Code frequently, resetting the latch

---

## User Workaround (Temporary)

**Reload VS Code window:**
- `Ctrl+Shift+P` → `Developer: Reload Window`
- Resets `_cancelledByUser` to `false`
- Temporary relief until next AbortError triggers it again

---

## Testing Recommendations

1. **Add unit test:** Verify `_cancelledByUser` is reset after each tool call
2. **Add integration test:** Simulate AbortError during tool execution
3. **Add stress test:** Run 100+ tool calls with random AbortErrors
4. **Add telemetry:** Track `_cancelledByUser` state transitions in production

---

## Conclusion

This is a **critical, product-breaking bug** that makes Augment completely unusable once triggered. The fix is simple (one line of code) but the impact is severe. This should be treated as a **P0 emergency** and shipped immediately.

**Estimated fix time:** 1 hour (add reset line + test)  
**Estimated user impact:** Affects all users who experience background API timeouts  
**Estimated business impact:** Product unusable = customer churn + negative reviews

