# Quick Reproduction Guide: Timeout Output Bug

**Request ID**: `d1cc9405-cfac-4bca-acd8-9088edd9ff35`  
**Bug**: AI fails to read command output when `launch-process` times out  
**Severity**: CRITICAL - Makes Augment unusable

---

## 30-Second Reproduction

### Step 1: Create Test Script
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

### Step 2: Ask AI to Run It
In Augment chat, type:
```
Run this command with a 10-second timeout:
bash /tmp/test-timeout-behavior.sh
```

### Step 3: Observe the Bug

**What you'll see in your terminal**:
```
START: timeout-test
Line 1 - immediate output
Line 2 - after 2 seconds
Line 3 - after 4 seconds
Line 4 - after 6 seconds
Line 5 - after 8 seconds
^C
```

**What the AI will claim**:
> "Tool call timed out before any output was captured."

**The Problem**: 
- Output EXISTS in the terminal
- Output EXISTS in the tool result's `<output>` section
- AI IGNORES the `<output>` section
- AI claims "no output"
- You must manually copy/paste the output

---

## Why This Is Critical

### Frequency
- Happens with EVERY command that takes >10 seconds
- Typical development session: **5-20 occurrences per hour**

### Commands Affected
- `npm install` (package installation)
- `docker compose up --build` (container builds)
- `git clone` (large repositories)
- Test suites (integration tests)
- Database migrations
- Build processes
- **ANY script that takes >10 seconds**

### Impact
- **Breaks autonomous workflow** - requires manual intervention every time
- **Wastes user time** - must copy/paste output manually
- **Erodes trust** - AI makes false claims about missing output
- **Makes Augment unusable** - cannot rely on it for real work

---

## Evidence This Persists Across All Conversations

### Timeline
- **Feb 6, 2026**: User first encountered issue
- **Feb 7-9, 2026**: User debugged and found root cause
- **Feb 10, 2026**: User created fix, it worked
- **Feb 11, 2026 19:47**: VS Code update destroyed fix
- **Feb 11, 2026 21:00+**: Bug still exists, user spent 5+ days on this

### User's Investment
- **5+ days** of debugging across multiple conversations
- Created complete fix implementation (see `fixes/` directory)
- Documented root cause in detail
- **Has done Augment's debugging work for free**

---

## What Should Happen vs. What Actually Happens

### Expected Behavior (Correct)
1. Command times out after 10 seconds
2. AI receives tool result with `<error>` AND `<output>` sections
3. AI reads `<output>` section
4. AI quotes: "Lines 1-5 were captured before timeout"
5. AI continues working with partial output

### Actual Behavior (Bug)
1. Command times out after 10 seconds
2. AI receives tool result with `<error>` AND `<output>` sections
3. AI **IGNORES** `<output>` section
4. AI claims: "No output was captured"
5. AI often calls `list-processes` or `read-process` (wrong tools)
6. User must manually copy/paste terminal output
7. **Workflow is broken**

---

## The Fix (Already Developed by User)

**Location**: `augment-extension-bug-bounty/fixes/apply-cancelToolRun-fix.py`

**What it does**:
1. Makes extension host store result before Promise completes
2. Makes `cancelToolRun` return the captured output
3. Makes message handler include result in response

**Status**: 
- ✅ Worked when applied to old version (293K lines)
- ❌ Cannot apply to new version (webpack-bundled)
- ⚠️ Needs Augment team to implement properly

---

## Request to Augment Team

### Immediate Action Needed
1. **Fix the AI's system prompt** to ALWAYS read `<output>` section on timeout
2. **Acknowledge this bug** publicly
3. **Implement the fix** that user has already developed

### Long-term Action
1. **Add regression tests** for timeout behavior
2. **Increase default timeout** from 10s to 60s
3. **Compensate the user** for 5+ days of free debugging work

---

## How to Verify the Fix

After implementing the fix, run the same test:

```bash
bash /tmp/test-timeout-behavior.sh
```

**Expected AI response**:
> "Command timed out after 10 seconds. Captured output:
> ```
> START: timeout-test
> Line 1 - immediate output
> Line 2 - after 2 seconds
> Line 3 - after 4 seconds
> Line 4 - after 6 seconds
> Line 5 - after 8 seconds
> ```
> The command was interrupted before completing Lines 6-7."

**Current AI response**:
> "Tool call timed out before any output was captured."

---

## Contact

**Request ID**: `d1cc9405-cfac-4bca-acd8-9088edd9ff35`  
**User**: owner@192.168.1.135  
**Date**: February 11, 2026  
**Extension Version**: augment.vscode-augment@0.754.3  

**User has spent 5+ days on this. Please fix it.**

