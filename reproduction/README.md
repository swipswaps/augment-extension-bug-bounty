# Reproduction Steps

**Report ID**: `174ab568-83ed-4b09-9ac9-dce2f07c6fcf`  
**Extension**: `augment.vscode-augment` v0.754.3

---

## Prerequisites

1. **Augment VS Code Extension** v0.754.3 installed
2. **VS Code** 1.108.1 or later
3. **Linux/macOS/Windows** with bash shell
4. **Augment Agent** active in VS Code

---

## Bug 1: Cleanup Ordering (100% Data Loss)

### Reproduction Steps

1. Open VS Code with Augment extension
2. Start Augment Agent conversation
3. Ask agent to run: `echo "START: test1" && echo "Line 1" && echo "Line 2" && echo "Line 3" && echo "END: test1"`
4. Observe the `<output>` section in the tool result

### Expected Result (with fix)

```
<output>
START: test1
Line 1
Line 2
Line 3
END: test1
</output>
```

### Actual Result (without fix)

```
<output>
</output>
```

**Explanation**: `cleanupTerminal()` deletes the script capture file before it's read, causing 100% data loss.

---

## Bug 2: Stream Reader Timeout (Partial Data Loss)

### Reproduction Steps

1. Open VS Code with Augment extension
2. Start Augment Agent conversation
3. Ask agent to run the test script: `bash test-bug-2.sh`
4. Observe how many stages are captured in the `<output>` section

### Test Script (`test-bug-2.sh`)

```bash
#!/usr/bin/env bash
for i in {1..20}; do
  echo "=== Stage $i ==="
  seq 1 100
  sleep 0.05
  echo "stage-$i-complete"
done
echo "All 20 stages complete"
echo "END: test2"
```

### Expected Result (with fix)

```
<output>
=== Stage 1 ===
1
2
...
100
stage-1-complete
...
=== Stage 20 ===
1
2
...
100
stage-20-complete
All 20 stages complete
END: test2
</output>
```

### Actual Result (without fix, 100ms timeout)

```
<output>
=== Stage 1 ===
...
=== Stage 5 ===
# ← STOPS HERE (5/20 stages)
# NO END MARKER
</output>
```

**Explanation**: 100ms per-chunk timeout is too aggressive. Reader abandons mid-stream when chunks are delayed by >100ms.

---

## Bug 3: Script File Flush Race (Tail-End Truncation)

### Reproduction Steps

1. Apply Bug 1 and Bug 2 fixes first (otherwise this bug is masked)
2. Open VS Code with Augment extension
3. Start Augment Agent conversation
4. Ask agent to run the test script: `bash test-bug-2.sh` (same as Bug 2)
5. Observe if the last few lines are present

### Expected Result (with fix)

```
<output>
...
stage-20-complete
All 20 stages complete  # ← THESE LINES PRESENT
END: test2              # ← END MARKER PRESENT
</output>
```

### Actual Result (without fix, with Bug 1+2 fixed)

```
<output>
...
stage-20-complete
# ❌ MISSING: "All 20 stages complete"
# ❌ MISSING: "END: test2"
</output>
```

**Explanation**: Script file is read before `script` utility flushes its final buffer. Last 1-5 lines consistently missing.

**Verification**: Adding `sleep 0.5` before the END marker makes the test pass, confirming it's a flush timing issue.

---

## Bug 4: Output Display Cap (Not a Bug)

### Reproduction Steps

1. Open VS Code with Augment extension
2. Start Augment Agent conversation
3. Ask agent to run: `seq 1 1000` (generates ~4000 bytes, but test with larger for >63 KB)
4. Observe the `<output>` section

### Expected Result

```
<output>
1
2
...
850  # ← TRUNCATED HERE (63 KB reached)

<response clipped>
To view the full content, use the view-range-untruncated tool with reference_id: abc123
</output>
```

### Verification

Use `view-range-untruncated` tool with the Reference ID to access full content:

```
view-range-untruncated(reference_id="abc123", start_line=850, end_line=1000)
→ Lines 850-1000 returned successfully ✅
```

**Explanation**: This is BY DESIGN — 63 KB display limit with full content accessible via separate tool.

---

## Bug 5: Terminal Accumulation (Complete Tool Failure)

### Reproduction Steps

1. Open VS Code with Augment extension
2. Start Augment Agent conversation
3. Run 100+ commands in sequence (use the test script: `bash test-bug-5.sh`)
4. Observe when tool calls start failing with "Cancelled by user." error

### Test Script (`test-bug-5.sh`)

```bash
#!/usr/bin/env bash
# Simulate heavy terminal usage
for i in {1..150}; do
  echo "Command $i"
  sleep 0.1
done
```

### Expected Result (with mitigation)

All 150 commands execute successfully, no "Cancelled by user." errors.

### Actual Result (without mitigation)

After ~100 commands:
```
<error>Cancelled by user.</error>
```

**All subsequent tool calls fail** with the same error, even though user didn't cancel anything.

**Explanation**: 100+ accumulated terminals cause extension host instability → MCP client reset → `_cancelledByUser = true` (one-way latch) → permanent tool failure.

**Recovery**: Reload VS Code window (`Ctrl+Shift+P` → `Developer: Reload Window`)

---

## Verification Checklist

After applying fixes, verify all bugs are resolved:

- [ ] **Bug 1**: Run `echo "START" && echo "Line 1" && echo "END"` → all lines captured
- [ ] **Bug 2**: Run `test-bug-2.sh` → all 20 stages captured
- [ ] **Bug 3**: Run `test-bug-2.sh` → END marker present
- [ ] **Bug 4**: Run `seq 1 1000` → truncation footer shows Reference ID
- [ ] **Bug 5**: Run `test-bug-5.sh` → no "Cancelled by user." errors

---

## Notes

- **Bug 1** must be fixed first — it masks all other bugs
- **Bug 2** must be fixed before Bug 3 is visible
- **Bug 5** requires long session to reproduce — may take 30+ minutes of active use
- All test scripts are provided in this directory


