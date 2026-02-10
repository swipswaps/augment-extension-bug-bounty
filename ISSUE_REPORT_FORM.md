# Augment Code Extension Issue Report Form

**For submission via VS Code: Augment Code Extension → "Report an issue"**

---

## Field 1: Explanation of the time issue was encountered here

**Timeline**: February 7-9, 2026  
**Conversation**: "Reviewing chat logs for LLM compliance"  
**Conversation ID**: `0cd6160c-eed5-4d28-9cbd-a2cadfb5c2a0`  
**Conversation Timespan**: 2026-02-06T21:15:40.770Z to 2026-02-10T01:09:38.617Z

**February 7, 2026 (Initial Discovery)**:
While developing a Firefox Performance Tuner application (full-stack React + Express), I encountered systematic failures with the `launch-process` tool. Commands were executing successfully (visible in VS Code terminal), but the `<output>` section returned by the tool was consistently empty. This affected all command types: build commands (`npm run build`), git operations (`git commit`, `git push`), and simple test commands (`echo "test"`).

**February 8, 2026 (Bug 1 Discovery)**:
After extensive debugging, I located the extension file (`~/.vscode/extensions/augment.vscode-augment-0.754.3/out/extension.js`), pretty-printed the minified code (8.3 MB → 293,705 lines), and discovered that `cleanupTerminal()` was being called BEFORE the output-reading loop (line 259373), causing 100% data loss on Script Capture (T0) strategy.

**February 8, 2026 (Bug 2 Discovery)**:
After fixing Bug 1, large outputs (20 stages × 100 lines with delays) were still truncating mid-stream. Investigation revealed a 100ms per-chunk timeout in `_readProcessStreamWithTimeout` (line 259968) that was too aggressive for real-world data streams.

**February 9, 2026 (Bug 3 Discovery)**:
With Bugs 1+2 fixed, the last 1-5 lines of output were consistently missing. Testing revealed a race condition where the script capture file was being read immediately after process exit, before the `script` utility flushed its final buffer.

**February 9, 2026 (Bug 5 Discovery)**:
After an extensive debugging session with 100+ accumulated terminal sessions, all tool calls suddenly started failing with "Cancelled by user." errors — despite the user (me) never canceling anything. Investigation revealed that terminal accumulation caused resource pressure, triggering spurious `cancel-tool-run` messages, which set a one-way latch (`_cancelledByUser`) that permanently disabled all tool functionality.

**Impact**: These bugs caused complete workflow breakdown, requiring VS Code window reload and extension upgrade (1.108.1 → 1.109.0) to recover functionality.

---

## Field 2: Steps to reproduce the issue

### Bug 1: Cleanup Ordering (100% Data Loss)

**Prerequisites**: Augment VS Code Extension v0.754.3

**Steps**:
1. Open VS Code with Augment extension
2. Start Augment Agent conversation
3. Ask agent to run: `echo "START: test" && echo "Line 1" && echo "Line 2" && echo "END: test"`
4. Observe tool result `<output>` section

**Expected**: Output contains all lines  
**Actual**: `<output>` section is empty  
**Root Cause**: Script capture file deleted before being read (line 259373)

---

### Bug 2: Stream Reader Timeout (Partial Data Loss)

**Prerequisites**: Bug 1 must be fixed first

**Steps**:
1. Run: `for i in {1..20}; do echo "=== Stage $i ===" && seq 1 100 && sleep 0.05 && echo "stage-$i-complete"; done && echo "All 20 stages complete" && echo "END: test2"`
2. Observe `<output>` section

**Expected**: All 20 stages + END marker  
**Actual**: Only 5-10 stages, truncated mid-stream  
**Root Cause**: 100ms timeout too aggressive (line 259968)

---

### Bug 3: Script File Flush Race (Tail-End Truncation)

**Prerequisites**: Bugs 1+2 must be fixed first

**Steps**:
1. Run same test as Bug 2
2. Observe last few lines

**Expected**: All stages + completion message + END marker  
**Actual**: Last 1-5 lines missing  
**Root Cause**: File read before `script` flushes buffer (lines 259315-259385)

---

### Bug 5: Terminal Accumulation (Complete Tool Failure)

**Prerequisites**: Long conversation session (100+ tool calls)

**Steps**:
1. Execute 100+ commands over several hours
2. Do NOT manually close terminals
3. Attempt any tool call

**Expected**: Tool executes normally  
**Actual**: All tools fail with "Cancelled by user." — user never canceled  
**Root Cause**: Terminal accumulation → `_cancelledByUser` latch (lines 235772, 235861, 235911, 270918)

---

## Additional Information

**Full Bug Report**: https://github.com/swipswaps/augment-extension-bug-bounty  
**Report ID**: `174ab568-83ed-4b09-9ac9-dce2f07c6fcf`  
**Extension Version**: `augment.vscode-augment` v0.754.3  
**Severity**: CRITICAL (P0) — Complete tool failure, data loss

**Bugs Discovered**: 5 (4 bugs + 1 by-design)  
**Fixes Applied**: 3 (Bug 1, 2, 3) — verified locally  
**Mitigations Created**: 1 (Bug 5 - RULE 22 Terminal Hygiene)

**Documentation**:
- Complete bug analysis with code evidence
- Reproduction steps and test scripts
- Impact assessment and timeline
- Recommendations for long-term fixes

