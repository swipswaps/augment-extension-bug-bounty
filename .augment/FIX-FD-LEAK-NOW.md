# FIX FD LEAK NOW - Action Plan

**Current Status:**
- FD Count: ~56,000 (threshold: 50,000)
- Runaway Zygotes: 2-3 processes consuming 20%+ CPU
- Root Cause: `getRemoteAgentOverviewsStream` missing cleanup + immediate retry

---

## IMMEDIATE FIX (Do This Now)

### Option 1: Reload VS Code Window (Fastest - 10 seconds)

1. Press `Ctrl+Shift+P`
2. Type: `Developer: Reload Window`
3. Press Enter

**Result:** Clears all leaked FDs, kills runaway zygotes, fresh start

**Downside:** Leak will return within hours

---

### Option 2: Kill Runaway Zygotes (Temporary - 30 seconds)

```bash
# Kill the specific runaway zygote processes
kill -9 968120 972624

# VS Code will respawn them cleanly
```

**Result:** Reduces CPU usage, may reduce FD count slightly

**Downside:** Doesn't fix root cause, FDs still leak

---

### Option 3: Enable Auto-Reload Daemon (Permanent Mitigation)

```bash
# Start the auto-reload daemon
nohup ./.augment/auto-reload-vscode-on-fd-leak.sh &

# It will automatically reload VS Code when FD count exceeds 10,000
```

**Result:** Automatic mitigation, no manual intervention needed

**Downside:** Interrupts work when reload happens

---

## PERMANENT FIX (Requires Augment Team)

The permanent fix requires Augment team to patch the extension source code.

**Bug Report:** `.notes/AUGMENT-TEAM-FINAL-BUG-REPORT-2026-02-24.md`

**Working Fix Code:** `.notes/69935426-075c-8329-b732-ceb8a5e0b600_0116.txt` (lines 1213-2477)

**Six Required Changes:**
1. Single-instance guard (prevent concurrent streams)
2. Guaranteed stream cleanup (iterator.return() + response.body.cancel())
3. Exponential backoff (1s → 30s max)
4. Backend health gate (block webview reload during instability)
5. Hard FD growth guard (stop if >10% growth in 60s)
6. Empty conversation ID gating (prevent supervisor prompt loop)

---

## VERIFICATION

After applying any fix, verify with:

```bash
# Check FD count
lsof 2>/dev/null | grep -c code

# Check runaway zygotes
ps aux | grep -E "code.*zygote" | grep -v grep | awk '{if ($3 > 5.0) print}'

# Monitor for 5 minutes
watch -n 10 "lsof 2>/dev/null | grep -c code"
```

**Success Criteria:**
- FD count < 500
- No runaway zygotes (CPU < 5%)
- FD count stable (no monotonic growth)

---

## RECOMMENDED ACTION RIGHT NOW

**Do this immediately:**

1. **Reload VS Code Window** (`Ctrl+Shift+P` → `Developer: Reload Window`)
2. **Monitor FD count** for 10 minutes to see if leak returns
3. **If leak returns:** Enable auto-reload daemon
4. **Report to Augment team:** Send them the bug report

---

## WHY THIS WORKS

**Reload Window:**
- Kills extensionHost process
- Terminates all active streams
- Closes all leaked file descriptors
- Respawns clean extensionHost

**Auto-Reload Daemon:**
- Monitors FD count every 60 seconds
- Triggers reload when threshold exceeded
- Prevents system instability

**Permanent Fix (Augment Team):**
- Adds proper stream cleanup to `getRemoteAgentOverviewsStream`
- Adds exponential backoff to prevent retry storms
- Prevents positive feedback loop (timeout → retry → leak → faster timeout)

---

## CURRENT FD BREAKDOWN

Based on analysis:
- **Normal:** 200-500 FDs per process
- **Current:** 56,000+ FDs across all code processes
- **Leak Rate:** ~100-200 FDs/minute during active use
- **Time to Critical:** 4-8 hours from clean start

---

**ACTION REQUIRED: Reload VS Code window NOW to clear leaked FDs**

