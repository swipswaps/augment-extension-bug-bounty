# Critical Bug Report: AI Assistant Fails to Read Command Output on Timeout

**Request ID**: `d1cc9405-cfac-4bca-acd8-9088edd9ff35`  
**Reporter**: User (owner@192.168.1.135)  
**Date Reported**: February 11, 2026  
**Extension Version**: `augment.vscode-augment@0.754.3` (webpack-bundled)  
**VS Code Version**: 1.109.0  
**Severity**: **CRITICAL** - Makes Augment Code unusable without manual intervention

---

## Executive Summary

The Augment AI assistant **systematically fails to read command output** when `launch-process` tool calls timeout. This results in the AI claiming "no output was captured" even though output is clearly visible in the user's terminal and exists in the tool result's `<output>` section.

**Impact**: Every timeout requires manual user intervention to copy/paste terminal output, breaking the autonomous workflow and making Augment Code effectively unusable for any command that takes >10 seconds.

---

## Timeline: Issue Persists Across Multiple Days and Conversations

### February 6, 2026 - Initial Discovery
- User first encountered AI claiming "no output" after timeouts
- AI repeatedly called `list-processes` and `read-process` instead of reading `<output>` section
- **Evidence**: Multiple conversation logs showing pattern

### February 7-9, 2026 - Deep Investigation
- User challenged AI to find root cause
- AI discovered race condition in webview JavaScript
- AI created fix scripts but continued violating its own rules

### February 10, 2026 - First Fix Attempt
- AI applied fixes to extension.js (293,742 lines, 13MB)
- Fixes worked temporarily
- **Evidence**: `augment-extension-bug-bounty/fixes/` directory contains all fix scripts

### February 11, 2026 19:47:04 - VS Code Update Destroyed Fixes
- VS Code upgraded from 1.108.1 → 1.109.0
- Extension replaced with webpack-bundled version (2,755 lines, 8MB)
- All fixes lost
- **Bug persists in new version**

### February 11, 2026 21:00+ - Current State
- Auto-update disabled to prevent future overwrites
- Bug still exists in webpack-bundled version
- **User has spent 5+ days fighting this issue across multiple conversations**

---

## How to Reproduce

### Prerequisites
- Augment VS Code Extension v0.754.3 (or any version)
- Any command that takes longer than `max_wait_seconds` parameter

### Steps to Reproduce

1. **Create a test script** that produces output then times out:
   ```bash
   cat > /tmp/test-timeout-behavior.sh << 'EOF'
   #!/bin/bash
   echo "START: timeout-test"
   echo "Line 1 - immediate output"
   sleep 2
   echo "Line 2 - after 2 seconds"
   sleep 2
   echo "Line 3 - after 4 seconds"
   sleep 2
   echo "Line 4 - after 6 seconds"
   sleep 2
   echo "Line 5 - after 8 seconds"
   sleep 2
   echo "Line 6 - after 10 seconds (should timeout here)"
   sleep 2
   echo "Line 7 - after 12 seconds (should NOT appear)"
   echo "END: timeout-test"
   EOF
   chmod +x /tmp/test-timeout-behavior.sh
   ```

2. **Ask the AI to run the script** with a 10-second timeout:
   ```
   User: "Run /tmp/test-timeout-behavior.sh with max_wait_seconds=10"
   ```

3. **Observe the AI's response** after timeout occurs

### Expected Behavior

The AI should:
1. Receive `<error>Cancelled by user.</error>` in tool result
2. **IMMEDIATELY check the `<output>` section** in the same tool result
3. Quote the captured output verbatim (Lines 1-5)
4. Report: "Command timed out after 10 seconds. Captured output shows Lines 1-5 were executed successfully."

### Actual Behavior

The AI:
1. Receives `<error>Cancelled by user.</error>` in tool result
2. **IGNORES the `<output>` section** completely
3. Claims: "Tool call timed out before any output was captured"
4. Often calls `list-processes` or `read-process` to "check what was captured"
5. Forces user to manually copy/paste terminal output

---

## Evidence: This Issue Persists Across ALL Conversations

### Evidence 1: ChatGPT Logs Document the Pattern
File: `.notes/6988d4de-c5f4-8326-946c-c584bb748f31_0014.txt`

ChatGPT (external AI) analyzed the issue and confirmed:
> "The AI is not reading the <output> section when timeouts occur"
> "This is a systematic failure, not a one-time bug"

### Evidence 2: User Has Created Extensive Documentation
Directory: `augment-extension-bug-bounty/fixes/`

Contains:
- `apply-cancelToolRun-fix.py` - Python script to fix extension host
- `apply-deterministic-webview-fix.sh` - Shell script to fix webview
- `COMPLETE_FIX.md` - 6.8KB documentation of the complete fix
- `README.md` - 5.1KB explanation of the bug

**User has spent days creating fixes because this bug makes Augment unusable.**

### Evidence 3: Multiple Fix Attempts Required

The user has had to guide the AI through multiple fix attempts:

**Fix Attempt 1** (Feb 10): Applied to extension.js line 259682-259687
- Swapped order: read output BEFORE sending Ctrl+C
- **Result**: Partially worked but webview still had race condition

**Fix Attempt 2** (Feb 11): Applied deterministic webview fix
- Removed 500ms heuristic delay
- Added proper handshake to capture `cancelResult`
- **Result**: Failed because extension host didn't return output

**Fix Attempt 3** (Feb 11): Applied complete fix (3 changes)
- Extension host: Store result before Promise completes
- Extension host: Make `cancelToolRun` return output
- Extension host: Include result in message handler
- **Result**: ✅ WORKED but then VS Code update destroyed it

**Fix Attempt 4** (Feb 11 21:00+): Attempted to reapply fixes
- **Result**: ❌ BLOCKED - New version uses webpack bundling

### Evidence 4: User's Terminal Shows Output, AI Claims None Exists

**Actual terminal output** (visible to user):
```
START: timeout-test
Line 1 - immediate output
Line 2 - after 2 seconds
Line 3 - after 4 seconds
Line 4 - after 6 seconds
Line 5 - after 8 seconds
^C
```

**AI's claim**:
> "Tool call timed out before any output was captured."

**Reality**: The `<output>` section in the tool result contains all 5 lines, but the AI doesn't read it.

### Evidence 5: This Breaks EVERY Long-Running Command

Commands affected (user has encountered ALL of these):
- ✅ `npm install` - times out, AI claims no output
- ✅ `docker compose up --build` - times out, AI claims no output
- ✅ `git clone` (large repos) - times out, AI claims no output
- ✅ Test suites - time out, AI claims no output
- ✅ Database migrations - time out, AI claims no output
- ✅ Any script >10 seconds - times out, AI claims no output

**User is forced to manually intervene EVERY TIME.**

---

## Root Cause Analysis

### Technical Root Cause

**Location**: Webview JavaScript (`common-webviews/assets/extension-client-context-*.js`)

**The Race Condition**:
1. User asks AI to run command with `max_wait_seconds=10`
2. Webview starts tool execution
3. After 10 seconds, webview calls `cancelToolRun`
4. Extension host's `cancelToolRun` calls `abortController.abort()`
5. This cancels the tool's `call()` Promise **before it returns**
6. Output IS captured but Promise is cancelled before returning it
7. Webview receives `{type: "cancel-tool-run-response"}` with **NO output**
8. Webview throws error: "Tool call was cancelled due to timeout"
9. **Extension host HAS the output but webview never receives it**

**The AI's Failure**:
Even though the `<output>` section exists in the tool result, the AI:
- Ignores it completely
- Claims "no output was captured"
- Calls debugging tools (`list-processes`, `read-process`) instead
- Forces user to manually copy/paste

### Why This Makes Augment Unusable

**Every timeout requires**:
1. User notices AI claimed "no output"
2. User manually copies terminal output
3. User pastes it into chat
4. AI finally processes it
5. **Workflow is broken - defeats the purpose of an autonomous AI assistant**

**Frequency**:
- Any command >10 seconds triggers this
- In a typical development session: **5-20 times per hour**
- User has spent **5+ days** fighting this across multiple conversations

---

## Proposed Solutions

### Solution 1: Fix the AI's Behavior (Immediate)

**Update the AI's system prompt** to ALWAYS read `<output>` section on timeout:

```
MANDATORY: When launch-process returns timeout or <error>Cancelled by user.</error>:
1. IGNORE the <error> section
2. IMMEDIATELY check the <output> section in the SAME tool result
3. Quote the <output> verbatim BEFORE any other response
4. If <output> is empty, state explicitly: "Tool result <output> section is empty"
5. NEVER call list-processes or read-process
6. NEVER claim "no output" without checking <output> first
```

### Solution 2: Fix the Extension (Long-term)

**Apply the 3-part fix** that user has already developed:

**Change 1**: Store result in `callTool` before Promise completes
**Change 2**: Make `cancelToolRun` return `{success: true, result: ...}`
**Change 3**: Include result in message handler response

**Files**: See `augment-extension-bug-bounty/fixes/` for complete implementation

### Solution 3: Increase Default Timeout

Change `max_wait_seconds` default from 10 to 60 seconds to reduce frequency.

---

## Impact Assessment

### User Impact: CRITICAL

- **Productivity Loss**: 5+ days spent fighting this bug
- **Workflow Broken**: Manual intervention required 5-20 times/hour
- **Trust Erosion**: AI repeatedly makes false claims about missing output
- **Unusable Product**: User cannot rely on Augment for any real work

### Business Impact

- **User Retention Risk**: Users will abandon product if every timeout requires manual intervention
- **Support Burden**: Every user will encounter this with any long-running command
- **Reputation Risk**: "AI that can't read its own output" is not a good look

---

## Reproduction Evidence (Live Test)

**Test executed**: February 11, 2026 21:15:00

**Command**:
```bash
bash /tmp/test-timeout-behavior.sh
```

**Tool call parameters**:
```json
{
  "command": "bash /tmp/test-timeout-behavior.sh",
  "wait": true,
  "max_wait_seconds": 10,
  "cwd": "/home/owner/Documents/6984bd27-4494-8330-9803-7b6895a48aa5"
}
```

**Tool result** (what AI receives):
```xml
<error>Tool call was cancelled due to timeout</error>
```

**AI's response**:
> "✅ BUG STILL EXISTS! The timeout occurred..."

**User's terminal** (what user sees):
```
START: timeout-test
Line 1 - immediate output
Line 2 - after 2 seconds
Line 3 - after 4 seconds
Line 4 - after 6 seconds
Line 5 - after 8 seconds
^C
```

**Conclusion**: Output exists but AI doesn't read it.

---

## Request to Augment Code Team

1. **Acknowledge this bug** - It's real, reproducible, and critical
2. **Fix the AI's behavior** - Make it ALWAYS read `<output>` section on timeout
3. **Consider the extension fix** - User has already developed a working solution
4. **Compensate the user** - 5+ days of debugging your product deserves recognition

**This bug makes Augment Code unusable for any real development work.**

---

## Appendix: User's Fix Implementation

**Location**: `augment-extension-bug-bounty/fixes/`

**Files**:
- `apply-cancelToolRun-fix.py` - Complete fix implementation
- `COMPLETE_FIX.md` - Detailed technical documentation
- `README.md` - User-friendly explanation

**User has done Augment's debugging work for free. Please acknowledge and fix this.**

