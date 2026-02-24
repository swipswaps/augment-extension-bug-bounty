# Master Remediation Plan: FD Leak Root Cause Fix

## Executive Summary

Based on analysis files 0114, 0115, and 0116, the FD leak is a **correlated systemic failure cascade** with a proven fix pattern.

**Primary Root Cause:** `getRemoteAgentOverviewsStream` at line 64:59334 (d2 timeout wrapper)
- Timeout aborts stream after 60s
- Cleanup is incomplete (stream not disposed, body not cancelled)
- Immediate retry without backoff
- No single-instance guard

**Amplifiers:**
- Supervisor prompt generation with empty conversation ID (1560 occurrences)
- Feature flag timeout causing webview reload storms (520 occurrences)
- Zygote fork retry loops

**The Positive Feedback Loop:**
```
timeout → retry → leak → timeout faster → retry faster → leak faster
```

## Diagnostic Tools Already Created

✅ `.augment/leak-inspector.js` - TCP socket and FD count inspector
✅ `.augment-hardening/augment-hardening-preload.js` - Runtime patch for fetch cleanup
✅ `.augment-hardening/launch-hardened-vscode.sh` - Launcher with hardening
✅ `.notes/ARCHITECTURAL-ROOT-CAUSE.md` - Complete explanation
✅ `.notes/ANALYSIS-SUMMARY-0114-0115-0116.md` - Summary of latest findings

## Definitive Isolation Test (From File 0115)

**Goal:** Confirm `getRemoteAgentOverviewsStream` is primary leak

**Procedure:**
1. Find extension host PID: `ps aux | grep -- '--extensionHost'`
2. Baseline FD count: `watch -n 2 "ls /proc/<PID>/fd | wc -l"`
3. Disable stream invocation in extension
4. Restart VS Code
5. Re-measure FD count for 15+ minutes

**Expected Result:**
- If FD stabilizes → confirmed primary driver
- If FD still grows → secondary amplifier

## Permanent Fix Requirements (From File 0116)

### FIX 1: Enforce Single Active Stream
```javascript
let activeRemoteAgentStream: Promise<void> | null = null;

if (activeRemoteAgentStream) return;

finally {
  activeRemoteAgentStream = null;
}
```

### FIX 2: Guaranteed Stream Cleanup
```javascript
let iterator;
try {
  iterator = stream[Symbol.asyncIterator]();
  for await (const chunk of iterator) { ... }
} finally {
  if (iterator?.return) await iterator.return();
  if (response?.body?.cancel) await response.body.cancel();
}
```

### FIX 3: Add Exponential Backoff
```javascript
await sleep(backoff);
backoff = Math.min(backoff * 2, 30000);
```

### FIX 4: Block Webview Reload During Backend Instability
```javascript
let backendHealthy = true;
if (3 consecutive AbortErrors) backendHealthy = false;
if (!backendHealthy) block webview reload;
```

### FIX 5: Hard FD Growth Guard
```javascript
if (FD count grows > 10% in 60 seconds) {
  stop all streaming;
  log critical;
  fail safe;
}
```

### FIX 6: Prevent Empty Conversation Prompt Loop
```javascript
if (conversationId is empty) {
  do not generate supervisor prompt;
  log once;
  wait for valid ID;
}
```

## Execution Plan

### Phase 1: Confirmation (Manual)
1. Run leak inspector: `node .augment/leak-inspector.js <extension-host-PID>`
2. Observe TCP socket growth correlation with FD growth
3. Disable stream and confirm FD stabilization

### Phase 2: Apply Hardening (Automated)
1. Close all VS Code windows
2. Launch with hardening: `./.augment-hardening/launch-hardened-vscode.sh`
3. Monitor FD count for 24 hours

### Phase 3: Permanent Extension Patch (Requires Augment Team)
The hardening preload is a **temporary mitigation**. Permanent fix requires:
- Patching extension.js at line 64:59334 (d2 wrapper)
- Adding single-instance guard to stream loop
- Implementing exponential backoff
- Adding stream finalization in finally blocks

## Success Criteria

✅ FD count stable under 500
✅ No monotonic FD growth over 24 hours
✅ AbortError occasional, not storming
✅ No zygote fork death loops
✅ No webview reload storms
✅ TCP ESTABLISHED sockets remain low (<20)

## Current Status

- **Diagnostic tools**: Created ✅
- **Hardening preload**: Created ✅
- **Isolation test**: Pending (requires manual execution)
- **VS Code restart with hardening**: Pending (requires user action)
- **Permanent extension patch**: Pending (requires Augment team)

## Next Immediate Action

**User must execute:**
```bash
# 1. Close all VS Code windows
pkill -f "code.*6984bd27-4494-8330-9803-7b6895a48aa5"

# 2. Wait for processes to die
sleep 5

# 3. Launch with hardening
./.augment-hardening/launch-hardened-vscode.sh
```

This will activate the runtime patches and break the positive feedback loop.

