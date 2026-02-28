# FALSE POSITIVE DISCOVERY - FD Leak Investigation

**Date:** 2026-02-25  
**Status:** ✅ ROOT CAUSE IDENTIFIED - NO ACTUAL FD LEAK

## Executive Summary

The entire months-long FD leak investigation was based on a **measurement error**. There is **NO actual file descriptor leak** in VS Code.

## The False Positive

### Wrong Measurement Method
```bash
lsof 2>/dev/null | grep -c code
# Result: 53,279 FDs (WRONG - includes false matches)
```

This command matched:
- ✅ VS Code processes (correct)
- ❌ Files with "**codec**" in the path (FALSE POSITIVE)
- ❌ Any library path containing "code" (FALSE POSITIVE)

### What Was Actually Matched

The command matched WirePlumber's Bluetooth codec libraries:
```
/usr/lib64/spa-0.2/bluez5/libspa-codec-bluez5-lc3.so
/usr/lib64/spa-0.2/bluez5/libspa-codec-bluez5-opus.so
/usr/lib64/spa-0.2/bluez5/libspa-codec-bluez5-g722.so
/usr/lib64/spa-0.2/bluez5/libspa-codec-bluez5-sbc.so
... (and many more)
```

Each of these libraries was loaded into memory multiple times across different threads, creating ~50,000 false matches.

## Correct Measurements

### Method 1: Sum FDs by PID
```bash
total=0
for pid in $(pgrep -f "/usr/share/code/code"); do
  count=$(lsof -p $pid 2>/dev/null | wc -l)
  total=$((total + count))
done
echo "$total FDs"
# Result: 2,463 FDs (CORRECT)
```

### Method 2: Count /proc/*/fd (Most Accurate)
```bash
total=0
for pid in $(pgrep -f "/usr/share/code/code"); do
  count=$(ls /proc/$pid/fd 2>/dev/null | wc -l)
  total=$((total + count))
done
echo "$total FDs"
# Result: 611 FDs (CORRECT - kernel-native count)
```

## Actual Status

- **VS Code FD Count:** 611 FDs (completely normal)
- **Expected Range:** 500-1,000 FDs for Electron app with extensions
- **Threshold Used:** 50,000 FDs (based on false measurement)
- **Correct Threshold:** 5,000 FDs (realistic for actual VS Code)

## Impact of False Positive

### Database Pollution
- **6,000+ false warnings** in `.augment/error_tracking.db`
- All `fd_leak_warning` entries from before 2026-02-25 are false positives

### Wasted Investigation Effort
- Months of debugging non-existent leak
- Created hardening preload (unnecessary)
- Created auto-reload daemon (unnecessary)
- Analyzed 142,077 lines of watchdog logs
- Searched through minified extension code
- Created multiple bug reports and fix documentation

### Obsolete Documentation
The following files are now obsolete:
- `.notes/AUGMENT-TEAM-FINAL-BUG-REPORT-2026-02-24.md`
- `.notes/FINAL-INVESTIGATION-SUMMARY-2026-02-24.md`
- `.augment/FIX-FD-LEAK-NOW.md`
- `.augment/APPLY-FIX-NOW.sh`
- `.augment/PERMANENT-FIX-getRemoteAgentOverviewsStream.sh`

## The Fix

### Extension Code Fixed
**File:** `hidden-terminal-watchdog/src/extension.ts`

**Before (WRONG):**
```typescript
const lsofProcess = spawn('lsof', [], { stdio: ['ignore', 'pipe', 'pipe'] });
// ... collect output ...
const codeLines = stdout.split('\n').filter(line => line.includes('code'));
const fdCount = codeLines.length;  // FALSE POSITIVE
```

**After (CORRECT):**
```typescript
const fdCountProcess = spawn('sh', ['-c', `
    total=0
    for pid in $(pgrep -f "/usr/share/code/code"); do
        count=$(ls /proc/$pid/fd 2>/dev/null | wc -l)
        total=$((total + count))
    done
    echo $total
`], { stdio: ['ignore', 'pipe', 'pipe'] });
// ... collect output ...
const fdCount = parseInt(stdout.trim(), 10);  // CORRECT
```

**Threshold Updated:**
- Old: 50,000 FDs (based on false measurement)
- New: 5,000 FDs (realistic for actual VS Code)

## Lessons Learned

1. **Always verify measurement methodology** before investigating
2. **String matching in lsof output is unreliable** - use PID-based filtering
3. **Use kernel-native sources** (`/proc/*/fd`) when possible
4. **Verify assumptions with multiple measurement methods**
5. **Question long-standing "facts"** if they don't make sense

## CRITICAL: Runaway Zygotes Are REAL

**The FD leak was false, but the runaway zygotes are a SEPARATE REAL PROBLEM:**

Current status (2026-02-25 08:17):
- **PID 1732431:** 25.6% CPU, 641 MB RAM, running 193 minutes
- **PID 968120:** 9.9% CPU, 599 MB RAM, running 226 minutes
- **PID 968179:** 5.1% CPU, 81 MB RAM, running 116 minutes

These zygotes have:
- Normal FD count (48 FDs)
- Normal thread count (12 threads)
- **ABNORMAL CPU usage** (stuck in busy loop)

**This is a CPU leak, not an FD leak.**

## What Was False vs What Is Real

### FALSE POSITIVES ❌
- FD leak (53,000+ FDs) - measurement error
- All `fd_leak_warning` entries in database

### REAL PROBLEMS ✅
- Runaway zygote processes (25%+ CPU)
- AbortError on getRemoteAgentOverviewsStream (719 occurrences)
- _cancelledByUser latch issue (30 occurrences)

## Next Steps

1. ✅ Fix extension FD counting method (DONE)
2. ✅ Update threshold to realistic value (DONE)
3. ⏳ Rebuild extension to apply fixes
4. ⏳ Clean up obsolete FD leak documentation
5. ⏳ Archive false positive FD warnings in database
6. **⚠️ INVESTIGATE runaway zygote CPU leak** (REAL PROBLEM)
7. **⚠️ INVESTIGATE getRemoteAgentOverviewsStream AbortErrors** (REAL PROBLEM)

