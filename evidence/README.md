# Evidence

**Report ID**: `174ab568-83ed-4b09-9ac9-dce2f07c6fcf`  
**Extension**: `augment.vscode-augment` v0.754.3

---

## Overview

This directory contains forensic evidence for all bugs identified in this report.

---

## Files

### `extension-analysis.md`

Complete analysis of extension.js with line numbers from pretty-printed version.

**Contents**:
- Code paths for all 5 bugs
- Line-by-line traces
- Variable state tracking
- Function call sequences

### `code-traces.md`

Detailed code traces showing execution flow for each bug.

**Contents**:
- Bug 1: Cleanup ordering execution flow
- Bug 2: Stream reader timeout logic
- Bug 3: Script file flush race timing
- Bug 5: Terminal accumulation → MCP reset → _cancelledByUser latch

### `logs/`

Directory containing test logs and before/after comparisons.

**Contents**:
- `bug-1-before.log` — Empty output before fix
- `bug-1-after.log` — Full output after fix
- `bug-2-before.log` — 5/20 stages before fix
- `bug-2-after.log` — 20/20 stages after fix
- `bug-3-before.log` — Missing END marker before fix
- `bug-3-after.log` — END marker present after fix
- `bug-5-error.log` — "Cancelled by user." error messages

---

## Pretty-Printed Extension.js

**Original file**: `~/.vscode/extensions/augment.vscode-augment-0.754.3/out/extension.js`  
**Size**: 8.3 MB (minified, single line)  
**Pretty-printed**: 293,705 lines

**Command used**:
```bash
npx --yes js-beautify --type js \
  -f ~/.vscode/extensions/augment.vscode-augment-0.754.3/out/extension.js \
  -o /tmp/extension-pretty.js
```

**Key locations** (line numbers from pretty-printed version):

| Bug | Location | Line # | Description |
|---|---|---|---|
| Bug 1 | `onDidCloseTerminal` | 259373 | `cleanupTerminal()` called too early |
| Bug 2 | `_readProcessStreamWithTimeout` | 259968 | 100ms per-chunk timeout |
| Bug 3 | `_checkSingleProcessCompletion` | 259315-259385 | No flush delay |
| Bug 3 | `onDidCloseTerminal` | 259373 | No flush delay (non-wait path) |
| Bug 5 | `_cancelledByUser` init | 235772 | Initialized to `false` |
| Bug 5 | `_cancelledByUser` set | 235861 | Set to `true` by `close(true)` |
| Bug 5 | `_cancelledByUser` check | 235911 | Checked in `callTool()` catch |
| Bug 5 | `cancel-tool-run` handler | 270918 | Message handler triggers close |

---

## Code Evidence

### Bug 1: Cleanup Ordering

**Line 259373** (pretty-printed):
```javascript
onDidCloseTerminal(async h => {
  this._logger.debug(`Got onDidCloseTerminal event: ${h.name}`),
  e._completionStrategy?.cleanupTerminal(h),    // ← LINE 259373
  this._removeLongRunningTerminal(h);
  // ... output-reading loop starts here ...
})
```

**Problem**: `cleanupTerminal(h)` deletes script file before output-reading loop runs.

---

### Bug 2: Stream Reader Timeout

**Line 259968** (pretty-printed):
```javascript
setTimeout(() => {
  d || (d = true,
  this._logger.debug(`Read timeout occurred for process ${n}`),
  h({done: true, value: void 0}))
}, 100)  // ← LINE 259968: 100ms timeout
```

**Problem**: 100ms per-chunk timeout too aggressive for real-world data streams.

---

### Bug 3: Script File Flush Race

**Lines 259315-259385** (pretty-printed):
```javascript
async _checkSingleProcessCompletion(r, n) {
  // ... check if process is done ...
  if(!o.isCompleted) return !1;
  
  this._logger.debug(`${n} determined process ${r} is done, reading output`);
  
  // ❌ NO DELAY — reads file immediately
  let s;
  try {
    s = await this.hybridReadOutput(r)
  }
  // ...
}
```

**Problem**: File read before `script` utility flushes final buffer.

---

### Bug 5: Terminal Accumulation

**Line 235772** (initialization):
```javascript
this._cancelledByUser = !1  // false
```

**Line 235861** (set to true):
```javascript
close(t) {
  // ...
  this._cancelledByUser = t  // set to true when t=true
  // ...
}
```

**Line 235911** (checked):
```javascript
async callTool(t, e, r, n) {
  try {
    // ... call MCP tool ...
  } catch (i) {
    if (this._cancelledByUser)
      return "Cancelled by user."  // ← LINE 235911
    // ...
  }
}
```

**Problem**: `_cancelledByUser` is NEVER reset back to `false` — one-way latch.

---

## Test Results

### Before Fixes

| Test | Result | Output |
|---|---|---|
| Bug 1 test | ❌ FAIL | Empty `<output>` section |
| Bug 2 test | ❌ FAIL | 5/20 stages captured |
| Bug 3 test | ❌ FAIL | Last 3 lines missing |
| Bug 5 test | ❌ FAIL | "Cancelled by user." after 100 commands |

### After Fixes

| Test | Result | Output |
|---|---|---|
| Bug 1 test | ✅ PASS | All lines captured, START/END markers |
| Bug 2 test | ✅ PASS | 20/20 stages captured |
| Bug 3 test | ✅ PASS | END marker present |
| Bug 5 test | ✅ PASS | No errors (RULE 22 mitigation) |

---

## Verification Commands

### Bug 1 Verification

```bash
echo "START: test1" && echo "Line 1" && echo "Line 2" && echo "Line 3" && echo "END: test1"
```

**Before fix**: Empty output  
**After fix**: All 5 lines captured

### Bug 2 + Bug 3 Verification

```bash
bash reproduction/test-bug-2.sh
```

**Before Bug 2 fix**: 5/20 stages  
**After Bug 2 fix**: 20/20 stages  
**Before Bug 3 fix**: Missing END marker  
**After Bug 3 fix**: END marker present

### Bug 5 Verification

```bash
bash reproduction/test-bug-5.sh
```

**Before mitigation**: "Cancelled by user." after ~100 commands  
**After mitigation**: All 150 commands complete

---

## Additional Evidence

- **VS Code version**: 1.108.1 (bug present), 1.109.0 (bug persists, but reload clears state)
- **Extension version**: 0.754.3
- **OS**: Fedora Linux 43 (also affects macOS, Windows)
- **Capture strategy**: Script Capture (T0) via `/usr/bin/script` (util-linux-script-2.41.3)

---

## Contact

For access to full evidence files or additional verification:

**Reporter**: swipswaps  
**Report ID**: `174ab568-83ed-4b09-9ac9-dce2f07c6fcf`  
**Date**: 2026-02-09


