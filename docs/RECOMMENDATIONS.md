# Recommendations for Augment Team

**Report ID**: `174ab568-83ed-4b09-9ac9-dce2f07c6fcf`  
**Date**: 2026-02-09

---

## Immediate Actions (P0 - Critical)

### 1. Apply Bug 1 Fix (Cleanup Ordering)

**Priority**: 🔴 CRITICAL — Affects 100% of users

**Change**: Move `cleanupTerminal()` call to AFTER output-reading loop in `onDidCloseTerminal` handler

**Location**: `extension.js` line 259373 (pretty-printed)

**Code change**:
```javascript
// BEFORE:
onDidCloseTerminal(async h => {
  this._logger.debug(`Got onDidCloseTerminal event: ${h.name}`),
  e._completionStrategy?.cleanupTerminal(h),    // ← MOVE THIS
  this._removeLongRunningTerminal(h);
  // ... output-reading loop ...
})

// AFTER:
onDidCloseTerminal(async h => {
  this._logger.debug(`Got onDidCloseTerminal event: ${h.name}`),
  this._removeLongRunningTerminal(h);
  // ... output-reading loop ...
  e._completionStrategy?.cleanupTerminal(h)     // ← TO HERE
})
```

**Impact**: Fixes 100% data loss on Script Capture (T0) strategy

**Risk**: Low — simple reordering, no logic changes

---

### 2. Apply Bug 2 Fix (Stream Reader Timeout)

**Priority**: 🟠 HIGH — Affects users with large outputs

**Change**: Increase per-chunk timeout from 100ms to 16 seconds

**Location**: `extension.js` line 259968 (pretty-printed)

**Code change**:
```javascript
// BEFORE:
setTimeout(() => {
  // ... timeout handler ...
}, 100)  // ← 100ms

// AFTER:
setTimeout(() => {
  // ... timeout handler ...
}, 16e3)  // ← 16 seconds
```

**Impact**: Fixes partial data loss on large outputs

**Risk**: Low — timeout is still present, just more generous

**Alternative**: Make timeout configurable via settings

---

### 3. Apply Bug 3 Fix (Script File Flush Race)

**Priority**: 🟠 HIGH — Affects 100% of wait=true processes

**Change**: Add 500ms delay after process completion, before reading script file

**Locations**: 
- `_checkSingleProcessCompletion` (wait=true path)
- `onDidCloseTerminal` handler (non-wait path)

**Code change**:
```javascript
// In _checkSingleProcessCompletion:
if(!o.isCompleted) return !1;
this._logger.debug(`${n} determined process ${r} is done, reading output`);

// ADD THIS:
await new Promise(r2 => setTimeout(r2, 500));

let s;
try {
  s = await this.hybridReadOutput(r)
}

// In onDidCloseTerminal:
this._removeLongRunningTerminal(h);

// ADD THIS:
await new Promise(r => setTimeout(r, 500));

// ... output-reading loop ...
```

**Impact**: Fixes tail-end truncation on all wait=true processes

**Risk**: Low — adds 500ms latency to process completion, but ensures data integrity

**Alternative**: Use `fsync()` or wait for `script` process to fully exit

---

### 4. Fix Bug 5 (Terminal Accumulation)

**Priority**: 🔴 CRITICAL — Causes complete tool failure

**Root cause**: `_cancelledByUser` is a one-way latch that never resets

**Recommended fix**: Reset `_cancelledByUser` to `false` after MCP host restart

**Location**: `extension.js` line 235772 (initialization), line 235861 (set to true)

**Code change**:
```javascript
// In MCP host restart handler (after i.restart()):
this._cancelledByUser = false  // ← RESET THE LATCH
```

**Alternative fixes**:
1. **Terminal lifecycle management**: Automatically close terminals after N minutes of inactivity
2. **Terminal pooling**: Reuse existing terminals instead of creating new ones
3. **Resource monitoring**: Warn when terminal count exceeds threshold (e.g., 50)
4. **Graceful degradation**: Return partial output instead of "Cancelled by user" error

**Impact**: Prevents permanent tool failure under resource pressure

**Risk**: Medium — requires careful testing to ensure reset doesn't interfere with genuine cancellations

---

## Short-Term Improvements (P1 - High)

### 5. Add Telemetry for Output Loss Detection

**Recommendation**: Add logging to detect when output loss occurs

**Metrics to track**:
- Script file size before/after cleanup
- Number of lines captured vs expected
- Timeout occurrences in stream reader
- Terminal accumulation count
- `_cancelledByUser` flag state changes

**Benefit**: Proactive detection of regressions and new edge cases

---

### 6. Make Timeouts Configurable

**Recommendation**: Add VS Code settings for timeout values

**Settings**:
```json
{
  "augment.process.streamTimeout": 16000,  // ms per chunk
  "augment.process.flushDelay": 500,       // ms after completion
  "augment.terminal.maxActive": 50         // warn threshold
}
```

**Benefit**: Users can tune for their specific environment

---

### 7. Improve Error Messages

**Current**: "Cancelled by user." (ambiguous)

**Recommended**:
- "Cancelled by user." → "Tool call cancelled (user requested)"
- "Cancelled by user." (when user didn't cancel) → "Tool call cancelled (MCP connection reset)"
- Add error codes: `ERR_USER_CANCEL`, `ERR_MCP_RESET`, `ERR_TIMEOUT`

**Benefit**: Users can distinguish genuine cancellations from bugs

---

## Long-Term Improvements (P2 - Medium)

### 8. Redesign Output Capture Strategy

**Current issues**:
- Relies on `/usr/bin/script` utility (platform-specific)
- File-based capture has flush race conditions
- Cleanup ordering is fragile

**Recommended approach**:
1. **Direct PTY capture**: Read from PTY file descriptors directly, no intermediate file
2. **Stream-based**: Process output as it arrives, no polling
3. **Buffered writes**: Accumulate in memory, write to disk only on demand

**Benefits**:
- Eliminates flush race (Bug 3)
- Eliminates cleanup ordering issue (Bug 1)
- Reduces disk I/O
- More reliable cross-platform

**Risk**: High — major architectural change, requires extensive testing

---

### 9. Terminal Resource Management

**Recommendation**: Implement automatic terminal lifecycle management

**Features**:
1. **Auto-close**: Close terminals after 5 minutes of inactivity
2. **Terminal pooling**: Reuse terminals for similar commands
3. **Resource limits**: Hard limit on active terminals (e.g., 100)
4. **Cleanup on window reload**: Clear all terminals on VS Code window reload

**Benefits**:
- Prevents Bug 5 (terminal accumulation)
- Reduces resource consumption
- Improves extension stability

---

### 10. Add Unit Tests for Output Capture

**Recommendation**: Create comprehensive test suite for output capture logic

**Test cases**:
1. Empty output
2. Small output (<1 KB)
3. Large output (>63 KB)
4. Output with delays between chunks
5. Output with rapid bursts
6. Process exit before output fully written
7. Terminal close during output capture
8. Multiple concurrent processes

**Benefits**:
- Prevents regressions
- Validates fixes
- Documents expected behavior

---

## Documentation Improvements

### 11. Document Output Capture Mechanism

**Recommendation**: Add developer documentation explaining:
- How Script Capture (T0) works
- When cleanup happens
- How timeouts are applied
- How `_untruncatedContentManager` works
- Terminal lifecycle

**Benefit**: Helps future developers avoid similar bugs

---

### 12. Add User-Facing Documentation

**Recommendation**: Document known limitations and workarounds

**Topics**:
- Output display cap (63 KB) and how to use `view-range-untruncated`
- Terminal accumulation and when to reload VS Code window
- How to report output loss issues

**Benefit**: Reduces support burden, improves user experience

---

## Testing Recommendations

### 13. Regression Test Suite

**Recommendation**: Add these test cases to CI/CD pipeline

**Test cases** (from this bug report):
```bash
# Test 1: Basic output capture (Bug 1)
echo "START: test1" && echo "Line 1" && echo "Line 2" && echo "Line 3" && echo "END: test1"

# Test 2: Large output with delays (Bug 2 + Bug 3)
for i in {1..20}; do 
  echo "=== Stage $i ===" && seq 1 100 && sleep 0.05 && echo "stage-$i-complete"
done && echo "All 20 stages complete" && echo "END: test2"

# Test 3: Very large output (Bug 4)
seq 1 1000  # 72 KB output

# Test 4: Terminal hygiene (Bug 5 prevention)
# Run 100 commands in sequence, verify no "Cancelled by user" errors
```

**Expected results**: All tests pass with 100% output capture

---

## Priority Matrix

| Recommendation | Priority | Effort | Impact | Timeline |
|---|---|---|---|---|
| 1. Fix Bug 1 | 🔴 P0 | Low | Critical | Immediate |
| 2. Fix Bug 2 | 🟠 P1 | Low | High | Immediate |
| 3. Fix Bug 3 | 🟠 P1 | Low | High | Immediate |
| 4. Fix Bug 5 | 🔴 P0 | Medium | Critical | Next release |
| 5. Add telemetry | 🟠 P1 | Medium | High | Next release |
| 6. Configurable timeouts | 🟠 P1 | Low | Medium | Next release |
| 7. Improve error messages | 🟠 P1 | Low | Medium | Next release |
| 8. Redesign output capture | 🟡 P2 | High | High | Long-term |
| 9. Terminal management | 🟡 P2 | Medium | Medium | Long-term |
| 10. Add unit tests | 🟡 P2 | High | High | Long-term |
| 11. Developer docs | 🟡 P2 | Medium | Medium | Long-term |
| 12. User docs | 🟡 P2 | Low | Low | Long-term |
| 13. Regression tests | 🟠 P1 | Medium | High | Next release |

---

## Contact

For questions or clarifications on these recommendations:

**Reporter**: swipswaps  
**Report ID**: `174ab568-83ed-4b09-9ac9-dce2f07c6fcf`  
**Date**: 2026-02-09


