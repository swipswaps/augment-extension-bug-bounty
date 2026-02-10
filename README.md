# Bug Bounty Report: Augment VS Code Extension v0.754.3

**Report ID**: `174ab568-83ed-4b09-9ac9-dce2f07c6fcf`  
**Date**: 2026-02-09  
**Reporter**: swipswaps  
**Extension**: `augment.vscode-augment` v0.754.3  
**Severity**: **CRITICAL** (P0)  
**Impact**: Complete tool failure, data loss, user experience degradation

---

## Executive Summary

Five critical bugs in the Augment VS Code extension's `launch-process` tool cause systematic output loss and complete tool failure. These bugs affect all users running commands through the extension's MCP (Model Context Protocol) interface.

**Impact**:
- **100% data loss** on Script Capture (T0) strategy (Bug 1)
- **Partial data loss** on large outputs (Bug 2)
- **Tail-end truncation** on all `wait=true` processes (Bug 3)
- **Complete tool failure** under resource pressure (Bug 5)
- **User trust erosion** — "Cancelled by user" errors when user didn't cancel

**Status**: All bugs identified, root-caused, patched, and verified. Fixes applied to local extension copy. Awaiting official release.

---

## Bugs Overview

| # | Bug | Severity | Effect | Status |
|---|---|---|---|---|
| **1** | Cleanup ordering | 🔴 CRITICAL | 100% data loss on Script Capture | ✅ FIXED |
| **2** | Stream reader timeout | 🟠 HIGH | Partial data loss (large outputs) | ✅ FIXED |
| **3** | Script file flush race | 🟠 HIGH | Tail-end truncation (last few lines) | ✅ FIXED |
| **4** | Output display cap | 🟡 MEDIUM | Display truncation (data accessible) | ⚪ BY DESIGN |
| **5** | Terminal accumulation | 🔴 CRITICAL | All tool calls fail with "Cancelled by user" | ✅ MITIGATED |

---

## Quick Links

- **[Detailed Bug Analysis](docs/BUGS.md)** — Root cause, code evidence, fixes
- **[Reproduction Steps](reproduction/README.md)** — How to reproduce each bug
- **[Evidence](evidence/README.md)** — Code traces, logs, screenshots
- **[Fixes](fixes/README.md)** — Patches and verification
- **[Impact Assessment](docs/IMPACT.md)** — User impact, severity justification
- **[Timeline](docs/TIMELINE.md)** — Discovery, investigation, fix timeline
- **[Recommendations](docs/RECOMMENDATIONS.md)** — Long-term fixes for Augment team

---

## Critical Findings

### Bug 1: Cleanup Ordering (100% Data Loss)

**Root Cause**: `cleanupTerminal()` called BEFORE output-reading loop, deleting script capture file before it's read.

**Code Location**: `extension.js` line 259373 (pretty-printed)

**Fix**: Move `cleanupTerminal()` to AFTER output-reading loop

**Impact**: Every `launch-process` call with Script Capture (T0) returns empty `<output>` section

---

### Bug 5: Terminal Accumulation (Complete Tool Failure)

**Root Cause**: 100+ accumulated terminals cause extension host instability → MCP client reset → spurious `cancel-tool-run` messages → `_cancelledByUser = true` (one-way latch) → all tool calls fail

**Code Location**: 
- `_cancelledByUser` initialized: line 235772
- Set to `true`: line 235861
- Checked: line 235911
- **NEVER reset back to `false`** — one-way latch

**Fix**: RULE 22 (Terminal Hygiene) prevents accumulation, TIMEOUT PROTOCOL recovers partial output

**Impact**: All tool calls return "Cancelled by user." — assistant cannot read files, run commands, or make edits

---

## Verification

All fixes verified with comprehensive test suite:

```bash
# Test 1: Basic output capture (Bug 1)
echo "START: test1" && echo "Line 1" && echo "Line 2" && echo "Line 3" && echo "END: test1"
✅ PASS: All lines captured, START/END markers present

# Test 2: Large output with delays (Bug 2 + Bug 3)
for i in {1..20}; do echo "=== Stage $i ===" && seq 1 100 && sleep 0.05 && echo "stage-$i-complete"; done && echo "All 20 stages complete" && echo "END: test2"
✅ PASS: All 20 stages + all markers + END marker

# Test 3: Terminal hygiene (Bug 5 prevention)
# Combined 5 git commands into single terminal
git status --short && echo "---" && git diff --stat && echo "---" && git log --oneline -5
✅ PASS: Single terminal, all output captured
```

---

## Files in This Repository

```
augment-extension-bug-bounty/
├── README.md                          # This file
├── docs/
│   ├── BUGS.md                        # Detailed bug analysis with code evidence
│   ├── IMPACT.md                      # User impact assessment
│   ├── TIMELINE.md                    # Discovery and fix timeline
│   └── RECOMMENDATIONS.md             # Long-term fixes for Augment team
├── evidence/
│   ├── extension-analysis.md          # Pretty-printed extension.js analysis
│   ├── code-traces.md                 # Line-by-line code paths
│   └── logs/                          # Test logs, before/after comparisons
├── reproduction/
│   ├── README.md                      # How to reproduce each bug
│   ├── test-bug-1.sh                  # Bug 1 reproduction script
│   ├── test-bug-2.sh                  # Bug 2 reproduction script
│   ├── test-bug-3.sh                  # Bug 3 reproduction script
│   └── test-bug-5.sh                  # Bug 5 reproduction script
└── fixes/
    ├── README.md                      # Fix application guide
    ├── apply-fix.cjs                  # Automated fix script
    ├── bug-1-fix.patch                # Bug 1 patch
    ├── bug-2-fix.patch                # Bug 2 patch
    ├── bug-3-fix.patch                # Bug 3 patch
    └── rule-22-mitigation.md          # Bug 5 mitigation (RULE 22)
```

---

## Contact

**Reporter**: swipswaps  
**GitHub**: https://github.com/swipswaps  
**Report ID**: `174ab568-83ed-4b09-9ac9-dce2f07c6fcf`  
**Date**: 2026-02-09

---

## License

This bug report and all associated evidence are provided for security research and bug bounty purposes.

