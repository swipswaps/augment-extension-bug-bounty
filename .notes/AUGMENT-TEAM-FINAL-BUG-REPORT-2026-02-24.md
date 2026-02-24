# CRITICAL BUG REPORT: File Descriptor Leak in Augment VS Code Extension

**Date:** 2026-02-24  
**Reporter:** User (via months of investigation)  
**Severity:** CRITICAL (System-level resource exhaustion)  
**Affected Versions:** v0.754.3, v0.792.0  

---

## Executive Summary

The Augment VS Code extension contains a **critical file descriptor leak** in `getRemoteAgentOverviewsStream` that causes:
- **50,000+ open file descriptors** (normal: <500)
- **Runaway zygote processes** consuming 100% CPU
- **MCP tool infrastructure failure** ("Cancelled by user" errors)
- **System instability** requiring VS Code reload every few hours

**Root Cause:** Missing stream cleanup + immediate retry without backoff = positive feedback loop

---

## Evidence Summary

### Quantitative Evidence (from error tracking database)
- **6,787** runaway zygote detections
- **5,917** FD leak warnings
- **803** AbortErrors from timeout wrapper
- **4,828** invalid_line_range errors
- **4,338** feature_flags_timeout errors
- **1,560** supervisor prompt generations with empty conversation ID

### FD Count Timeline
- Normal baseline: 200-500 FDs
- After 1 hour: 10,000-15,000 FDs
- After 4 hours: 30,000-40,000 FDs
- After 8 hours: **50,000-57,000 FDs** (system threshold exceeded)

---

## Root Cause Analysis

### Primary Leak Source

**File:** `~/.vscode/extensions/augment.vscode-augment-*/out/extension.js`  
**Function:** `getRemoteAgentOverviewsStream` (line 249 in v0.754.3, line 295 in v0.792.0)  
**Issue:** Incomplete stream cleanup on AbortError

### The Failure Loop

```
1. Extension calls getRemoteAgentOverviewsStream
2. Timeout wrapper (d2) aborts after 60s
3. Stream cleanup is INCOMPLETE:
   - No response.body.cancel()
   - No iterator.return()
   - No AbortController disposal
4. Retry logic IMMEDIATELY reconnects (NO BACKOFF)
5. Leaked FD from previous attempt remains open
6. Loop repeats every ~60s
7. FD count grows monotonically
8. At 50k FDs: zygote enters busy-wait (EMFILE error)
9. CPU spikes to 100%, system becomes unstable
```

### Positive Feedback Loop

```
timeout → retry → leak → timeout faster → retry faster → leak faster
```

**Why it accelerates:**
- Each leaked FD increases kernel pressure
- Kernel pressure slows network I/O
- Slower I/O causes more timeouts
- More timeouts = more retries = more leaks

---

## Nine Missing Safeguards

1. ❌ No `await stream.return()` in finally block
2. ❌ No `response.body.cancel()` on abort
3. ❌ No exponential backoff on retry
4. ❌ No guard against concurrent stream instances
5. ❌ No block if extension is closing
6. ❌ No debounce on webview reload
7. ❌ Zygote fork retry is immediate (Chromium behavior)
8. ❌ No timeout clearance in d2 wrapper
9. ❌ No `_closingPromise` latch reset

---

## Buggy Code Pattern (Reconstructed from Minified Source)

```javascript
// BUGGY: Missing cleanup
async function* getRemoteAgentOverviewsStream(timestamp, signal) {
    const response = await fetch(url, { signal });
    
    for await (const chunk of response.body) {
        yield chunk;
    }
    
    // ❌ NO CLEANUP:
    // - response.body.cancel() never called
    // - iterator.return() never called
    // - AbortController never disposed
}

// BUGGY: Immediate retry without backoff
async function streamLoop() {
    while (true) {  // ← Unbounded retry loop
        try {
            const stream = await getRemoteAgentOverviewsStream();
            for await (const chunk of stream) {
                handleChunk(chunk);
            }
        } catch (err) {
            if (err.message === "AbortError") {
                continue;  // ← Immediate reconnect, no backoff
            }
            throw err;
        }
    }
}
```

---

## Permanent Fix Requirements

### 1. Guaranteed Stream Cleanup

```javascript
async function* getRemoteAgentOverviewsStream(timestamp, signal) {
    let response = null;
    let iterator = null;
    
    try {
        response = await fetch(url, { signal });
        iterator = response.body[Symbol.asyncIterator]();
        
        for await (const chunk of iterator) {
            yield chunk;
        }
    } finally {
        // ✅ GUARANTEED CLEANUP
        if (iterator) {
            await iterator.return?.();
        }
        if (response?.body) {
            await response.body.cancel();
        }
    }
}
```

### 2. Exponential Backoff

```javascript
let retryDelay = 1000;  // Start at 1s
const maxDelay = 30000;  // Cap at 30s

while (true) {
    try {
        // ... stream logic ...
        retryDelay = 1000;  // Reset on success
    } catch (err) {
        if (err.message === "AbortError") {
            await sleep(retryDelay);
            retryDelay = Math.min(retryDelay * 2, maxDelay);
            continue;
        }
        throw err;
    }
}
```

### 3. Single-Instance Guard

```javascript
let activeStreamInstance = null;

async function startStream() {
    if (activeStreamInstance) {
        return;  // Prevent concurrent streams
    }
    
    activeStreamInstance = true;
    try {
        // ... stream logic ...
    } finally {
        activeStreamInstance = null;
    }
}
```

---

## Complete Working Fix

**See:** `.notes/69935426-075c-8329-b732-ceb8a5e0b600_0116.txt` lines 1213-2477  
(Contains production-ready TypeScript implementation with all safeguards)

---

## Temporary Mitigation (User-Side)

**Hardening preload wrapper:**
```bash
./.augment-hardening/launch-hardened-vscode.sh
```

This wraps `globalThis.fetch` with proper cleanup until official fix is deployed.

---

## Why Automated Patching Failed

**Extension code is minified:**
- Entire extension in ONE LINE (~293,705 characters)
- Line 249 (v0.754.3) contains the entire bundled extension
- Automated string replacement is unsafe
- Requires source-level fix + rebuild

---

## Recommended Actions

### For Augment Team (URGENT)

1. **Immediate:** Add stream cleanup to `getRemoteAgentOverviewsStream`
2. **Immediate:** Add exponential backoff to retry loop
3. **High Priority:** Add single-instance guard
4. **High Priority:** Fix `_closingPromise` one-way latch (line 603)
5. **Medium Priority:** Add FD growth monitoring
6. **Medium Priority:** Gate supervisor prompt on non-empty conversation ID

### For Users (Temporary)

1. Use hardening preload: `./.augment-hardening/launch-hardened-vscode.sh`
2. Reload VS Code window when FD count exceeds 10,000
3. Monitor FD count: `lsof -p $(pgrep -f extensionHost) | wc -l`

---

## Success Criteria

✅ FD count stable under 500  
✅ No monotonic FD growth over 24 hours  
✅ AbortError occasional, not storming  
✅ No zygote fork death loops  
✅ No webview reload storms  
✅ TCP ESTABLISHED sockets remain low (<20)  

---

## Supporting Documentation

- **Root cause analysis:** `.notes/ARCHITECTURAL-ROOT-CAUSE.md`
- **Complete solution:** `.notes/COMPLETE-SOLUTION-GUIDE.md`
- **Remediation plan:** `.augment/MASTER-REMEDIATION-PLAN.md`
- **Analysis summary:** `.notes/ANALYSIS-SUMMARY-0114-0115-0116.md`
- **Working fix code:** `.notes/69935426-075c-8329-b732-ceb8a5e0b600_0116.txt` (lines 1213-2477)

---

**END OF REPORT**

