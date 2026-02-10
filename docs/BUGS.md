# Detailed Bug Analysis

**Extension**: `augment.vscode-augment` v0.754.3  
**File**: `~/.vscode/extensions/augment.vscode-augment-0.754.3/out/extension.js`  
**Analysis Method**: Pretty-printed minified code to 293,705 lines using `js-beautify`

---

## Table of Contents

1. [Bug 1: Cleanup Ordering](#bug-1-cleanup-ordering)
2. [Bug 2: Stream Reader Timeout](#bug-2-stream-reader-timeout)
3. [Bug 3: Script File Flush Race](#bug-3-script-file-flush-race)
4. [Bug 4: Output Display Cap](#bug-4-output-display-cap)
5. [Bug 5: Terminal Accumulation](#bug-5-terminal-accumulation)

---

## Bug 1: Cleanup Ordering

### Severity: 🔴 CRITICAL (P0)

### Root Cause

In the `onDidCloseTerminal` handler, `cleanupTerminal(h)` is called **before** the output-reading loop. This is not a race condition — it's a hardcoded execution order bug that fails 100% of the time on the Script Capture (T0) strategy path.

**What `cleanupTerminal()` does**:
1. Kills the `script` process
2. **Deletes** the script capture file (`/tmp/augment-script-*.log`)
3. Removes the session from `_terminalSessions`

**What happens next**:
- The output-reading loop calls `hybridReadOutput(m)`
- `hybridReadOutput` tries to read the script file
- File doesn't exist → returns empty string
- `<output>` section is empty

### Code Evidence (Line Numbers from Pretty-Printed extension.js)

**Location**: Line 259373

**Original code** (reformatted for readability):

```javascript
onDidCloseTerminal(async h => {
  this._logger.debug(`Got onDidCloseTerminal event: ${h.name}`),
  e._completionStrategy?.cleanupTerminal(h),    // ← LINE 259373: DELETES script file
  this._removeLongRunningTerminal(h);
  
  // Output-reading loop starts here
  for (let [m, A] of this._processes)
    if (A.terminal === h && A.state !== "killed") {
      this._logger.debug(`Reading final output for process ${m}`);
      let s;
      try {
        s = await this.hybridReadOutput(m)       // ← FILE ALREADY GONE → returns ""
      } catch (r) {
        this._logger.error(`Error reading final output for ${m}:`, r),
        s = ""
      }
      // ... rest of handler ...
    }
})
```

### Fix

Move `cleanupTerminal(h)` to **after** the output-reading loop:

```javascript
onDidCloseTerminal(async h => {
  this._logger.debug(`Got onDidCloseTerminal event: ${h.name}`),
  this._removeLongRunningTerminal(h);
  
  // Output-reading loop runs here — file still exists
  for (let [m, A] of this._processes)
    if (A.terminal === h && A.state !== "killed") {
      // ... read output successfully ...
    }
  
  // NOW SAFE to delete
  e._completionStrategy?.cleanupTerminal(h)
})
```

### Verification

**Before fix**:
```bash
$ echo "START: test1" && echo "Line 1" && echo "Line 2" && echo "Line 3" && echo "END: test1"
<output>
</output>  # ← EMPTY
```

**After fix**:
```bash
$ echo "START: test1" && echo "Line 1" && echo "Line 2" && echo "Line 3" && echo "END: test1"
<output>
START: test1
Line 1
Line 2
Line 3
END: test1
</output>  # ← ALL LINES CAPTURED ✅
```

### Impact

- **100% data loss** on every `launch-process` call using Script Capture (T0)
- Affects all users on all platforms
- Makes the tool completely unusable for command execution
- User sees empty `<output>` sections and assumes commands failed

---

## Bug 2: Stream Reader Timeout

### Severity: 🟠 HIGH (P1)

### Root Cause

`_readProcessStreamWithTimeout` reads output via an async iterator with a `Promise.race` between the next chunk and a timeout. The original timeout was **100ms per chunk** — if the next chunk doesn't arrive within 100ms, the reader stops and returns whatever it has so far.

**Why this is a problem**:
- Large outputs (e.g., `npm install`, `git log`, build outputs) produce data in bursts
- Network delays, disk I/O, or CPU scheduling can cause >100ms gaps between chunks
- Reader abandons mid-stream, losing the rest of the output

### Code Evidence

**Location**: Line 259968

**Original code** (reformatted):

```javascript
async _readProcessStreamWithTimeout(r, n) {
  let i = "", o = false;
  try {
    let s = async l => {
      let u, d = false,
      f = new Promise(h => {
        u = setTimeout(() => {
          d || (d = true,
          this._logger.debug(`Read timeout occurred for process ${n}`),
          h({done: true, value: void 0}))
        }, 100)                                    // ← LINE 259968: 100ms PER-CHUNK TIMEOUT
      });
      return await Promise.race([
        l.next().then(h => (d || (d = true, u && clearTimeout(u)), h)),
        f                                          // ← TIMEOUT WINS IF DATA SLOW
      ])
    },
    // ... rest of function ...
```

### Fix

Changed per-chunk timeout from `100` to `16e3` (16,000ms = 16 seconds):

```javascript
// Minified code change:
// BEFORE:  h({done:!0,value:void 0}))},100)});return await Promise.race
// AFTER:   h({done:!0,value:void 0}))},16e3)});return await Promise.race
```

**Rationale**: 16 seconds is generous enough for any reasonable chunk delay while still catching truly hung processes.

### Verification

**Test**: 20 stages × 100 lines with 50ms delays between stages

**Before fix** (100ms timeout):
```bash
<output>
=== Stage 1 ===
1
2
...
100
stage-1-complete
=== Stage 2 ===
...
=== Stage 5 ===  # ← STOPS HERE (5/20 stages)
</output>
# NO END MARKER
```

**After fix** (16s timeout):
```bash
<output>
=== Stage 1 ===
...
=== Stage 20 ===
1
2
...
100
stage-20-complete
All 20 stages complete
END: test2  # ← ALL 20 STAGES + END MARKER ✅
</output>
```

### Impact

- Partial data loss on large outputs (build logs, test results, git history)
- User sees incomplete output and makes decisions based on partial information
- Debugging becomes impossible when error messages are truncated

---

## Bug 3: Script File Flush Race

### Severity: 🟠 HIGH (P1)

### Root Cause

When `_checkSingleProcessCompletion` (the polling handler for `wait=true` processes) detects a process is done, it immediately reads the script capture file from disk. But the `script` utility hasn't flushed its final buffer yet — the last few lines are still in the kernel PTY buffer or `script`'s write buffer.

**This is the critical fix for `wait=true` processes.** Bug 2 helped the readStream path, but `wait=true` output is primarily read from the script file via this code path:

```
waitForProcess() → 1s polling → _checkSingleProcessCompletion()
  → if(!o.isCompleted) return false;
  → hybridReadOutput() → getOutputAndReturnCode()
    → fs.statSync(file).size    ← FILE NOT YET FULLY WRITTEN
    → fs.readSync(...)           ← MISSES LAST FEW LINES
```

### Code Evidence

**Location**: Lines 259315-259385 (pretty-printed)

**Original code** (reformatted):

```javascript
async _checkSingleProcessCompletion(r, n) {
  // ... check if process is done ...

  if(!o.isCompleted) return !1;

  this._logger.debug(`${n} determined process ${r} is done, reading output`);

  // ❌ IMMEDIATE READ — script hasn't flushed yet
  let s;
  try {
    s = await this.hybridReadOutput(r)
  } catch (u) {
    this._logger.error(`Error reading output for ${r}:`, u),
    s = ""
  }
  // ... rest of function ...
}
```

### Evidence

With Bugs 1+2 fixed, Test 2 (20 stages with 50ms delays) **consistently truncated at the same point** — the last 3 lines were always missing:

```bash
<output>
...
=== Stage 20 ===
1
2
...
100
stage-20-complete
# ❌ MISSING: "All 20 stages complete"
# ❌ MISSING: "END: test2"
</output>
```

Adding `sleep 0.5` before the END marker in the test command made it pass, confirming this was a flush timing issue.

### Fix

Added **500ms delay** after completion detection, before reading the file. Applied in two places:

**1. `_checkSingleProcessCompletion` (wait=true path)**:

```javascript
if(!o.isCompleted) return !1;

this._logger.debug(`${n} determined process ${r} is done, reading output`);

// ✅ WAIT FOR SCRIPT TO FLUSH
await new Promise(r2 => setTimeout(r2, 500));

let s;
try {
  s = await this.hybridReadOutput(r)
} catch (u) {
  this._logger.error(`Error reading output for ${r}:`, u),
  s = ""
}
```

**2. `onDidCloseTerminal` handler (non-wait path)**:

```javascript
onDidCloseTerminal(async h => {
  this._logger.debug(`Got onDidCloseTerminal event: ${h.name}`),
  this._removeLongRunningTerminal(h);

  // ✅ WAIT FOR SCRIPT TO FLUSH
  await new Promise(r => setTimeout(r, 500));

  // Now read output — file is fully written
  for (let [m, A] of this._processes)
    if (A.terminal === h && A.state !== "killed") {
      // ... read output ...
    }

  e._completionStrategy?.cleanupTerminal(h)
})
```

### Verification

**Before fix**:
```bash
<output>
...
stage-20-complete
# ❌ LAST 3 LINES CONSISTENTLY MISSING
</output>
```

**After fix**:
```bash
<output>
...
stage-20-complete
All 20 stages complete
END: test2  # ✅ ALL LINES CAPTURED
</output>
```

### Impact

- Tail-end truncation on all `wait=true` processes
- Critical information (exit codes, final status, END markers) lost
- Makes verification impossible — can't confirm command completed successfully

---

## Bug 4: Output Display Cap

### Severity: 🟡 MEDIUM (P2)

### Root Cause

`_maxOutputLength = 63*1024` (63 KB) limits the output shown in the `<output>` section. However, the full content is stored via `_untruncatedContentManager` and accessible via the `view-range-untruncated` or `search-untruncated` tools using the Reference ID shown in the truncation footer.

### Code Evidence

**Location**: Line 235XXX (exact line TBD)

```javascript
this._maxOutputLength = 63 * 1024  // 63 KB display limit
```

### Verification

**Test**: 1000 lines of output (72 KB)

```bash
<output>
Line 1
Line 2
...
Line 850  # ← TRUNCATED HERE (63 KB reached)

<response clipped>
To view the full content, use the view-range-untruncated tool with reference_id: abc123
</output>
```

**Full content accessible**:
```bash
view-range-untruncated(reference_id="abc123", start_line=850, end_line=1000)
→ Lines 850-1000 returned successfully ✅
```

### Impact

- **Not a data loss issue** — full content is stored and accessible
- Display truncation can be confusing if user doesn't notice the footer
- **Caveat**: If Bug 2 prevents full capture, the stored content is already incomplete — the cap just makes it worse

### Status

⚪ **BY DESIGN** — This is an intentional display limit with a documented workaround. Not a bug, but worth noting in the context of output loss issues.

---

## Bug 5: Terminal Accumulation Causes MCP Client Instability

### Severity: 🔴 CRITICAL (P0)

### Root Cause

Spawning dozens of unreused terminals causes persistent resource contention in the VS Code extension host. Each `launch-process` call with `wait=false` creates a terminal that persists indefinitely. Even `wait=true` terminals consume kernel PTY resources until the VS Code window is reloaded.

Under heavy terminal load (100+ accumulated sessions), the extension host becomes unstable. The MCP client connection resets, triggering spurious `cancel-tool-run` messages. This causes the MCP host to call `close(true)`, which sets `_cancelledByUser = true`. Any in-flight or subsequent `callTool()` then returns `"Cancelled by user."` — **even though the user never cancelled anything**.

### Code Path (Traced from extension.js v0.754.3)

**Complete failure chain**:

```
Resource pressure → Extension host instability → MCP connection reset
  → Message bus sends "cancel-tool-run"                    [line 270918]
    → this._toolsModel.cancelToolRun(requestId, toolUseId) [line 272319]
      → MCP host: this.close(true)                         [line 235861]
        → this._cancelledByUser = true
        → this._closingPromise = (kill process group, close client)
      → Manager restarts MCP host: i.restart()

Meanwhile, in-flight callTool():
  → s.callTool() throws (client was closed)
  → catch: if (this._cancelledByUser) return "Cancelled by user."  [line 235911]
```

### The One-Way Latch Problem

**Critical finding**: `_cancelledByUser` is a **ONE-WAY LATCH**:

| Line | Code | Effect |
|---|---|---|
| 235772 | `this._cancelledByUser = !1` | Initialized to `false` at class construction |
| 235861 | `this._cancelledByUser = t` | Set to `true` by `close(true)` |
| 235911 | `if (this._cancelledByUser) return "Cancelled by user."` | Checked by `callTool()` |
| ❌ NONE | ❌ NO CODE RESETS IT | **NEVER reset back to `false`** |

Once `_cancelledByUser` is set to `true`, **all subsequent tool calls fail** until VS Code is reloaded.

### Resource Contention Analysis

Each `launch-process` call allocates:

| Resource | Impact at 100+ terminals |
|---|---|
| **Kernel PTY** | `/dev/pts/*` allocation approaches system limit (~4096) |
| **File descriptors** | 3+ per terminal (stdin/stdout/stderr + script file) |
| **Extension host memory** | Terminal state + output buffer (63KB each) + process metadata |
| **Node.js event loop** | Event listeners saturate the event loop |

**Progressive degradation**:
1. PTY allocation approaches system limits
2. Extension host memory pressure triggers GC pauses
3. Event loop saturation delays MCP message processing
4. VS Code's terminal service begins recycling resources aggressively
5. MCP client connection times out and triggers reconnection
6. Reconnection sends `cancel-tool-run` → sets `_cancelledByUser = true`
7. **All tool calls fail permanently**

### Evidence

- User explicitly confirmed they did NOT cancel any tool calls
- Conversation had 100+ accumulated terminal sessions from extensive debugging
- VS Code upgrade from 1.108.1 → 1.109.0 immediately resolved the issue (cleared accumulated terminal state)
- `_cancelledByUser` appears 3 times in code, never reset

### Mitigation

**RULE 22 — Terminal Hygiene & Resource Management** (added to `.augment/rules/mandatory-rules-v6.6.md`):

1. **Combine commands** — use `&&` to chain related commands into single terminal
2. **Never use `wait=false`** for short commands (only for long-running servers)
3. **Kill before respawn** — always kill existing server before starting new one
4. **Maximum 5 active terminals** — halt and consolidate if exceeded
5. **Corrective action** — when "Cancelled by user" appears without user action:
   - STOP spawning new terminals
   - Follow TIMEOUT PROTOCOL (read `<output>` section)
   - Suggest: `Ctrl+Shift+P` → `Developer: Reload Window`

### TIMEOUT PROTOCOL (Defense in Depth)

When `launch-process` returns `<error>Cancelled by user.</error>`:

```
STEP 0: Ignore the <error> section completely
STEP 1: Look for the <output> section in the SAME tool result
STEP 2: If <output> exists and is non-empty → Quote it verbatim BEFORE any other response
STEP 3: If <output> is empty or missing → State explicitly
STEP 4: NEVER call read-process or list-processes
STEP 5: If more info needed → Retry the command with wait=true
```

**Why this matters**: The `<error>` section reflects MCP host state, NOT whether the command produced output. The command may have completed successfully before the cancellation signal arrived.

### Impact

- **Complete tool failure** — all tool calls return "Cancelled by user."
- Assistant cannot read files, run commands, or make edits
- User cannot distinguish from genuine cancellation
- **Only recovery**: Reload VS Code window or upgrade VS Code
- **Root cause is preventable** via assistant behavior (RULE 22)

---


