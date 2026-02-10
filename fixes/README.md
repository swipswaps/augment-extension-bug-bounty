# Fixes and Patches

**Report ID**: `174ab568-83ed-4b09-9ac9-dce2f07c6fcf`  
**Extension**: `augment.vscode-augment` v0.754.3

---

## Overview

This directory contains patches and fix scripts for all bugs identified in this report.

---

## Applying Fixes

### Prerequisites

1. **Backup extension.js** before applying any fixes:
```bash
cp ~/.vscode/extensions/augment.vscode-augment-0.754.3/out/extension.js \
   ~/.vscode/extensions/augment.vscode-augment-0.754.3/out/extension.js.backup
```

2. **Verify extension location**:
```bash
ls -la ~/.vscode/extensions/augment.vscode-augment-*/out/extension.js
```

---

## Bug 1: Cleanup Ordering

### Fix Method

Use the provided `apply-fix.cjs` script to automatically reorder the cleanup call.

### Manual Application

**File**: `~/.vscode/extensions/augment.vscode-augment-0.754.3/out/extension.js`

**Find** (minified, single line):
```javascript
e._completionStrategy?.cleanupTerminal(h),this._removeLongRunningTerminal(h);for(let[m,A]of this._processes)
```

**Replace with**:
```javascript
this._removeLongRunningTerminal(h);for(let[m,A]of this._processes)
```

**Then find** (later in the same handler):
```javascript
}e._completionStrategy?.cleanupTerminal(h)})
```

**Replace with**:
```javascript
}})
```

**Then add** (at the end of the handler, before the closing `})`):
```javascript
e._completionStrategy?.cleanupTerminal(h)
```

### Verification

```bash
echo "START: test1" && echo "Line 1" && echo "Line 2" && echo "Line 3" && echo "END: test1"
```

**Expected**: All lines captured, START/END markers present

---

## Bug 2: Stream Reader Timeout

### Fix Method

Change timeout value from `100` to `16e3` (16 seconds).

### Manual Application

**File**: `~/.vscode/extensions/augment.vscode-augment-0.754.3/out/extension.js`

**Find** (minified, single line):
```javascript
h({done:!0,value:void 0}))},100)});return await Promise.race
```

**Replace with**:
```javascript
h({done:!0,value:void 0}))},16e3)});return await Promise.race
```

### Verification

```bash
bash reproduction/test-bug-2.sh
```

**Expected**: All 20 stages captured (not just 5)

---

## Bug 3: Script File Flush Race

### Fix Method

Add 500ms delay after process completion, before reading script file.

### Manual Application

**File**: `~/.vscode/extensions/augment.vscode-augment-0.754.3/out/extension.js`

**Location 1**: `_checkSingleProcessCompletion` (wait=true path)

**Find**:
```javascript
if(!o.isCompleted)return!1;this._logger.debug(`${n} determined process ${r} is done, reading output`);let s;try{s=await this.hybridReadOutput(r)}
```

**Replace with**:
```javascript
if(!o.isCompleted)return!1;this._logger.debug(`${n} determined process ${r} is done, reading output`);await new Promise(r2=>setTimeout(r2,500));let s;try{s=await this.hybridReadOutput(r)}
```

**Location 2**: `onDidCloseTerminal` handler (non-wait path)

**Find**:
```javascript
this._removeLongRunningTerminal(h);for(let[m,A]of this._processes)
```

**Replace with**:
```javascript
this._removeLongRunningTerminal(h);await new Promise(r=>setTimeout(r,500));for(let[m,A]of this._processes)
```

### Verification

```bash
bash reproduction/test-bug-2.sh
```

**Expected**: END marker present (not truncated)

---

## Bug 4: Output Display Cap

**Status**: ⚪ BY DESIGN — No fix needed

**Workaround**: Use `view-range-untruncated` tool with Reference ID from truncation footer

---

## Bug 5: Terminal Accumulation

**Status**: ✅ MITIGATED via RULE 22 (Terminal Hygiene)

**Fix Method**: Prevention via assistant behavior rules, not code patch

**Mitigation**: See `rule-22-mitigation.md` for complete RULE 22 implementation

**Code fix recommendation**: Reset `_cancelledByUser` to `false` after MCP host restart

---

## Automated Fix Script

### `apply-fix.cjs`

This Node.js script automatically applies all three code fixes (Bug 1, 2, 3) to extension.js.

**Usage**:
```bash
node apply-fix.cjs
```

**What it does**:
1. Locates extension.js file
2. Creates backup with timestamp
3. Applies all three fixes
4. Verifies changes
5. Reports success/failure

**Safety**:
- Creates backup before any changes
- Validates file exists before modifying
- Checks for expected patterns before replacing
- Rolls back on error

---

## Rollback

### Restore Original

```bash
cp ~/.vscode/extensions/augment.vscode-augment-0.754.3/out/extension.js.backup \
   ~/.vscode/extensions/augment.vscode-augment-0.754.3/out/extension.js
```

### Verify Rollback

```bash
echo "START: test1" && echo "Line 1" && echo "END: test1"
```

**Expected** (with bugs): Empty `<output>` section

---

## Verification Checklist

After applying all fixes:

- [ ] **Bug 1 fixed**: `echo "START" && echo "Line 1" && echo "END"` → all lines captured
- [ ] **Bug 2 fixed**: `bash test-bug-2.sh` → all 20 stages captured
- [ ] **Bug 3 fixed**: `bash test-bug-2.sh` → END marker present
- [ ] **Bug 5 mitigated**: No "Cancelled by user." errors in normal usage

---

## Notes

- **Reload VS Code** after applying fixes for changes to take effect
- **Test thoroughly** before relying on fixes in production
- **Report any issues** to swipswaps with Report ID: `174ab568-83ed-4b09-9ac9-dce2f07c6fcf`


