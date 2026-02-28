# Root Cause Analysis: "Cancelled by user" Errors

## Investigation Summary

**Date:** 2026-02-20  
**Issue:** All Augment tool calls return "Cancelled by user" error, making Augment UNUSABLE  
**Database Evidence:** 761 "This operation was aborted" errors occurring every ~60 seconds

## Key Findings

### 1. The Cancellation Mechanism (Line 827 in extension.js)

```javascript
isRequestActive(t,r){
    return this._runningTool?.requestId===t&&this._runningTool?.toolUseId===r
}

async cancelToolRun(t,r){
    return this.isRequestActive(t,r)?(await this.close(!0),!0):!1
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

### 2. When `_runningTool` is Set (Line 827 in extension.js)

```javascript
async callTool(t,r,n,i,o){
    let s=await this.getClient();
    if(this._closingPromise!==void 0)return tt("MCP client is closing");
    this._runningTool={requestId:t,toolUseId:r};  // ← SET HERE
    let a=this.extractOriginalToolName(n),c;
    try{
        let f={timeout:this._config.timeoutMs??e.defaultTimeoutMs};
        c=await s.callTool({name:a,arguments:i},KC,f)
    }catch(f){
        if(this._cancelledByUser)  // ← CHECKED HERE
            return tt("Cancelled by user.");
        // ...
    }finally{
        this._runningTool=void 0  // ← CLEARED HERE
    }
    // ...
}
```

### 3. Critical Discovery: `cancelToolRun()` is NEVER Called Internally

**Grep search results:** Only ONE reference to `cancelToolRun(` found - the definition itself at line 827.

**This means:**
- `cancelToolRun()` is NOT called from anywhere within the Augment extension code
- It must be called EXTERNALLY by VS Code Extension Host or MCP infrastructure
- The call is coming from OUTSIDE the extension

### 4. The Contradiction

**ChatGPT's hypothesis:** Background API calls (like `remote-agents/list-stream`) are setting `_runningTool` and triggering cancellation.

**Evidence contradicts this:**
- `_runningTool` is ONLY set in `callTool()` method (line 827)
- Background API calls do NOT go through `callTool()`
- Therefore, background API calls do NOT set `_runningTool`
- Therefore, `isRequestActive()` should return FALSE for background API calls

### 5. The Real Question

**If `cancelToolRun()` is being called externally, WHO is calling it and WHY?**

Possible sources:
1. VS Code Extension Host API
2. MCP protocol infrastructure
3. AbortController timeout handlers
4. External cancellation signals

## Next Steps

1. **Search for external callers:** Look for VS Code Extension Host code that might call `cancelToolRun()`
2. **Check MCP protocol:** Investigate if MCP protocol has cancellation mechanisms
3. **Trace AbortError:** Follow the AbortError from `remote-agents/list-stream` to see if it triggers external cancellation
4. **Add logging:** Instrument `cancelToolRun()` to log WHO is calling it and with WHAT parameters

## Conclusion

The root cause is NOT that background API calls are setting `_runningTool`. The root cause is that **something external to the extension is calling `cancelToolRun()` and we need to find out what**.

