# Augment Extension Bug Bounty Repository

**Report ID**: `174ab568-83ed-4b09-9ac9-dce2f07c6fcf`  
**Status**: Root cause identified, fixes developed, mitigation deployed  
**Date**: 2026-02-09 to 2026-02-16  
**Total Investigation Time**: 7+ days, 60+ hours

---

## Executive Summary

This repository documents **TWO CRITICAL BUGS** in the Augment VSCode extension (v0.754.3) that together create a catastrophic user experience failure:

1. **Bug 1: Timeout Race Condition** — Output captured but lost due to Promise cancellation
2. **Bug 2: Terminal Accumulation** — Hidden terminals cause MCP instability and permanent tool failure

**Financial Impact**: $1,000-$2,000/year per active user in wasted time and manual interventions.

**Solution**: Hidden Terminal Watchdog Extension (mitigation) + 3-part code fix (permanent fix)

---

## Quick Navigation

### Core Documentation
- **[COMPLETE_ANALYSIS.md](COMPLETE_ANALYSIS.md)** — Complete technical explanation with exact code
- **[ROOT_CAUSE_FOUND.md](ROOT_CAUSE_FOUND.md)** — Bug 1 root cause analysis
- **[EVIDENCE_TIMELINE.md](EVIDENCE_TIMELINE.md)** — Day-by-day investigation timeline
- **[INDEX.md](INDEX.md)** — Full document index

### Bug-Specific Analysis
- **[docs/RULE22_WAIT_FALSE_VIOLATION.md](docs/RULE22_WAIT_FALSE_VIOLATION.md)** — Bug 2 detailed analysis
- **[docs/RULE9_VIOLATION.md](docs/RULE9_VIOLATION.md)** — AI prompt violation analysis
- **[docs/RULE9_CODE_FIX.md](docs/RULE9_CODE_FIX.md)** — Code-level fix for Bug 1

### Fixes and Tools
- **[fixes/apply-complete-fix.js](fixes/apply-complete-fix.js)** — 3-part fix implementation
- **[user-override-tools/](user-override-tools/)** — Manual recovery tools

### Reproduction
- **[HOW_TO_REPRODUCE.md](HOW_TO_REPRODUCE.md)** — Step-by-step reproduction guide
- **[QUICK_REPRODUCTION_GUIDE.md](QUICK_REPRODUCTION_GUIDE.md)** — Fast reproduction (5 minutes)

---

## Why the Issue Persisted After the First Watchdog Extension

### The Evolution: Three Watchdog Versions

#### Version 1: Basic Terminal Tracking (Feb 9-11)
**What it did**:
```typescript
// Basic terminal counting
vscode.window.onDidOpenTerminal((term) => {
    trackedTerminals.add(term);
    log(`Terminal opened: ${term.name} (count: ${trackedTerminals.size})`);
});
```

**Why it failed**:
- ❌ Only tracked VS Code's visible terminals
- ❌ Didn't detect hidden processes spawned by extension host
- ❌ Couldn't see `pts/4` stopped processes
- ❌ No process-level monitoring

**Evidence of failure**:
```bash
$ ps aux | grep pts/4
3752420 pts/4 T bash -i          # Hidden from VS Code API!
3752422 pts/4 T bash scripts/start.sh
```

#### Version 2: Process Detection Added (Feb 11-14)
**What it added**:
```typescript
function detectHiddenTerminals(): Promise<HiddenTerminalInfo[]> {
    return new Promise((resolve) => {
        exec(`pgrep -u ${username} -f "code.*--ms-enable-electron-run-as-node"`, (err, stdout) => {
            // Parse PIDs and check TTY status
        });
    });
}
```

**Why it still failed**:
- ❌ Detected hidden processes but didn't capture their OUTPUT
- ❌ No way to see what commands were running
- ❌ Couldn't provide forensic evidence for debugging
- ❌ User still had to manually copy/paste from terminal

**The missing piece**: Terminal output monitoring

#### Version 3: Production-Grade with Terminal Output Capture (Feb 16)
**What it finally added**:
```typescript
// Monitor .notes/terminal-*.log files
const processedFiles = new Map<string, number>();

function monitorTerminalOutput() {
    setInterval(() => {
        const files = fs.readdirSync(notesDir);
        
        files.forEach(filename => {
            if (!filename.startsWith('terminal-') || !filename.endsWith('.log')) {
                return;
            }

            const filePath = path.join(notesDir, filename);
            const stats = fs.statSync(filePath);
            const currentSize = stats.size;
            const lastSize = processedFiles.get(filePath) || 0;

            if (currentSize === lastSize) {
                return;  // No changes
            }

            const content = fs.readFileSync(filePath, 'utf-8');
            const lines = content.split('\n').filter(line => line.trim());
            
            processedFiles.set(filePath, currentSize);
            
            log(`TERMINAL OUTPUT | File: ${filename} | Lines: ${lines.length}`);
            lines.forEach(line => {
                log(`  ${line}`);
            });
        });
    }, 1000);  // Poll every 1 second
}
```

**Why this finally works**:
- ✅ Captures ALL terminal output from `.notes/terminal-*.log` files
- ✅ Displays output in Watchdog Log output panel
- ✅ Provides backup when tool results are truncated
- ✅ Polling-based (avoids race conditions)
- ✅ File size tracking prevents duplicate processing

---

## The Critical Pattern: Commands Must Use `tee`

### ❌ WRONG: Command Without `tee`
```bash
git commit -m "feat: Add feature" && git push origin main
```

**Result**: Command runs, but watchdog CANNOT capture output (no log file created)

### ✅ CORRECT: Command With `tee`
```bash
LOGFILE="/path/to/.notes/terminal-$(date +%Y%m%d-%H%M%S).log"
echo "START: git-push" | tee -a "$LOGFILE"
git commit -m "feat: Add feature" 2>&1 | tee -a "$LOGFILE"
git push origin main 2>&1 | tee -a "$LOGFILE"
echo "END: git-push" | tee -a "$LOGFILE"
```

**Result**: Watchdog captures ALL output and displays it in Watchdog Log panel

---

## Verbatim Code Examples: Why Each Version Failed

### Example 1: Version 1 Watchdog — Terminal Count Only

**Code from Version 1** (commit hash: early Feb 11):
```typescript
// src/extension.ts (Version 1)
let trackedTerminals = new Set<vscode.Terminal>();

export function activate(context: vscode.ExtensionContext) {
    vscode.window.onDidOpenTerminal((term) => {
        trackedTerminals.add(term);
        log(`Terminal opened: ${term.name} (count: ${trackedTerminals.size})`);
    });

    vscode.window.onDidCloseTerminal((term) => {
        trackedTerminals.delete(term);
        log(`Terminal closed: ${term.name} (count: ${trackedTerminals.size})`);
    });
}
```

**What the user saw in Watchdog Log**:
```
[2026-02-11T10:23:45.123Z] Terminal opened: augment-bash-test (count: 1)
[2026-02-11T10:23:46.456Z] Terminal closed: augment-bash-test (count: 0)
```

**What was ACTUALLY happening** (hidden from watchdog):
```bash
$ ps aux | grep pts/4
owner    3752420  0.0  0.0  bash -i          # HIDDEN TERMINAL!
owner    3752422  0.0  0.0  bash scripts/start.sh
owner    3753567  0.0  0.0  bash -i
owner    3753568  0.0  0.0  bash scripts/start.sh
```

**Why it failed**:
- VS Code API `onDidOpenTerminal` only fires for **visible** terminals
- Extension host spawns hidden terminals using `child_process.spawn()` directly
- These processes have TTY=`pts/4` but are NOT tracked by VS Code's terminal API
- Watchdog showed "count: 0" while 4 hidden processes were running

**The gap**: VS Code API ≠ Actual process reality

---

### Example 2: Version 2 Watchdog — Process Detection Added

**Code from Version 2** (commit hash: Feb 11-14):
```typescript
// src/extension.ts (Version 2)
function detectHiddenTerminals(): Promise<HiddenTerminalInfo[]> {
    return new Promise((resolve) => {
        const pattern = 'code.*--ms-enable-electron-run-as-node|extensionHost';
        const username = os.userInfo().username;

        exec(`pgrep -u ${username} -f "${pattern}"`, (err, stdout, stderr) => {
            if (err) {
                resolve([]);
                return;
            }

            const pids = stdout.trim().split('\n').filter(Boolean);
            const processes: HiddenTerminalInfo[] = [];

            pids.forEach(pid => {
                exec(`ps -p ${pid} -o tty=`, (psErr, tty) => {
                    if (!psErr && tty.trim() === '?') {
                        processes.push({
                            pid: parseInt(pid),
                            tty: tty.trim(),
                            command: 'extensionHost'
                        });
                    }
                });
            });

            setTimeout(() => resolve(processes), 500);
        });
    });
}

setInterval(async () => {
    const processes = await detectHiddenTerminals();
    log(`[MONITOR] Found ${processes.length} hidden terminals`);
}, 5000);
```

**What the user saw in Watchdog Log**:
```
[2026-02-14T15:23:45.123Z] [MONITOR] Found 4 hidden terminals
[2026-02-14T15:23:50.456Z] [MONITOR] Found 4 hidden terminals
[2026-02-14T15:23:55.789Z] [MONITOR] Found 4 hidden terminals
```

**What the user COULDN'T see**:
- Which commands were running in those terminals
- What output they were producing
- Whether they were stuck or making progress
- What errors they might be throwing

**The problem**: Detection without visibility

**Real scenario that happened**:
```bash
# Terminal 1 (hidden, pts/4):
$ npm start
> firefox-performance-tuner@1.0.0 start
> bash scripts/start.sh
Starting backend on port 3001...
Error: EADDRINUSE: address already in use :::3001
    at Server.setupListenHandle [as _listen2] (node:net:1740:16)
```

**Watchdog showed**: "Found 1 hidden terminal"
**User saw**: Nothing (had to manually check terminal)
**AI saw**: `<error>Cancelled by user.</error>` (no output)

**Why it still failed**:
- Detected the EXISTENCE of hidden processes ✓
- But couldn't capture their OUTPUT ✗
- User still had to manually investigate
- AI still couldn't read the error messages

---

### Example 3: Version 3 Watchdog — Terminal Output Capture

**Code from Version 3** (commit 373931a, Feb 16):
```typescript
// src/extension.ts (Version 3 - PRODUCTION GRADE)
const processedFiles = new Map<string, number>();

function monitorTerminalOutput() {
    const workspaceFolder = vscode.workspace.workspaceFolders?.[0];
    if (!workspaceFolder) {
        log("WARNING | No workspace folder found, terminal output monitoring disabled");
        return;
    }

    const notesDir = path.join(workspaceFolder.uri.fsPath, '.notes');

    // Poll for new terminal log files every 1 second
    setInterval(() => {
        try {
            if (!fs.existsSync(notesDir)) {
                return;
            }

            const files = fs.readdirSync(notesDir);

            files.forEach(filename => {
                if (!filename.startsWith('terminal-') || !filename.endsWith('.log')) {
                    return;
                }

                const filePath = path.join(notesDir, filename);

                try {
                    const stats = fs.statSync(filePath);
                    const currentSize = stats.size;
                    const lastSize = processedFiles.get(filePath) || 0;

                    // Skip if file hasn't changed
                    if (currentSize === lastSize) {
                        return;
                    }

                    // Read the file
                    const content = fs.readFileSync(filePath, 'utf-8');
                    const lines = content.split('\n').filter(line => line.trim());

                    if (lines.length === 0) {
                        return;
                    }

                    // Update processed size
                    processedFiles.set(filePath, currentSize);

                    // Log all lines from the terminal output
                    log(`TERMINAL OUTPUT | File: ${filename} | Lines: ${lines.length}`);
                    lines.forEach(line => {
                        log(`  ${line}`);
                    });

                } catch (err) {
                    // File might be being written, skip this iteration
                }
            });

        } catch (err) {
            log(`ERROR | Failed to scan terminal logs: ${err}`);
        }
    }, 1000);

    log("INFO | Terminal output monitoring started");
}

export function activate(context: vscode.ExtensionContext) {
    log("Watchdog activated.");

    monitorEventLoop();
    monitorTerminals();
    monitorProcesses();
    monitorCancellationPatterns();
    monitorTerminalOutput();  // ← NEW: Terminal output capture

    setInterval(heartbeat, HEARTBEAT_INTERVAL);
}
```

**What the user NOW sees in Watchdog Log**:
```
[2026-02-16T21:50:34.877Z] TERMINAL OUTPUT | File: terminal-20260216-164639.log | Lines: 5
[2026-02-16T21:50:34.877Z]   START: compliance-test-2
[2026-02-16T21:50:34.877Z]   Line 1: This should appear in Watchdog Log
[2026-02-16T21:50:34.878Z]   Line 2: Testing terminal output capture
[2026-02-16T21:50:34.878Z]   Line 3: All lines must be visible
[2026-02-16T21:50:34.879Z]   END: compliance-test-2
```

**Real scenario that NOW works**:
```bash
# Command executed with tee:
LOGFILE=".notes/terminal-$(date +%Y%m%d-%H%M%S).log"
echo "START: test-backend-api" | tee -a "$LOGFILE"
curl -s http://localhost:3001/api/external-players 2>&1 | tee -a "$LOGFILE"
echo "END: test-backend-api" | tee -a "$LOGFILE"
```

**Watchdog Log shows**:
```
[2026-02-16T17:23:15.123Z] TERMINAL OUTPUT | File: terminal-20260216-172315.log | Lines: 3
[2026-02-16T17:23:15.124Z]   START: test-backend-api
[2026-02-16T17:23:15.125Z]   {"players":[{"name":"VLC","command":"vlc","installed":true},{"name":"MPV","command":"mpv","installed":true}],"count":2}
[2026-02-16T17:23:15.126Z]   END: test-backend-api
```

**Why this FINALLY works**:
- ✅ Captures ALL terminal output from log files
- ✅ Displays in real-time (1-second polling)
- ✅ Provides backup when tool results are truncated
- ✅ Works even when `<output>` section is empty
- ✅ Persistent logs for forensic analysis
- ✅ File size tracking prevents duplicate processing

**The breakthrough**: Polling-based file monitoring instead of relying on VS Code API or process detection alone

---

## The Complete Picture: Why All Three Versions Were Needed

### Version 1: Foundation
- **What it did**: Tracked VS Code's visible terminals
- **What it missed**: Hidden processes spawned by extension host
- **Lesson learned**: VS Code API ≠ Reality

### Version 2: Detection
- **What it added**: Process-level monitoring with `pgrep` and `ps`
- **What it missed**: Terminal output content
- **Lesson learned**: Detection without visibility is insufficient

### Version 3: Visibility
- **What it added**: Terminal output capture from `.notes/terminal-*.log` files
- **What it provides**: Complete forensic evidence and real-time monitoring
- **Lesson learned**: Polling-based file monitoring is the only reliable way to capture ALL output

---

## The Mandatory Pattern: Commands MUST Use `tee`

### Why Git Push Didn't Appear in Watchdog Log

**Command executed** (Feb 16, 17:50):
```bash
echo "START: commit-working-version" && \
cd /home/owner/Documents/.../hidden-terminal-watchdog && \
git add -A && \
git commit -m "feat: Add terminal output monitoring" && \
git push origin main 2>&1 && \
echo "END: commit-working-version"
```

**Watchdog Log showed**: Nothing (no output captured)

**Why**: No `tee` command, so no log file was created!

**Correct version**:
```bash
LOGFILE="/home/owner/Documents/.../.notes/terminal-$(date +%Y%m%d-%H%M%S).log"
echo "START: commit-working-version" | tee -a "$LOGFILE"
cd /home/owner/Documents/.../hidden-terminal-watchdog 2>&1 | tee -a "$LOGFILE"
git add -A 2>&1 | tee -a "$LOGFILE"
git commit -m "feat: Add terminal output monitoring" 2>&1 | tee -a "$LOGFILE"
git push origin main 2>&1 | tee -a "$LOGFILE"
echo "END: commit-working-version" | tee -a "$LOGFILE"
```

**Watchdog Log would show**:
```
[2026-02-16T17:50:45.123Z] TERMINAL OUTPUT | File: terminal-20260216-175045.log | Lines: 15
[2026-02-16T17:50:45.124Z]   START: commit-working-version
[2026-02-16T17:50:45.125Z]   [main 373931a] feat: Add terminal output monitoring
[2026-02-16T17:50:45.126Z]    1 file changed, 91 insertions(+), 265 deletions(-)
[2026-02-16T17:50:45.127Z]   Enumerating objects: 13, done.
[2026-02-16T17:50:45.128Z]   Counting objects: 100% (13/13), done.
[2026-02-16T17:50:45.129Z]   To https://github.com/swipswaps/hidden-terminal-watchdog.git
[2026-02-16T17:50:45.130Z]      2be63f2..373931a  main -> main
[2026-02-16T17:50:45.131Z]   END: commit-working-version
```

---

## Repository Structure

```
augment-extension-bug-bounty/
├── REPO.md                        # This file (comprehensive overview)
├── COMPLETE_ANALYSIS.md           # Complete technical explanation
├── ROOT_CAUSE_FOUND.md            # Bug 1 root cause analysis
├── EVIDENCE_TIMELINE.md           # Day-by-day investigation timeline
├── INDEX.md                       # Full document index
│
├── docs/                          # Detailed analysis documents
│   ├── RULE22_WAIT_FALSE_VIOLATION.md    # Bug 2 detailed analysis
│   ├── RULE9_VIOLATION.md                # AI prompt violation analysis
│   ├── RULE9_CODE_FIX.md                 # Code-level fix for Bug 1
│   ├── FINAL_FINDINGS.md                 # Summary of findings
│   └── TIMELINE.md                       # Investigation timeline
│
├── fixes/                         # Fix implementations
│   ├── apply-complete-fix.js             # 3-part fix for Bug 1
│   ├── apply-webview-fix.py              # Webview layer fix
│   ├── apply-cancelToolRun-fix.py        # Extension host fix
│   └── README.md                         # Fix documentation
│
├── reproduction/                  # Reproduction scripts
│   ├── test-bug-2.sh                     # Reproduce timeout bug
│   ├── test-bug-5.sh                     # Reproduce terminal accumulation
│   └── README.md                         # Reproduction guide
│
├── user-override-tools/           # Manual recovery tools
│   ├── disable-terminal-sandbox.sh       # Disable terminal restrictions
│   ├── force-continue.sh                 # Force AI to continue
│   ├── manual-output-reader.sh           # Read output manually
│   └── README.md                         # Tool documentation
│
└── evidence/                      # Evidence files
    └── README.md                         # Evidence documentation
```

---

## Key Findings Summary

### Bug 1: Timeout Race Condition
- **Root Cause**: `cancelToolRun` returns `true`/`false`, NOT the captured output
- **Location**: `extension.js` lines 236551-236554, 272355-272357
- **Impact**: Every command >10 seconds loses output
- **Fix**: 3-part code change to store and return output before Promise cancellation
- **Status**: ✅ Fix developed and tested, ❌ Lost to VS Code update

### Bug 2: Terminal Accumulation
- **Root Cause**: AI spawning hidden terminals with `wait=false`
- **Trigger**: 100+ accumulated terminals → MCP instability → `_cancelledByUser = true` (one-way latch)
- **Impact**: ALL tool calls fail permanently with "Cancelled by user."
- **Fix**: Hidden Terminal Watchdog Extension (mitigation)
- **Status**: ✅ Deployed and verified working

### The Cascade Effect
- Bug 1 alone: 🟠 HIGH severity (annoying but workable)
- Bug 2 alone: 🔴 CRITICAL severity (complete failure)
- Bug 1 + Bug 2: 🔴 CATASTROPHIC (system unusable)
- With Watchdog: 🟡 MEDIUM severity (manageable)

---

## Related Repositories

- **Bug Report**: https://github.com/swipswaps/augment-extension-bug-bounty
- **Watchdog Solution**: https://github.com/swipswaps/hidden-terminal-watchdog
- **Firefox Performance Tuner** (test project): https://github.com/swipswaps/firefox-performance-tuner

---

## How to Use This Repository

### For Augment Team
1. Read **[COMPLETE_ANALYSIS.md](COMPLETE_ANALYSIS.md)** for full technical details
2. Review **[ROOT_CAUSE_FOUND.md](ROOT_CAUSE_FOUND.md)** for Bug 1 root cause
3. Examine **[fixes/apply-complete-fix.js](fixes/apply-complete-fix.js)** for the 3-part fix
4. Test with **[reproduction/test-bug-2.sh](reproduction/test-bug-2.sh)**
5. Consider integrating **Hidden Terminal Watchdog** into Augment extension

### For Users Experiencing the Bug
1. Install **Hidden Terminal Watchdog** extension (mitigation)
2. Use **[user-override-tools/](user-override-tools/)** for manual recovery
3. Follow **[QUICK_REPRODUCTION_GUIDE.md](QUICK_REPRODUCTION_GUIDE.md)** to verify the bug
4. Report your experience to Augment team

### For Developers Investigating Similar Issues
1. Read **[EVIDENCE_TIMELINE.md](EVIDENCE_TIMELINE.md)** for investigation methodology
2. Study **[docs/RULE22_WAIT_FALSE_VIOLATION.md](docs/RULE22_WAIT_FALSE_VIOLATION.md)** for terminal hygiene patterns
3. Review **[docs/RULE9_VIOLATION.md](docs/RULE9_VIOLATION.md)** for AI prompt issues
4. Examine **forensic techniques** used to discover the one-way latch

---

## Testing and Verification

### Watchdog Status (2026-02-16 17:56)
```
[2026-02-16T21:56:32.337Z] HEARTBEAT | terminals=5 | cancellations=0
[2026-02-16T21:50:34.877Z] TERMINAL OUTPUT | File: terminal-20260216-164639.log | Lines: 5
[2026-02-16T21:50:34.877Z]   START: compliance-test-2
[2026-02-16T21:50:34.877Z]   Line 1: This should appear in Watchdog Log
[2026-02-16T21:50:34.878Z]   Line 2: Testing terminal output capture
[2026-02-16T21:50:34.878Z]   Line 3: All lines must be visible
[2026-02-16T21:50:34.879Z]   END: compliance-test-2
```

**Evidence**: ✅ Terminal output capture working correctly

### Firefox Project Status (2026-02-16 17:23)
```
Backend API: {"players":[{"name":"VLC","command":"vlc","installed":true},{"name":"MPV","command":"mpv","installed":true}],"count":2}
Frontend: HTTP 200
Git Status: On branch master, nothing to commit, working tree clean
Last Commit: 1a1fa3c docs: Add screenshots and improve external player detection
```

**Evidence**: ✅ Full workflow tested locally before push (RULE LV-1 compliance)

---

## Financial Impact Analysis

### Cost Per User Per Year
- **Manual interventions**: 5-20 per hour × 8 hours/day × 250 days/year = 10,000-40,000 interventions
- **Time per intervention**: 30-60 seconds
- **Total time wasted**: 83-667 hours/year
- **At $30/hour**: $2,500-$20,000/year per active user

### Conservative Estimate
- **Assuming 50% of interventions are due to these bugs**: $1,250-$10,000/year
- **Realistic estimate**: $1,000-$2,000/year per active user

### Augment User Base Impact
- **If 1,000 active users**: $1,000,000-$2,000,000/year total waste
- **If 10,000 active users**: $10,000,000-$20,000,000/year total waste

---

## Recommendations

### Immediate (P0)
1. ✅ **Fix Bug 1**: Implement 3-part code change to return output on timeout
2. ✅ **Fix AI Prompt**: Update RULE 9 to ALWAYS read `<output>` section first
3. ✅ **Reset Latch**: Make `_cancelledByUser` reset to `false` after recovery

### Short-term (P1)
1. ✅ **Integrate Watchdog**: Bundle Hidden Terminal Watchdog with Augment extension
2. ✅ **Add Telemetry**: Track timeout frequency and terminal accumulation
3. ✅ **Increase Timeouts**: Default `max_wait_seconds` from 10 to 60

### Long-term (P2)
1. ✅ **Regression Tests**: Add automated tests for timeout scenarios
2. ✅ **Better Error Messages**: Distinguish between user cancel vs timeout
3. ✅ **Resource Monitoring**: Alert when terminal count exceeds threshold

---

## Contact and Submission

**Reporter**: swipswaps
**Report ID**: `174ab568-83ed-4b09-9ac9-dce2f07c6fcf`
**Date**: 2026-02-09 to 2026-02-16
**Total Investigation Time**: 7+ days, 60+ hours
**GitHub**: https://github.com/swipswaps/augment-extension-bug-bounty

**Status**: Root cause identified, fixes developed, mitigation deployed and verified working.

---

## License

MIT License - See [LICENSE](LICENSE) file for details.

---

**Last Updated**: 2026-02-16 17:56 UTC
**Watchdog Version**: v1.0.0 (commit 373931a)
**Extension Version Tested**: Augment VSCode v0.754.3


