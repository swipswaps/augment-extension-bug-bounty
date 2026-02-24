# Analysis Summary: Files 0114, 0115, 0116

## File 0114: Diagnostic Database Dump (79KB)

**Key Findings:**
- **1026 occurrences**: `invalid_line_range` errors (startLine=-1, stopLine=-1)
- **490 occurrences**: AbortError at line 64:59334 (d2 timeout wrapper)
- **520 occurrences**: `feature_flags_timeout` - webview waiting for flags times out
- **1560 occurrences**: "Generating supervisor prompt with empty conversation ID" - **MAJOR FD LEAK CONTRIBUTOR**
- **730 warnings**: FD leak warnings (range 50,360–57,492)
- **35 occurrences**: Runaway zygote detected
- **Error rate**: 101% in `Y.resolveAsyncMsg` function (more errors than successful invocations)

**Critical Evidence:**
- Chat input completions disabled, but FD leak persists
- Leak is architectural, not from a single feature

## File 0115: Executable Compliance Template (10KB)

**Purpose:** Structured diagnostic checklist for definitive leak confirmation

**9 Required Experiments:**
1. Baseline Idle (disable stream, observe 10 min)
2. Single Stream, No Timeout (confirm proper cleanup)
3. Forced Timeout, No Retry (confirm abort path cleanup)
4. Retry Enabled (detect latch re-entry)
5. Webview Disabled (confirm renderer churn impact)

**Required Evidence Matrix:**
- Extension Host FD count
- Active TCP sockets (ESTABLISHED / TIME_WAIT / CLOSE_WAIT)
- Undici dispatcher stats (in-process)
- Stream lifecycle events
- Webview reload count
- Renderer process PID churn

**6 Permanent Fix Requirements:**
1. Global single-flight guard
2. Structured cleanup (try/finally)
3. Exponential backoff (no immediate retry)
4. Prevent webview reload until streamInFlight === false
5. Explicit abort path: abortController.abort() + response.body.cancel() + iterator.return()
6. Hard assertion: if (activeStreams > 1) throw error

## File 0116: Systemic Failure Cascade Analysis (90KB)

**The Complete Failure Loop:**
```
1. Extension makes streaming request (getRemoteAgentOverviewsStream)
2. Timeout wrapper (d2) aborts it after 60s
3. Cleanup is incomplete (stream not disposed, body not cancelled)
4. Stream retry logic immediately reconnects (NO BACKOFF)
5. Webview waiting on flags times out
6. Webview reloads
7. Zygote forks renderer
8. Renderer dies (incomplete init)
9. Zygote retries fork (immediate, no backoff)
10. Loop continues → CPU spike, memory growth, FD leak
```

**This is a positive feedback loop:**
```
timeout → retry → leak → timeout faster → retry faster → leak faster
```

**Nine Missing Safeguards:**
1. No `await stream.return()` in finally block
2. No `response.body.cancel()` on abort
3. No exponential backoff on retry
4. No guard against concurrent stream instances
5. No block if extension is closing
6. No debounce on webview reload
7. Zygote fork retry is immediate (Chromium behavior)
8. No timeout clearance in d2 wrapper
9. No `_closingPromise` latch reset

**Primary Root Cause:**
Unbounded streaming retry without guaranteed cleanup at line 64:59334 (d2 timeout wrapper)

**Amplifiers:**
- Webview reload storms
- Supervisor prompt churn (1560 times with empty conversation ID)
- Missing conversation ID gating

**Symptoms:**
- FD 50k+
- Zygote killed repeatedly
- Feature flag timeout
- Invalid line range errors
- AbortError loop every ~60s

## Next Steps (From File 0116)

**Definitive Isolation Test:**
1. Disable `getRemoteAgentOverviewsStream` invocation
2. Restart VS Code
3. Observe for 15+ minutes
4. If FD growth stops → confirmed primary driver
5. If FD still grows → secondary amplifier

**Permanent Fix Pattern (Working Code Provided in File 0116):**
- Single-instance guard
- Guaranteed stream cleanup (iterator.return() + response.body.cancel())
- Exponential backoff (1s → 30s max)
- Backend health gate (block webview reload during instability)
- Hard FD growth guard (stop if >10% growth in 60s)
- Empty conversation ID gating (prevent supervisor prompt loop)

