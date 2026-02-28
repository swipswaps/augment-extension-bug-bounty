# Augment VS Code Extension: "Cancelled by user" Error Workaround Guide

**Issue:** All Augment tool calls fail with "Cancelled by user" error, making the extension completely unusable.

**Severity:** Critical - Product is 100% unusable once triggered  
**Frequency:** Occurs every ~60 seconds due to background API timeouts  
**Duration:** Has affected users for many months, worsened after recent updates

---

## How to Recognize the Issue

You'll know you're experiencing this issue when:

1. **All Augment tool calls fail immediately** with "Cancelled by user" error
2. **You didn't cancel anything** - the error appears spontaneously
3. **No commands execute** - file operations, code analysis, database queries all fail
4. **The error persists** across multiple attempts
5. **You may see popup warnings** about runaway zygote processes consuming CPU/RAM

---

## Immediate Workaround (Temporary Relief)

### Step 1: Reload VS Code Window

**Keyboard shortcut:**
- Press `Ctrl+Shift+P` (Windows/Linux) or `Cmd+Shift+P` (Mac)
- Type: `Developer: Reload Window`
- Press Enter

**What this does:**
- Resets the internal `_cancelledByUser` flag back to `false`
- Clears the error state
- Provides temporary relief until the next background API timeout

**How long it lasts:**
- Relief typically lasts 30-60 seconds
- The issue will recur when the next background API timeout occurs

### Step 2: Kill Runaway Zygote Processes (If Applicable)

If you're seeing popup warnings about runaway zygote processes:

```bash
# Find zygote processes
ps aux | grep -E "zygote|PID" | grep -v grep

# Kill specific PIDs (replace with actual PIDs from above)
kill -9 <PID1> <PID2> <PID3>
```

**Example:**
```bash
kill -9 2504479 2504052 2504105
```

---

## Why This Happens

**Root Cause:**
The Augment extension has a bug in its cancellation handling:

1. **Background API requests** to `remote-agents/list-stream` timeout every ~60 seconds
2. **MCP protocol sends cancellation notification** (per specification)
3. **Extension sets `_cancelledByUser = true`** globally
4. **Flag NEVER resets to `false`** - it's a one-way latch
5. **ALL subsequent tool calls fail** with "Cancelled by user" error

**Technical Details:**
- The `_cancelledByUser` flag is global, not request-specific
- The flag is set in the `close(true)` method
- The flag is checked in the `callTool()` catch block
- The flag is NEVER reset in the `finally` block
- This violates the MCP specification's intent that cancellation applies to specific requests

---

## Mitigation Strategies

### Strategy 1: Frequent Window Reloads

**When to use:** If you need to continue working immediately

**Steps:**
1. Keep `Ctrl+Shift+P` → `Developer: Reload Window` ready
2. Reload the window every time the error appears
3. Work quickly during the 30-60 second relief window

**Pros:**
- Immediate relief
- No configuration changes needed

**Cons:**
- Extremely disruptive to workflow
- Must reload every 30-60 seconds
- Loses unsaved work in some cases

### Strategy 2: Disable Augment Extension Temporarily

**When to use:** If the issue makes work impossible

**Steps:**
1. Press `Ctrl+Shift+P` → `Extensions: Disable`
2. Search for "Augment"
3. Select "Augment" extension
4. Work without Augment until fix is available

**Pros:**
- Eliminates the error completely
- Allows you to continue working

**Cons:**
- Loses all Augment functionality
- Must re-enable when fix is available

### Strategy 3: Monitor for Updates

**When to use:** Always

**Steps:**
1. Check for Augment extension updates daily
2. Watch the Augment GitHub repository for announcements
3. Subscribe to Augment's release notes

**Pros:**
- Ensures you get the fix as soon as it's available

**Cons:**
- Requires manual checking
- No immediate relief

---

## Expected Timeline for Fix

**Estimated fix time:** 1 hour (add one line of code + test)  
**Estimated release time:** Unknown - depends on Augment team's release schedule

**The fix is simple:**
```javascript
// In callTool() method, add this line to the finally block:
this._cancelledByUser = false;  // ← ONE LINE FIX
```

---

## How to Report This Issue

If you're experiencing this issue, please report it to the Augment team:

1. **GitHub Issues:** https://github.com/augmentcode/augment (if public repo exists)
2. **Augment Support:** support@augmentcode.com (or appropriate support channel)
3. **Include this information:**
   - "Cancelled by user" error message
   - Frequency of occurrence (every 30-60 seconds)
   - VS Code version
   - Augment extension version
   - Operating system

**Reference this bug report:** `.notes/AUGMENT-TEAM-CRITICAL-BUG-REPORT.md`

---

## Additional Resources

- **MCP Specification on Cancellation:** https://modelcontextprotocol.io/specification/2025-06-18/basic/utilities/cancellation
- **Root Cause Analysis:** `.notes/cancellation-root-cause-analysis.md`
- **Technical Bug Report:** `.notes/AUGMENT-TEAM-CRITICAL-BUG-REPORT.md`

---

## FAQ

**Q: Why does this happen every 60 seconds?**  
A: Background API requests to `remote-agents/list-stream` timeout every ~60 seconds, triggering the cancellation mechanism.

**Q: Will this be fixed?**  
A: Yes, the fix is simple (one line of code). The Augment team needs to release an update.

**Q: Can I patch the extension myself?**  
A: Technically yes, but it requires modifying the compiled extension.js file, which is not recommended and may break with updates.

**Q: Does this affect everyone?**  
A: This affects all users who experience background API timeouts, which appears to be most users based on the frequency of reports.

**Q: Is my data safe?**  
A: Yes, this is a tool execution bug, not a data corruption bug. Your code and data are safe.

---

**Last Updated:** 2026-02-20  
**Status:** Awaiting fix from Augment team

