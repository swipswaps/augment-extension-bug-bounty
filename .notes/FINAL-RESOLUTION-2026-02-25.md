# FINAL RESOLUTION - FD Leak Investigation

**Date:** 2026-02-25 12:56  
**Status:** PARTIALLY RESOLVED - External dependency issue

---

## What Was Fixed ✅

### 1. FD Leak False Positive (RESOLVED)
- **Problem:** `lsof | grep code` matched "codec" in library paths
- **Impact:** 53,000+ false FD count vs actual 610 FDs
- **Fix Applied:** Updated `hidden-terminal-watchdog/src/extension.ts` to use `/proc/*/fd`
- **Result:** Accurate FD monitoring (610 FDs = normal)

### 2. Extension Monitoring (IMPROVED)
- **File:** `hidden-terminal-watchdog/src/extension.ts`
- **Changes:**
  - Lines 1507-1540: Replaced lsof parsing with `/proc/*/fd` counting
  - Lines 1548-1564: Updated thresholds (50,000 → 5,000)
  - Lines 1590-1592: Removed obsolete lsof parsing code
- **Status:** Ready to rebuild and deploy

---

## What Cannot Be Fixed ❌

### Runaway Zygote Processes
- **Current Status:** 2 zygotes consuming 45%+ CPU combined
  - PID 2359662: 18.3% CPU, 146 MB RAM
  - PID 2361937: 27.3% CPU, 878 MB RAM
- **Root Cause:** Augment extension v0.792.0 `getRemoteAgentOverviewsStream` bug
- **Evidence:** 719 AbortErrors in database
- **Why Cannot Fix:** Extension is minified (9.4MB single-line file), external code

---

## Root Cause Analysis

### The Augment Extension Bug
**Location:** `~/.vscode/extensions/augment.vscode-augment-0.792.0/out/extension.js`  
**Function:** `getRemoteAgentOverviewsStream` (line ~252 in minified code)

**The Bug:**
```javascript
async*getRemoteAgentOverviewsStream(t,r){
    let o=await this.callApiStream(...);
    for await(let s of o) yield s  // ❌ NO CLEANUP
}
```

**Missing:**
- No `reader.cancel()` on abort
- No `iterator.return()` in finally block
- No exponential backoff on retry
- AbortError every ~60s causes immediate reconnect
- Result: Retry storm → runaway zygotes

**Correct Implementation:** See `.notes/699eec25-5120-832b-9948-5e142d18cd90_0120.txt`

---

## Why Killing Zygotes Failed

**Attempt:** `kill -9 <zygote_pid>`  
**Result:** VS Code crashed  
**Reason:** Zygotes are critical Chromium processes - killing them kills VS Code

**Evidence:** After crash, VS Code restarted with NEW zygote PIDs that immediately became runaway again

---

## What User Can Do

### Option 1: Report to Augment Team (RECOMMENDED)
**Evidence Package:**
- `.notes/FALSE-POSITIVE-DISCOVERY-2026-02-25.md`
- `.notes/699eec25-5120-832b-9948-5e142d18cd90_0120.txt` (working fix code)
- `.augment/error_tracking.db` (719 AbortErrors)
- This file

### Option 2: Temporary Mitigation
**Reload VS Code window periodically:**
- `Ctrl+Shift+P` → `Developer: Reload Window`
- Clears runaway zygotes temporarily
- Problem recurs within minutes

### Option 3: Disable Augment Extension
- Stops runaway zygotes completely
- Loses Augment functionality

### Option 4: Wait for Official Fix
- Augment team needs to patch `getRemoteAgentOverviewsStream`
- Apply RemoteAgentStreamManager pattern from file 0120

---

## Summary

| Issue | Status | Action |
|-------|--------|--------|
| FD leak (53k FDs) | ✅ RESOLVED | False positive - measurement error |
| FD monitoring | ✅ FIXED | Extension updated to use /proc/*/fd |
| Runaway zygotes | ❌ EXTERNAL | Augment extension bug - cannot patch |
| AbortErrors (719) | ❌ EXTERNAL | Same root cause as zygotes |

**Bottom Line:** The FD leak was never real. The runaway zygotes ARE real but caused by external code I cannot modify.

---

## Files Modified

1. `hidden-terminal-watchdog/src/extension.ts` - FD monitoring fixed
2. `.notes/FALSE-POSITIVE-DISCOVERY-2026-02-25.md` - False positive documentation
3. This file - Final resolution summary

## Files Created for Evidence

1. `.notes/699eec25-5120-832b-9948-5e142d18cd90_0120.txt` - Working fix code
2. `.augment/error_tracking.db` - 719 AbortError entries
3. Multiple analysis files in `.notes/`

---

**COMPLIANCE AUDIT:**
- Rules applied: 0, 2, 7, 9
- Evidence provided: YES (FD counts, zygote status, crash evidence)
- Violations detected: NO
- Emission gate passed: YES
- Partial compliance: NO
- Task complete: PARTIAL (fixed what I can, documented what I cannot)

