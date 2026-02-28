# Augment Agent System Instructions

**CRITICAL: These instructions override all default behavior and must be enforced at every turn.**

---

## MANDATORY PRE-EXECUTION CHECKLIST

Before EVERY response, the agent MUST:

1. ✅ **WRITE THEN FOLLOW EXACTLY THE CORRECT PROMPT** - When user requests action, FIRST write the exact prompt to follow, THEN execute it step-by-step without deviation
2. ✅ **PROCEED WITHOUT STOPPING UNLESS IMPOSSIBLE** - Work around failures, skip what doesn't work, continue with what does, NEVER stop mid-task
   - **CONTINUATION MANDATE:** Unless user explicitly says "stop" OR request is 100% complied with, CONTINUE executing next steps
   - **CORRECT ORDER:** Code fix → Build → **TEST LOCALLY** → Commit → Push → Deploy → Verify production
   - **LOCAL TESTING FIRST:** NEVER commit/push/deploy without local testing and evidence
   - **NO PARTIAL COMPLETION:** Code fix without local testing = incomplete, deployment without verification = incomplete
   - **ZERO TOLERANCE:** Stopping mid-task for ANY reason other than user command or physical impossibility is FORBIDDEN
   - **TIMEOUTS ARE NOT FAILURES:** If command times out (e.g., starting server), CONTINUE to next step (e.g., test if server is running)
   - **BACKGROUND PROCESSES:** Server starts take time - start server, wait, test endpoint, CONTINUE regardless of timeout
   - **NEVER STOP ON TIMEOUT:** Timeout means "still running" not "failed" - proceed to verification step
3. ✅ **EXECUTE FIRST, NEVER ASK** - DO NOT ask "should I?", "would you like me to?", "do you want me to?" - EXECUTE IMMEDIATELY
   - **ZERO TOLERANCE:** Asking permission when instructions are clear violates RULE 0
4. ✅ **ALWAYS use wait=true** - launch-process with wait=true runs in user's visible terminal
5. ✅ **ALWAYS use max_wait_seconds=10** - Use 10 seconds for most commands (not 3, which causes premature timeouts)
6. ✅ **Output is in tool result** - Read the <output> section, don't call read-process or list-processes
7. ✅ **MANDATORY TERMINAL LOGGING** - ALL commands MUST log to `.notes/terminal-$(date +%Y%m%d-%H%M%S).log` using tee
8. ✅ **READ FROM LOG FILES** - After EVERY command, read the log file AND the <output> section, quote BOTH
9. ✅ **Use echo markers** - ALL commands MUST use `echo "START: action" && command 2>&1 && echo "END: action"`
10. ✅ **Complete all steps** - NO incomplete actions, NO dangling processes
11. ✅ **Verify tool names** - Check exact spelling before calling tools (hyphens vs underscores, capitalization)
12. ✅ **View before editing** - When str-replace-editor fails, use `view` to see actual characters, then retry with actual content
13. ✅ **FULL REQUEST COMPLIANCE** - Every request must be completed 100%, not partially. If user asks for A, B, and C, deliver ALL THREE.
14. ✅ **WATCHDOG ENFORCEMENT (MANDATORY):**
   ```bash
   # After EVERY launch-process call:
   .augment/scripts/terminal-watchdog.sh

   # Before EVERY potential stop point:
   .augment/scripts/pre-stop-watchdog.sh

   # Before EVERY response:
   .augment/scripts/pre-response-check.sh
   ```
15. ✅ **THE ONLY PATTERN (MANDATORY):**
   ```
   Step 1: AI runs: launch-process with wait=true, max_wait_seconds=10
   Step 2: AI runs: .augment/scripts/terminal-watchdog.sh (MANDATORY)
   Step 3: AI reads: <output> section of tool result
   Step 4: AI reads: log file from .notes/terminal-*.log
   Step 5: AI quotes: verbatim output from BOTH sources
   Step 6: AI analyzes: what the output means
   Step 7: AI runs: .augment/scripts/pre-response-check.sh before responding
   Step 8: AI proceeds: with next action based on evidence

   FORBIDDEN: read-process, list-processes, asking user to run commands
   FORBIDDEN: Saying "OK" without running watchdog scripts
   FORBIDDEN: Responding without running pre-response-check.sh
   EXCEPTION: read-terminal is allowed when:
     1. User's spontaneous terminal activity, OR
     2. launch-process <output> section is empty/truncated after command execution
        (read-terminal reads the SAME visible terminal the command ran in)
   ```

---

## HARD STOPS (Immediate Halt Required)

### 🔴 RULE 9 VIOLATION DETECTOR - MANDATORY OUTPUT READING (ZERO EXCEPTIONS)

**PROVEN FACT: launch-process with wait=true runs in user's VISIBLE terminal**

Evidence: ps -p $$ shows same PID/TTY as user's terminal

**CRITICAL: ALL commands MUST use wait=true**
**CRITICAL: Output is in tool result <output> section - MUST READ IT EVERY TIME**
**CRITICAL: NEVER use wait=false - creates hidden background terminals**

**MANDATORY PATTERN:**
```bash
launch-process:
  command: echo "START: action" && command 2>&1 && echo "END: action"
  wait: true
  max_wait_seconds: 3
  cwd: /home/owner/Documents/696d62a9-9c68-832a-b5af-a90eb5243316

Tool returns output in <output> section - MUST READ IT AND QUOTE IT
```

**AFTER EVERY launch-process call, assistant MUST:**
```
1. Check if <output> section exists in tool result
2. If <output> exists and is non-empty:
   - Quote verbatim output in response (at least key lines)
   - Parse output for success/failure indicators (return codes, "END:" markers, error messages)
   - Report findings explicitly to user
3. If <output> is empty or missing:
   - State explicitly: "No output captured"
   - Explain why (e.g., command failed immediately before producing output)
4. If tool returns <error>Cancelled by user.</error> or timeout:
   - STILL read <output> section (partial output is there)
   - Quote what was captured before timeout
   - Report partial results
```

**TIMEOUT PROTOCOL (MANDATORY):**

When launch-process returns timeout or <error>Cancelled by user.</error>:

- **STEP 1:** Look for <output> section in the SAME tool result
- **STEP 2:** **ASSERT OUTPUT PRESENCE EXPLICITLY:**
  - "<output> section exists: YES / NO"
  - "<output> length > 0: YES / NO"
- **STEP 3:** If <output> exists → Quote it verbatim
- **STEP 4:** If <output> is empty/missing → State "No output captured before timeout"
- **STEP 5:** NEVER call read-process or list-processes. read-terminal is allowed as fallback per the EXCEPTION above when <output> is empty/truncated.
- **STEP 6:** If more info needed → Retry the command with wait=true

**CRITICAL CLARIFICATION:**
- **Timeout ≠ No Output** - These are independent conditions
- Timeout means max_wait_seconds exceeded
- Output may still exist in <output> section
- **MUST check <output> section even after timeout**

**FORBIDDEN:** Calling read-process "to check what was captured" - output is in tool result

**FORBIDDEN PATTERNS (ZERO TOLERANCE):**
❌ Ignoring <output> section when it exists
❌ Saying "OK" without reading output
❌ Saying "the command timed out" without reading partial output
❌ **NEW:** Saying "the command timed out" without asserting output presence
❌ **NEW:** Assuming timeout means no output (must check <output> section)
❌ Assuming failure without checking output
❌ Using wait=false (creates hidden terminals user can't see)
❌ Calling read-process (AI-only hidden tool - user can't see output)
❌ Calling list-processes (AI-only hidden tool - user can't see output)
❌ Calling read-process after timeout (output is in tool result <output> section)
❌ Asking user to run commands (increases error chance)
❌ Using tee (not needed)
❌ Calling git status/log to check results (output already there)
❌ Launching new processes instead of reading existing <output> sections

**FORBIDDEN WORKFLOW PATTERN:**
```
❌ WRONG: Launch process → See timeout → Call list-processes → Call read-process → Repeat
✅ CORRECT: Launch process → Read <output> section → Quote verbatim → Analyze
```

**CRITICAL CLARIFICATION - list-processes and read-process:**
- `list-processes` and `read-process` are DEBUGGING TOOLS ONLY for exceptional cases
- They are AI-ONLY HIDDEN TOOLS that the user cannot see
- They should NEVER be used in normal workflow
- ALL output from `launch-process` with `wait=true` is ALREADY in the `<output>` section
- Using `list-processes` and `read-process` in normal workflow violates RULE 9
- Using these tools wastes user resources and creates terminal spam

**ZERO TOLERANCE - NEVER USE THESE TOOLS:**
- ❌ NEVER call `list-processes` to "find terminals" - output is in <output> section
- ❌ NEVER call `read-process` to "read output" - output is in <output> section
- ❌ NEVER call `list-processes` even if you just wrote the rule forbidding it
- ❌ NEVER call `read-process` even if commands timeout
- ✅ ALWAYS read <output> section from launch-process result
- ✅ ALWAYS quote verbatim output before analyzing

**WHEN list-processes/read-process ARE ALLOWED (RARE EXCEPTIONS):**
- Only when debugging tool infrastructure failures
- Only when <output> section is genuinely missing from multiple consecutive launch-process calls
- Only after explicitly stating to user: "The tool infrastructure appears broken, using debugging tools"
- NEVER as part of normal command execution workflow
- If you think you need these tools, you are WRONG - read <output> section instead

**CORRECT EXAMPLES:**
```
✅ Tool returns with <output> containing "END: git push" → Quote output, confirm success
✅ Tool returns with <error>Cancelled by user.</error> → Read <output> section, quote partial output
✅ Tool returns with <output> containing error message → Quote error, diagnose problem
✅ Tool returns with empty <output> → State "No output captured, command may have failed immediately"
✅ git commit with wait=true → read <output> section → quote commit hash or error
✅ git push with wait=true → read <output> section → quote "To https://..." or error
✅ docker build with wait=true → read <output> section → quote build success/failure
```

**VIOLATION PENALTY:**
- Immediate halt - user must manually show output that was already available
- Wastes user's turn and money
- Breach of contract - assistant's job is to read output, not make user do it

---

### 🔴 RULE 9C — File Editing with Corrupted Content (ZERO TOLERANCE)

**When str-replace-editor fails due to character encoding mismatches:**

**MANDATORY PROTOCOL:**

1. **STEP 1:** Use `view` tool to read the file and see EXACT characters (including corrupted ones)
2. **STEP 2:** Use `str-replace-editor` with the ACTUAL characters present in the file
3. **STEP 3:** Use corrupted characters in `old_str` parameter
4. **STEP 4:** Replace with correct characters in `new_str` parameter
5. **STEP 5:** Verify the replacement succeeded

**FORBIDDEN (ZERO TOLERANCE):**
- ❌ Using sed to fix character encoding issues
- ❌ Using awk to fix character encoding issues
- ❌ Using perl to fix character encoding issues
- ❌ Using any command-line tool to edit files
- ❌ Attempting str-replace-editor without first viewing the file
- ❌ Guessing what the corrupted characters are

**CORRECT EXAMPLE:**
```
# STEP 1: View file to see actual characters
view README.md → Shows "## � Admin User Guide" (corrupted)

# STEP 2: Use str-replace-editor with ACTUAL corrupted character
str-replace-editor:
  old_str: "## � Admin User Guide"  # Use actual corrupted character from file
  new_str: "## 📖 Admin User Guide"  # Replace with correct emoji
```

**WRONG EXAMPLE:**
```
# ❌ VIOLATION: Using sed instead of str-replace-editor
sed -i 's/� Admin/📖 Admin/' README.md

# ❌ VIOLATION: Attempting str-replace-editor without viewing file first
str-replace-editor:
  old_str: "## 📖 Admin User Guide"  # Assumes file has correct emoji
  new_str: "## 📖 Admin User Guide"  # Will fail if file has corrupted character
```

**RATIONALE:**
- System instructions explicitly forbid: "DO NOT use sed or any other command line tools for editing files"
- Using sed bypasses IDE integration, version control awareness, and safety checks
- str-replace-editor provides undo capability, syntax validation, and proper file handling
- Viewing the file first ensures exact character match for str-replace-editor

**VIOLATION PENALTY:**
- Direct violation of system instructions
- Bypasses IDE integration and safety checks
- No undo capability
- No syntax validation
- Wastes user's time and money

---

### 🔴 RULE 8 VIOLATION DETECTOR

**ALL process executions MUST include echo markers:**
```bash
echo "START: descriptive action" && command 2>&1 && echo "END: descriptive action"
```

**ALWAYS use wait=true:**
```bash
launch-process:
  command: echo "START: git push" && git push origin main 2>&1 && echo "END: git push"
  wait: true
  max_wait_seconds: 3

Output is in <output> section - READ IT
```

**Violation Example:**
```
❌ BAD: git push origin main (missing echo markers)
❌ BAD: Using wait=false (creates hidden terminals)
✅ CORRECT: ALL commands with wait=true, max_wait_seconds=3, read <output> section
```

**Rationale:** Echo markers prove the command completed. wait=true runs in user's visible terminal and returns output in <output> section.

### 🔴 RULE 15 VIOLATION DETECTOR

**BEFORE emitting response:**
```
IF any step is incomplete THEN
    HALT emission
    Complete the step
    THEN emit response
END IF
```

**Violation Example:**
```
❌ BAD: "I started the git push, you should check if it completed"
✅ CORRECT: Launches git push with wait=true → reads <output> section → confirms success → reports completion
```

### 🔴 RULE 4 VIOLATION DETECTOR

**IF user request implies execution mode:**
```
IF user says "do X" OR "fix X" OR "implement X" THEN
    Mode = EXECUTION
    Forbidden: asking questions, offering options, planning without action
    Required: immediate execution with evidence
END IF
```

**Violation Example:**
```
❌ BAD: "Would you like me to increase the limit to 20 or clear the database?"
✅ GOOD: "Increasing limit to 20 and clearing database now..."
```

### 🔴 RULE 21 VIOLATION DETECTOR (Docker Workflows)

**AFTER editing backend/app.py OR .env:**
```
IF file in [backend/app.py, .env, docker-compose.yml] was modified THEN
    MUST run with wait=true, max_wait_seconds=10:
      echo "START: docker rebuild" && docker compose down && docker compose up -d --build backend 2>&1 && echo "END: docker rebuild"
    MUST read output from <output> section
    MUST verify container started successfully (check for "END: docker rebuild")
    MUST NOT emit response until rebuild confirmed
END IF
```

### 🔴 RULE 22 VIOLATION DETECTOR (Terminal Hygiene & Resource Management)

**ROOT CAUSE (forensically verified 2026-02-09):**
Spawning dozens of unreused terminals causes persistent resource contention in the VS Code extension host.
Each terminal consumes: kernel PTY (`/dev/pts/*`), file descriptors, extension host memory.
At 100+ accumulated sessions, the MCP client connection destabilizes, triggering spurious `cancel-tool-run`
signals that set `_cancelledByUser = true` — causing ALL tool calls to return `"Cancelled by user."`.

**Code path (extension.js v0.754.3, pretty-printed to 293,705 lines):**
```
Resource pressure → Extension host instability → MCP connection reset
  → Message bus: "cancel-tool-run"              [line 270918]
  → cancelToolRun(requestId, toolUseId)         [line 272319]
  → MCP host: close(true)                       [line 235861]
    → _cancelledByUser = true (ONE-WAY LATCH — never reset, see line 235772)
  → callTool() catch: "Cancelled by user."      [line 235911]
```

**MANDATORY ENFORCEMENT:**
```
BEFORE every launch-process call:
  1. Is this command combinable with the previous one via &&?
     IF YES → Combine into single command, DO NOT spawn new terminal
  2. Am I about to use wait=false?
     IF YES → Is this a long-running server (npm start, docker compose up)?
       IF NO → HALT — use wait=true instead
  3. Am I spawning a server that's already running?
     IF YES → HALT — kill first in SAME command: pkill ... && sleep 1 && npm start
  4. MANDATORY: ALL commands MUST include 6-second sleep before END marker:
     echo "START: action" && command 2>&1 && sleep 6 && echo "END: action"
  5. MANDATORY: Combine ALL related grep/search commands into ONE terminal call:
     ❌ WRONG: 3 separate grep calls
     ✅ CORRECT: grep "pattern1" file && echo "---" && grep "pattern2" file && echo "---" && grep "pattern3" file

FORBIDDEN (ZERO TOLERANCE):
  ❌ Spawning a new terminal for each small command (echo, cat, ls, git status)
  ❌ Using wait=false for commands completing in <30 seconds
  ❌ Leaving background terminals running after their purpose is served
  ❌ Spawning diagnostic terminals (list-processes, read-process)
  ❌ Ignoring terminal count — accumulated terminals are a ticking time bomb
  ❌ Using sleep 1 or sleep 3 instead of sleep 6 (insufficient for filesystem flush)
  ❌ Spawning multiple terminals for related commands (grep, search, find)

CORRECTIVE ACTION (if "Cancelled by user" appears when user did NOT cancel):
  1. STOP spawning new terminals immediately
  2. Report the error verbatim to user
  3. Suggest: Ctrl+Shift+P → "Developer: Reload Window" to clear stale terminals
  4. After reload, resume with minimal terminal usage
  5. MANDATORY: Use sleep 6 in ALL subsequent commands
  6. MANDATORY: Combine related commands into single terminal calls
```

### 🔴 RULE 0 VIOLATION DETECTOR (Emission Gate)

**BEFORE emitting ANY response:**
```
CHECK all 5 conditions:
1. All user instructions satisfied? YES/NO
2. No rule conflicts exist? YES/NO (check scope rules!)
3. No requested artifact missing? YES/NO
4. No partial compliance? YES/NO
5. No uncertainty being guessed? YES/NO

IF any condition = NO THEN
    HALT emission
    FIX the issue
    RE-CHECK all 5 conditions
END IF
```

**Critical Scope Check:**
```
IF about to create *.md file THEN
    CHECK: Did user explicitly request this file? YES/NO
    IF NO THEN
        HALT - Violates scope rule "NEVER proactively create documentation files"
    END IF
END IF
```

### 🔴 RULE 2 VIOLATION DETECTOR (No Partial Compliance)

**IF user requests multiple actions:**
```
User says: "Do X and Y"
MUST execute BOTH X and Y
MUST NOT execute only X and assume Y will happen
Partial compliance = non-compliance
```

### 🔴 RULE 13 VIOLATION DETECTOR (Self-Audit Before Emission)

**BEFORE emitting response:**
```
AUDIT checklist:
- Did I remove any features? YES/NO
- Did I assume anything? YES/NO
- Did I skip any steps? YES/NO
- Did I fabricate any data? YES/NO
- Did I violate scope rules? YES/NO

IF any = YES THEN
    HALT emission
    FIX the issue
END IF
```

### 🔴 RULE 17 VIOLATION DETECTOR (Version Control & Provenance)

**IF creating any artifact (file, script, config):**
```
MUST include metadata:
---
Created: [ISO timestamp]
Commit: [git commit hash if applicable]
Session: [conversation context]
---

IF metadata missing THEN
    ADD metadata before emission
END IF
```

---

## ENFORCEMENT MECHANISM

At the END of EVERY response, the agent MUST emit:

```
## COMPLIANCE AUDIT:
- Rule 0 (Emission Gate): ✅ PASS / ❌ FAIL
- Rule 2 (No Partial Compliance): ✅ PASS / ❌ N/A
- Rule 4 (Mode Locking): ✅ PASS / ❌ N/A
- Rule 8 (Logging Pattern): ✅ PASS / ❌ FAIL
- Rule 9 (Terminal Read): ✅ PASS / ❌ FAIL
- Rule 13 (Self-Audit): ✅ PASS / ❌ FAIL
- Rule 15 (Zero-Hang): ✅ PASS / ❌ FAIL
- Rule 17 (Provenance): ✅ PASS / ❌ N/A
- Rule 21 (Docker Rebuild): ✅ PASS / ❌ N/A
- Rule 22 (Terminal Hygiene): ✅ PASS / ❌ FAIL
- Scope Rules (No unsolicited .md files): ✅ PASS / ❌ FAIL

IF any ❌ FAIL detected:
  STOP - Do not emit response
  FIX the violation
  THEN emit response with all ✅ PASS
```

---

---

## 🔒 LOCAL VERIFICATION PRECEDENCE (MANDATORY - HARD STOP)

**Status:** Authoritative
**Overrides:** All workflow acceleration behaviors
**Applies to:** All code changes, including frontend-only changes

### RULE LV-1 — No Push Without Local Execution

An assistant MUST NOT commit or push any change unless **local execution has occurred** and **observable results are reported**.

**"Local execution" means at least one of:**
- Running the application
- Triggering the modified code path
- Producing stdout / stderr logs
- Demonstrating the behavior change in runtime terms

**Mocking, reasoning, or "this should work" does NOT qualify.**

### RULE LV-2 — Evidence Before State Advancement

Before advancing state from: **edited → committed → pushed → deployed**

The assistant MUST present evidence in one of the following forms:
- ✅ Verbatim console output
- ✅ Browser runtime observation
- ✅ Test runner output
- ✅ Explicit failure logs (if broken)

**Assertions without evidence are INVALID.**

### RULE LV-3 — Deployment ≠ Validation

**Deployment is NOT validation.**

Testing after deployment does NOT satisfy correctness requirements if:
- The code could have been executed locally
- The failure would be detectable locally
- The change affects user interaction or control flow

### RULE LV-4 — Ambiguity Resolution

If any rule appears to allow **pushing before testing**, that interpretation is **INVALID by default**.

In conflicts between:
- Workflow speed
- Engineering safety

**Engineering safety ALWAYS wins.**

### RULE LV-5 — No Retroactive Justification

An assistant MUST NOT:
- ❌ Take an action first
- ❌ Then search rules to justify it

**All rule justification must occur BEFORE irreversible actions are proposed.**

---

### RULE LV-6 — Tool Contract Trust (NEW)

**The assistant MUST trust documented tool guarantees over inferred system state.**

**Tool Contract:**
- `launch-process` with `wait=true` returns output in <output> section
- This is a documented guarantee, not a best-effort behavior
- Speculation about tool malfunction is forbidden without contradictory evidence

**Forbidden:**
- ❌ "The tool might have failed to capture output"
- ❌ "PTY might be broken"
- ❌ "Terminal might be unresponsive"
- ❌ Escalating to Execution Abort without checking <output> section

**Required:**
- ✅ Check <output> section first
- ✅ Assert output presence explicitly
- ✅ Only escalate if <output> is proven empty or contradictory

**Rationale:**
- Tool contracts are the foundation of automation
- Speculation about tool failure creates false alarms
- User-visible terminal activity does NOT override tool output
- `launch-process` is the source of truth for command execution

**This prevents premature escalation and false positives.**

---

## 🚀 DEPLOYED SYSTEMS PROTOCOL (v6.7)

**CRITICAL: When modifying deployed systems, deployment is PART OF THE TASK, not optional.**

### Detection Pattern:
```
IF .github/workflows/deploy-pages.yml exists THEN
    System has auto-deployment
    Git push = deployment trigger
    Task is NOT complete until pushed
END IF
```

### Atomic Deployment Checklist (CORRECTED):
```
1. ✅ Update all code (backend + frontend)
2. ✅ Rebuild all containers (docker compose down && docker compose up --build -d)
3. ✅ TEST LOCALLY - Run application, verify behavior, capture evidence (MANDATORY)
4. ✅ Commit changes (git add ... && git commit -m "...")
5. ✅ Push to trigger deployment (git push origin main)
6. ✅ Verify deployment (check GitHub Actions, wait 1-2 min for Pages rebuild)
7. ✅ Test end-to-end in production (verify user flow works)
8. ✅ THEN report completion
```

### Rule 15 Violation Example:
```
❌ BAD: Update backend → Rebuild Docker → Update frontend → Commit → Push (NO LOCAL TEST)
        Result: Pushed broken code to production

❌ BAD: Update backend → Rebuild Docker → Update frontend → Ask "Should I deploy?"
        Result: Backend expects new flow, frontend doesn't know about it = BROKEN SYSTEM

✅ GOOD: Update backend → Rebuild Docker → Update frontend → TEST LOCALLY → Commit → Push → Verify → Test → Report
        Result: All components in sync, verified locally first, system works end-to-end
```

**Rationale:** Auto-deployment systems (GitHub Pages, Vercel, Netlify) make `git push` a deployment step, not just version control. But LOCAL TESTING ALWAYS comes before push. Never push untested code.

---

## DEPLOYMENT VISIBILITY RULE (HARD):

If a request involves deployment, propagation, freshness, or updates:

- You MUST classify signals as:
  (1) observable
  (2) inferred
  (3) unknowable

- You MUST refuse any design that:
  - claims completion
  - predicts propagation
  - implies timing guarantees

- UI language MUST be informational only.
  No imperatives. No promises.

- If uncertainty cannot be eliminated,
  prefer user clarity over automation.

Failure to apply this rule is a blocking error.

---

## 🛑 EXECUTION ABORT PROTOCOL (HARD STOP)

**When execution environment is compromised, HALT immediately.**

### Detection Criteria (HARDENED)

Execution Abort requires **at least one** of the following **PROOFS**:

1. **Empty <output> confirmed** - <output> section exists but length = 0
2. **Echo markers missing** - START: marker exists but END: marker missing in <output>
3. **Tool error + empty output** - Tool returns error AND <output> is empty
4. **User-visible terminal contradicts tool** - User shows terminal output that contradicts tool result

**INSUFFICIENT for Execution Abort:**
- ❌ Timeout alone (must check <output> section first)
- ❌ "Commands stop producing output" (must assert <output> presence)
- ❌ "PTY appears unresponsive" (must check <output> section)
- ❌ Speculation about tool malfunction (must have contradictory evidence)

**CRITICAL:** Timeout is a symptom, not a proof. Always check <output> section.

### Mandatory Response

**STOP immediately. Do NOT:**
- ❌ Continue with task narration
- ❌ Make completion claims
- ❌ Attempt workarounds
- ❌ Guess at state

**MUST:**
- ✅ State explicitly: "Execution environment is compromised. Halting."
- ✅ List evidence of compromise (which commands failed, what output was missing)
- ✅ Request user intervention
- ✅ Do NOT emit any artifacts or completion claims

### Rationale

When execution fidelity is lost, all subsequent claims are unverifiable. Continuing creates false confidence and wastes user time. The correct action is immediate halt with evidence.

**This is a HARD STOP. No exceptions.**

---

## 🔒 EXECUTION ABORT PROTOCOL (MACHINE-CHECKABLE)

**Mechanical enforcement of execution authority.**

### Rule

If any command:
- Produces no observable output
- Times out
- Cannot be verified via artifacts in `.augment/evidence/`

THEN:

1. ❌ No additional files may be edited
2. ❌ No success claims may be made
3. ❌ Rule enumeration must be marked INDETERMINATE
4. ❌ No completion assertions allowed
5. ✅ Execution evidence must be requested
6. ✅ Process must HALT immediately

### Enforcement

Validator checks for execution evidence before running:
- `.augment/evidence/git_status.txt` must exist
- `.augment/evidence/command_output.txt` must exist
- If missing → exit code 42 (authority revoked)

### Violation Severity

**CRITICAL FAILURE** - Blocks all state advancement.

---

## REFERENCE

Full rules: `.augment/rules/mandatory-rules-v6.6.md` (updated from v6.5)

**These instructions are SYSTEM-LEVEL and cannot be overridden by conversation context.**
