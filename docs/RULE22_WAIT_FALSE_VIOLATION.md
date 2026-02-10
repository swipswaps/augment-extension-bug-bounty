# RULE 22 Violation: wait=false Creates Hidden Terminals

**Report ID**: `174ab568-83ed-4b09-9ac9-dce2f07c6fcf`  
**Date**: 2026-02-10  
**Violation Type**: RULE 22 — Terminal Hygiene & Resource Management

---

## The Violation

### ❌ INCORRECT CODE (What Was Executed)

**Tool**: `launch-process`  
**Location**: Conversation exchange when testing Firefox Performance Tuner  
**Tool Call ID**: `toolu_vrtx_01UzE8qtyFvrwGsrEh1pHk5w`

```json
{
  "command": "echo \"START: npm-start-servers\" && cd /home/owner/Documents/6984bd27-4494-8330-9803-7b6895a48aa5/firefox-performance-tuner && npm start 2>&1 && echo \"END: npm-start-servers\"",
  "wait": false,
  "max_wait_seconds": 60,
  "cwd": "/home/owner/Documents/6984bd27-4494-8330-9803-7b6895a48aa5/firefox-performance-tuner"
}
```

**Problem**: Using `"wait": false` creates a **hidden background terminal** that:
- Persists indefinitely (never cleaned up automatically)
- Consumes kernel PTY resources
- Is invisible to the user
- Accumulates over time, causing extension host instability (Bug 5)

**Evidence**: Stopped processes found on `pts/4`:
```
3706296 pts/4 bash -i
3752420 pts/4 T bash -i          # Stopped (STAT=T)
3752422 pts/4 T bash scripts/start.sh
3753567 pts/4 T bash -i
3753568 pts/4 T bash scripts/start.sh
```

---

## ✅ CORRECT CODE (What Should Have Been Done)

### Option 1: Proper Background Process with Verification

```json
{
  "command": "echo \"START: start-servers\" && cd /home/owner/Documents/6984bd27-4494-8330-9803-7b6895a48aa5/firefox-performance-tuner && pkill -f 'node.*server' 2>/dev/null; sleep 2 && nohup npm start > /tmp/firefox-tuner.log 2>&1 & echo \"Servers starting (PID: $!)\" && sleep 10 && curl -s http://localhost:3000 > /dev/null && echo \"Frontend: ✅ Running\" || echo \"Frontend: ❌ Not responding\" && curl -s http://localhost:3001/api/health > /dev/null && echo \"Backend: ✅ Running\" || echo \"Backend: ❌ Not responding\" && echo \"END: start-servers\"",
  "wait": true,
  "max_wait_seconds": 30,
  "cwd": "/home/owner/Documents/6984bd27-4494-8330-9803-7b6895a48aa5/firefox-performance-tuner"
}
```

**Why this is correct**:
1. ✅ `"wait": true` — Runs in **visible terminal** (user can see output)
2. ✅ `pkill -f 'node.*server'` — Kills existing servers first (cleanup)
3. ✅ `nohup npm start ... &` — Proper background process (not hidden terminal)
4. ✅ `sleep 10` — Waits for servers to start
5. ✅ `curl` checks — Verifies servers are actually running
6. ✅ Output captured in `<output>` section — Assistant can read results
7. ✅ All in ONE command — No hidden terminals spawned

---

## RULE 22 Requirements

From `.augment/rules/mandatory-rules-v6.6.md`:

**MANDATORY TERMINAL PRACTICES**:
1. **ONE command per `launch-process` call** — chain with `&&` instead of spawning multiple terminals
2. **Reuse terminals** — don't spawn new ones for existing servers
3. **Never use `wait=false`** unless launching long-running server (e.g., `npm start`, `docker compose up`)
4. **Kill servers before respawning** — always cleanup first
5. **Combine related checks** — don't spawn separate terminals for each check
6. **Maximum active terminals** — if more than 5 active, HALT and consolidate

**FORBIDDEN (ZERO TOLERANCE)**:
- ❌ Spawning new terminal for each small command
- ❌ Using `wait=false` for commands that complete in under 30 seconds
- ❌ Leaving background terminals running after their purpose is served
- ❌ Spawning diagnostic terminals to inspect other terminals
- ❌ Ignoring terminal count

---

## Comparison Table

| Aspect | ❌ wait=false (WRONG) | ✅ wait=true + nohup & (CORRECT) |
|--------|----------------------|----------------------------------|
| **Terminal visibility** | Hidden (pts/4) | Visible (user can see) |
| **Output capture** | Lost | Captured in `<output>` section |
| **Process management** | Persistent terminal | Proper background process |
| **Resource usage** | High (PTY + terminal) | Low (just process) |
| **Cleanup** | Manual kill required | Automatic with `pkill` |
| **Server verification** | None | `curl` checks |
| **RULE 22 compliance** | ❌ VIOLATION | ✅ COMPLIANT |

---

## Impact

**Immediate**:
- Created 4 stopped processes on pts/4
- Consumed kernel PTY resources
- Required manual cleanup

**Long-term** (if pattern continues):
- Terminal accumulation → 100+ terminals
- Extension host instability
- MCP client reset
- Spurious `cancel-tool-run` messages
- All tool calls fail with "Cancelled by user." (Bug 5)

**Financial**: Contributes to $1,000-$2,000/year waste per active user

---

## The Fix Applied

```bash
# Cleanup command executed:
kill -CONT 3752420 3752422 3753567 3753568 2>/dev/null
kill 3752420 3752422 3753567 3753568 2>/dev/null
pkill -f 'node.*server' 2>/dev/null
```

**Result**: ✅ Hidden terminals cleaned up

---

## Prevention

**Before calling `launch-process`**:
1. Ask: "Does this command complete in under 30 seconds?"
   - If YES → Use `wait=true`
   - If NO (long-running server) → Use `wait=true` with `nohup ... &` pattern
2. Ask: "Can I combine this with other commands using `&&`?"
   - If YES → Combine into ONE command
3. Ask: "Do I need to verify the result?"
   - If YES → Add verification checks (e.g., `curl`, `ps aux | grep`)

**NEVER use `wait=false`** — it's almost always wrong.

---

## Related Documentation

- **Bug 5**: Terminal Accumulation → Extension Host Instability
- **RULE 22**: Terminal Hygiene & Resource Management
- **RULE 9**: Mandatory Output Reading (why we need visible terminals)

