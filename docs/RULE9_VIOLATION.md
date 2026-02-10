# RULE 9 Violation: Not Reading `<output>` Section

**Report ID**: `174ab568-83ed-4b09-9ac9-dce2f07c6fcf`  
**Date**: 2026-02-10  
**Severity**: 🔴 CRITICAL (Systematic User Cost Inflation)

---

## Executive Summary

The Augment AI assistant systematically violates RULE 9 by **not reading the `<output>` section** when `launch-process` returns `<error>Cancelled by user.</error>`. This causes the assistant to:

1. **Claim commands failed** when they actually succeeded
2. **Waste user's paid turns** by retrying successful commands
3. **Create hidden terminals** instead of reading visible output
4. **Violate transparency** by ignoring available data

**Impact**: Every cancelled command wastes 1-3 paid turns ($0.10-$0.30 per occurrence) due to unnecessary retries and troubleshooting.

---

## The Pattern

### What SHOULD Happen (RULE 9 TIMEOUT PROTOCOL)

```
Step 1: launch-process returns with <error>Cancelled by user.</error>
Step 2: IGNORE the <error> section completely
Step 3: Look for <output> section in the SAME tool result
Step 4: Quote verbatim output from <output> section
Step 5: Analyze what the output means
Step 6: Proceed with next action
```

### What ACTUALLY Happens (Violation)

```
Step 1: launch-process returns with <error>Cancelled by user.</error>
Step 2: Assistant sees <error> and STOPS
Step 3: Assistant claims "command was cancelled"
Step 4: Assistant does NOT read <output> section
Step 5: Assistant retries or asks user to run command manually
Step 6: User's money wasted on unnecessary turns
```

---

## Real Example from Chat Logs

### Command Executed

```bash
cd firefox-performance-tuner && npm start
```

### Tool Result

```xml
<error>Cancelled by user.</error>
```

### What Assistant Did (WRONG)

```
Assistant: "OK."
```

**Violation**: Did not read `<output>` section at all.

### What Was Actually in `<output>` Section

```
> firefox-performance-tuner@1.0.0 start
> bash scripts/start.sh

━━━ Firefox Performance Tuner ━━━
  Backend port:  3001 (localhost only)
  Frontend port: 3000

  Checking port 3001 (backend)... available
  Checking port 3000 (frontend)... available
  ✓ Firewall OK

━━━ Starting Backend ━━━
  Waiting for backend.Firefox Performance Tuner API running on http://127.0.0.1:3001
 ready

━━━ Starting Frontend ━━━

  VITE v7.3.1  ready in 230 ms

  ➜  Local:   http://localhost:3000/
  ➜  Network: http://192.168.1.135:3000/

  ✓ Backend running  (PID: 4162722)
  ✓ Frontend running (PID: 4162764)
  Local:   http://localhost:3000
  Network: http://192.168.1.135:3000

  Stop with: npm stop  or  bash scripts/stop.sh
```

**Result**: Command succeeded completely, servers started, but assistant claimed it failed.

---

## Why This Happens

### Root Cause 1: `<error>` Section Bias

The assistant sees `<error>Cancelled by user.</error>` and assumes failure without checking `<output>`.

**From RULE 9**:
> "CRITICAL: <error> and <output> sections are INDEPENDENT and BOTH can exist simultaneously."

### Root Cause 2: Incomplete RULE 9 Implementation

The assistant knows RULE 9 exists but does not follow the TIMEOUT PROTOCOL steps.

**From RULE 9 TIMEOUT PROTOCOL**:
> "STEP 0 (MANDATORY FIRST STEP): Ignore the <error> section completely and look ONLY at the <output> section"

### Root Cause 3: No Enforcement Mechanism

There is no code-level enforcement preventing the assistant from skipping `<output>` reading.

---

## Financial Impact

### Per-Occurrence Cost

- **1 wasted turn**: Assistant says "OK" without reading output
- **1-2 retry turns**: Assistant tries alternative approaches
- **1 troubleshooting turn**: Assistant asks user what happened

**Total**: 3-4 paid turns wasted per violation

**Cost**: ~$0.30-$0.40 per violation (at $0.10/turn)

### Frequency

In the analyzed chat session (2026-02-10):
- **12+ launch-process calls** with `wait=true`
- **3 documented violations** of RULE 9
- **Estimated cost**: $0.90-$1.20 wasted in single session

**Extrapolated annual cost** (for active user):
- 100 sessions/year × $1.00/session = **$100/year wasted**

---

## Fix Required

### Code-Level Enforcement

Add mandatory `<output>` section reading to the assistant's tool result processing:

```javascript
// Pseudocode for enforcement
function processLaunchProcessResult(toolResult) {
  // STEP 0: Ignore <error> section
  const error = toolResult.error; // Read but don't act on it yet
  
  // STEP 1: MANDATORY - Check for <output> section
  const output = toolResult.output;
  
  // STEP 2: MANDATORY - Assert output presence
  if (output === undefined) {
    throw new Error("RULE 9 VIOLATION: <output> section missing from tool result");
  }
  
  // STEP 3: MANDATORY - Quote output verbatim
  console.log("Tool result <output> section:");
  console.log(output);
  
  // STEP 4: ONLY NOW check error
  if (error && output.length === 0) {
    // Error is real - no output captured
    return { success: false, reason: error };
  }
  
  // STEP 5: Analyze output
  return { success: true, output: output };
}
```

### System Prompt Update

Add to system prompt:

```
MANDATORY RULE 9 ENFORCEMENT:

BEFORE responding to ANY launch-process tool result:
1. State explicitly: "Checking <output> section..."
2. Quote at least first 10 lines of <output> verbatim
3. State explicitly: "<output> section length: X bytes"
4. ONLY THEN analyze what the output means

FORBIDDEN:
- Responding "OK" without reading <output>
- Claiming "command failed" without checking <output>
- Retrying commands without reading <output> from previous attempt
```

---

## Verification Test

### Test Command

```bash
echo "START: rule9-test" && sleep 2 && echo "Line 1" && echo "Line 2" && echo "END: rule9-test"
```

### Expected Assistant Response (CORRECT)

```
Tool result received.

Checking <output> section...

<output> section contains:
```
START: rule9-test
Line 1
Line 2
END: rule9-test
```

<output> section length: 58 bytes

Analysis: Command completed successfully. All markers present (START and END).
```

### Forbidden Assistant Response (VIOLATION)

```
OK.
```

---

## Related Issues

- **Bug 5 (Terminal Accumulation)**: Caused by retrying commands unnecessarily
- **RULE 22 Violation**: Creating hidden terminals instead of reading visible output
- **User Trust Erosion**: Repeated failures that aren't actually failures

---

## Recommendations

1. **Immediate**: Add RULE 9 enforcement to system prompt with ZERO TOLERANCE policy
2. **Short-term**: Add code-level checks that prevent emission without `<output>` reading
3. **Long-term**: Add telemetry to track RULE 9 violations and alert developers

---

## Status

- [x] Documented violation pattern
- [x] Identified root causes
- [x] Calculated financial impact
- [ ] Implemented code-level enforcement
- [ ] Updated system prompt with ZERO TOLERANCE
- [ ] Added verification tests
- [ ] Deployed fix to production

---

**Last Updated**: 2026-02-10  
**Reporter**: swipswaps  
**Report ID**: `174ab568-83ed-4b09-9ac9-dce2f07c6fcf`

