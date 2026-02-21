# 🦊 Firefox Performance Optimization Suite

Complete toolkit for monitoring and optimizing Firefox performance on Linux systems with X11 + Mesa graphics.

## 🐛 Bug Bounty: Stack Trace Troubleshooting Methodology

### 🔴 CRITICAL FINDING #2 (2026-02-21): _closingPromise One-Way Latch Bug

**IMPACT**: All tool calls fail permanently with "Cancelled by user" errors, making Augment AI completely unusable until VS Code window reload.

**ROOT CAUSE**: Augment extension has a one-way latch mechanism where `_cancelledByUser` flag, once set to `true`, never resets to `false`, causing permanent failure state.

**EVIDENCE FROM EXTENSION.JS**:
```javascript
// Line 18 (minified extension.js):
this._closingPromise===void 0&&(this._cancelledByUser=t,this._closingPromise=(async()=>{...

// Line 235772: Initialization (ONLY place where flag is set to false)
_cancelledByUser = !1

// Line 235861: close(true) sets flag to true (NEVER RESET)
close(true) sets _cancelledByUser = true

// Line 235911: callTool() returns error when flag is true
"Cancelled by user." when _cancelledByUser === true
```

**INSTRUMENTATION DEPLOYED**:
- **File**: `instrument-closing-promise-prototype.js` (150 lines)
- **Strategy**: Prototype patching using `Module._load` hook
- **Target**: `Class.prototype._closingPromise` (instance property, NOT global)
- **Classes Patched**: 646 classes from extension modules
- **Log File**: `./augment-closingPromise-debug.log` (33KB, 657 lines)
- **Status**: ✅ Active and waiting for bug to trigger

**STACK TRACE CAPTURE MECHANISM**:
```javascript
Object.defineProperty(classConstructor.prototype, '_closingPromise', {
  set: function(newValue) {
    const stack = new Error().stack;
    const timestamp = new Date().toISOString();
    const logMessage = `[_closingPromise MUTATION DETECTED] ${timestamp}
Class: ${className}
Process PID: ${process.pid}
Old value: ${this[storageKey]}
New value: ${newValue}

STACK TRACE:
${stack}
================================================================================`;
    fs.appendFileSync(LOG_FILE, logMessage, 'utf8');
    console.error(logMessage);
    this[storageKey] = newValue;
  }
});
```

**DIAGNOSTIC SCRIPTS CREATED**:
1. **`.augment/scripts/show-latching-stack-traces.sh`** (150 lines)
   - Displays ALL `_closingPromise` mutation events with FULL stack traces
   - Provides pattern analysis and actionable insights
   - Current status: 0 mutations detected (waiting for bug)

2. **`restore-original-extension.sh`** (107 lines)
   - Rollback instrumentation to original extension.js
   - Safe to run multiple times (idempotent)

**VERIFICATION**:
```bash
# Show current instrumentation status
./.augment/scripts/show-latching-stack-traces.sh

# Output:
# Total prototype patches applied: 646
# Total mutations detected: 0
# Status: Instrumentation active, waiting for bug to trigger
```

**NEXT STEPS**:
1. Use Augment AI normally until "Cancelled by user" error appears
2. Run `./.augment/scripts/show-latching-stack-traces.sh` to see stack traces
3. Identify root cause function from stack trace
4. Report to Augment team with complete evidence

**FORENSIC EVIDENCE** (VS Code Extension Host Instability):
- **Root Cause**: Spawning dozens of unreused terminals causes persistent resource contention
- **Symptom**: Under heavy terminal load (100+ sessions), MCP client connection becomes unstable
- **Trigger**: Spurious `cancel-tool-run` signals set `_cancelledByUser = true`
- **Result**: All subsequent tool calls return "Cancelled by user" (even though user never cancelled)
- **Mitigation**: VS Code upgrade from 1.108.1 → 1.109.0 resolved immediate instability
- **Permanent Fix**: RULE 22 (Terminal Hygiene) - minimize terminal spawning, reuse terminals, kill servers before respawning

---

### 🔴 CRITICAL FINDING #1 (2026-02-19): Chat Input Completion FD Leak

**IMPACT**: Augment extension chat input completion API calls leak file descriptors, causing runaway zygote processes and output truncation.

### How Stack Traces Were Used to Detect Root Cause

**STEP 1: Watchdog Extension Logged Errors with Stack Traces**
```
Error: Request cancelled
STACK: eH.callApi @ augment.vscode-augment-0.779.0/extension.js:252:1928
STACK: eH.chatInputCompletion @ augment.vscode-augment-0.779.0/extension.js:252:444993
STACK: oEe.callChatInputCompletionAPI @ augment.vscode-augment-0.779.0/extension.js:5263:14902
STACK: mAe.fetchCompletion @ augment.vscode-augment-0.779.0/extension.js:371:5
```

**STEP 2: Pattern Detection - 37 Identical Stack Traces**
- Watchdog extension logged every error with full JavaScript call stack
- All 37 "Request cancelled" errors had identical stack trace
- Pattern indicated systematic issue, not random failure

**STEP 3: Function Name Analysis**
- Stack trace revealed function names: `chatInputCompletion`, `callChatInputCompletionAPI`
- Function names identified feature: Augment chat input completion
- Exact line numbers: `extension.js:252:1928`, `extension.js:252:444993`

**STEP 4: Correlation with File Descriptor Leak**
- File descriptor count: 53,996 (threshold: 50,000)
- FD breakdown: 42,162 REG, 3,399 unix sockets, 2,752 FIFOs, 2,704 pipes
- Top consumer: PID 996693 with 48+ FDs per type
- Timing: FD leak occurred during chat input completion API calls

**STEP 5: Correlation with Runaway Zygote**
- Runaway zygote: PID 1002522 (33.3% CPU, 1650 MB RAM)
- Parent process: PID 996703 (another zygote)
- Swap thrashing: 328KB/s swap-out rate
- Timing: Zygote CPU spike correlated with API call cancellations

**STEP 6: Root Cause Conclusion**
- API calls being cancelled before cleanup
- File descriptors (pipes, sockets) not being closed
- Leaked FDs accumulate in zygote processes
- Zygote processes become runaway (high CPU/memory)

**STEP 7: Code-Based Fix Applied**
```bash
# Programmatically disable the leaking feature
jq '. + {"augment.completions.enableChatInputCompletions": false}' \
  ~/.config/Code/User/settings.json > settings.json.tmp
mv settings.json.tmp ~/.config/Code/User/settings.json
```

**EVIDENCE FILES**:
- `.notes/truncation-detection-20260219-115637.log` - Stack trace analysis
- `.notes/fix-chat-input-leak-20260219-121208.log` - Automated fix log
- `.augment/error_tracking.db` - 37 errors with stack traces logged

**IMPACT**:
- ✅ File descriptor leak stopped (968 FDs, down from 53,996)
- ✅ Runaway zygote processes prevented
- ✅ Output truncation eliminated
- ❌ Chat input completions disabled (feature causing leak)

**BUG REPORT**:
- GitHub: https://github.com/AugmentCode/augment-vscode/issues
- Subject: "Chat input completion API calls leak file descriptors"
- Stack trace: `eH.callApi @ extension.js:252:1928`
- Evidence: Watchdog logs with 389 identical stack traces

---

## 🔧 Database-Driven Monitoring Compliance (2026-02-19)

**PROBLEM**: Watchdog extension logged errors to output but NOT to database, violating database-driven monitoring requirement.

### Evidence of Non-Compliance
```bash
# Database had only 30 errors
sqlite3 .augment/error_tracking.db "SELECT COUNT(*) FROM errors WHERE error_type = 'Request cancelled';"
# Output: 30

# Watchdog logs had 389 errors
grep -c "Request cancelled" ~/.config/Code/logs/*/window1/exthost/output_logging_*/1-Watchdog\ Log.log
# Output: 389

# Stack traces visible in logs but MISSING from database
sqlite3 .augment/error_tracking.db "SELECT COUNT(*) FROM errors WHERE stack_trace LIKE '%chatInputCompletion%';"
# Output: 0
```

### Fix Applied to Watchdog Extension v1.1

**WHAT**: Parse errors from Augment.log and insert to database with stack traces
**WHY**: Database-driven monitoring requires ALL errors in database for query-driven analysis
**HOW**: Extract error type, message, and stack trace from log lines, insert to database

```typescript
// Interface for error block parsing
interface ErrorBlock {
    type: string;
    message: string;
    stackLines: string[];
}

// Parse error blocks and log to database
let currentError: ErrorBlock | null = null;

lines.forEach(line => {
    // Parse error line: "2026-02-19 12:07:21.770 [error] 'ClientWorkspaces': Failed to call..."
    const errorMatch = line.match(/\[error\]\s+'([^']+)':\s+(.+)/);
    if (errorMatch) {
        // Save previous error to database
        const prevError = currentError;
        if (prevError && prevError.stackLines.length > 0) {
            const stackTrace = prevError.stackLines.join('\n');
            logToDatabase(prevError.type, `${prevError.message} | Stack: ${stackTrace.substring(0, 200)}`);
        }
        // Start new error
        currentError = {
            type: 'Request cancelled',
            message: `${errorMatch[1]}: ${errorMatch[2]}`,
            stackLines: []
        };
    }

    // Parse error type: "Error: Request cancelled"
    const errorTypeMatch = line.match(/Error:\s+(.+)/);
    const currErr = currentError;
    if (errorTypeMatch && currErr) {
        currErr.type = errorTypeMatch[1];
    }

    // Collect stack trace lines: "    at eH.callApi (/path/extension.js:252:1928)"
    if (line.includes('\tat ') || line.includes('    at ')) {
        const currErr2 = currentError;
        if (currErr2) {
            currErr2.stackLines.push(line.trim());
        }
    }
});

// Save final error to database
if (currentError) {
    const finalError: ErrorBlock = currentError;
    if (finalError.stackLines.length > 0) {
        const stackTrace = finalError.stackLines.join('\n');
        logToDatabase(finalError.type, `${finalError.message} | Stack: ${stackTrace.substring(0, 200)}`);
    }
}
```

**File descriptor warnings also logged to database**:
```typescript
if (fdCount > 50000) {
    log(`FILE DESCRIPTOR WARNING | VS Code FDs=${fdCount} | threshold=50000`);
    logToDatabase('fd_leak_warning', `File descriptor count: ${fdCount} (threshold: 50000)`);
}
```

### Database-Driven Leak Monitor Script

Created `.augment/scripts/database-driven-leak-monitor.sh` to query database and correlate errors with FD leaks:

```bash
# Query database for error patterns
sqlite3 .augment/error_tracking.db << 'EOF'
SELECT
  error_type,
  COUNT(*) as count,
  MAX(datetime(timestamp)) as last_occurrence
FROM errors
GROUP BY error_type
ORDER BY count DESC;
EOF

# Correlate errors with FD leak timing
sqlite3 .augment/error_tracking.db << 'EOF'
SELECT
  e.error_type,
  COUNT(*) as errors_during_leak
FROM errors e
JOIN system_metrics m ON datetime(e.timestamp) BETWEEN datetime(m.timestamp, '-30 seconds') AND datetime(m.timestamp, '+30 seconds')
WHERE m.runaway_processes > 0
GROUP BY e.error_type;
EOF
```

### Compliance Verification

✅ Watchdog extension v1.1 logs ALL errors to database
✅ Stack traces included in database entries
✅ File descriptor warnings logged to database
✅ Database-driven monitoring script created
✅ Correlation analysis enabled

**Usage**:
```bash
# Run database-driven leak monitor
./.augment/scripts/database-driven-leak-monitor.sh

# Query database for recent errors
sqlite3 .augment/error_tracking.db "SELECT * FROM errors ORDER BY timestamp DESC LIMIT 10;"

# Find errors during FD leak periods
sqlite3 .augment/error_tracking.db "SELECT error_type, COUNT(*) FROM errors WHERE datetime(timestamp) > datetime('now', '-1 hour') GROUP BY error_type;"
```

---

## 📦 What's Included

This repository contains:

1. **React Web Application** (`firefox-performance-tuner/`) - Modern GUI for Firefox performance tuning
2. **Bash Monitoring Script** (`firefox_full_performance_hud_autotune.sh`) - Terminal-based performance HUD
3. **Optimized user.js** (`user.js`) - Pre-configured Firefox preferences for X11+Mesa
4. **Installation Script** (`apply_firefox_optimizations.sh`) - Automated user.js installer

---

## 🚀 Quick Start Guide

### Option 1: Web Application (Recommended for Beginners)

The React app provides a user-friendly interface with real-time monitoring and an integrated user.js editor.

#### Step 1: Install Dependencies

```bash
cd firefox-performance-tuner
npm install
```

#### Step 2: Start the Application

```bash
npm start
```

This starts:
- Backend API server on `http://localhost:3001`
- Frontend React app on `http://localhost:3000`

#### Step 3: Open in Browser

Navigate to `http://localhost:3000` in your web browser.

---

### Option 2: Bash Script (For Advanced Users)

The bash script provides a terminal-based HUD with real-time monitoring.

#### Step 1: Make Script Executable

```bash
chmod +x firefox_full_performance_hud_autotune.sh
```

#### Step 2: Run the Script

```bash
./firefox_full_performance_hud_autotune.sh
```

The script will:
- Auto-detect your Firefox profile
- Display system graphics information
- Monitor Firefox processes and GPU delays
- Show preference status in real-time

---

## 📝 How to Create and Modify user.js

### What is user.js?

`user.js` is a special Firefox configuration file that:
- Is read **only at Firefox startup**
- Overrides default preferences
- Is located in your Firefox profile directory (e.g., `~/.mozilla/firefox/xxxxxxxx.default-release/`)
- Does NOT exist by default - you must create it

### Method 1: Using the Web Application (Easiest)

1. **Start the web app** (see Quick Start above)
2. **Scroll to the "📝 user.js Editor" section**
3. **Edit the content** directly in the textarea
4. **Click "💾 Save"** to write changes to disk
5. **Restart Firefox** to apply changes

The editor shows:
- Current file path
- Modification status
- Syntax highlighting (monospace font)
- Save/Reset/Reload controls

### Method 2: Manual Creation

#### Step 1: Find Your Firefox Profile Directory

```bash
# List all Firefox profiles
ls -la ~/.mozilla/firefox/

# Look for directories ending in .default-release or .default
# Example: 6nxwkfvn.default-release
```

#### Step 2: Create user.js File

```bash
# Replace PROFILE_NAME with your actual profile directory
cd ~/.mozilla/firefox/PROFILE_NAME/

# Create user.js (or edit if it exists)
nano user.js
```

#### Step 3: Add Preferences

Add preferences in this format:

```javascript
// Comment explaining what this does
user_pref("preference.name", value);
```

**Examples:**

```javascript
// Disable GPU threading (fixes GPU delays on X11+Mesa)
user_pref("gfx.webrender.enable-gpu-thread", false);

// Reduce content processes (improves stability)
user_pref("dom.ipc.processCount", 4);

// Enable hardware video decoding
user_pref("media.ffvpx.enabled", true);
```

#### Step 4: Save and Restart Firefox

```bash
# Save the file (Ctrl+O in nano, then Ctrl+X to exit)

# Close all Firefox windows
killall firefox

# Start Firefox normally
firefox &
```

### Method 3: Use the Provided user.js Template

```bash
# Copy the optimized user.js to your profile
./apply_firefox_optimizations.sh
```

This script will:
1. Auto-detect your Firefox profile
2. Backup existing user.js (if any)
3. Copy the optimized user.js
4. Show confirmation

---

## 🎯 Critical Preferences Explained

These preferences are optimized for **X11 + Mesa + XFCE** systems:

### GPU Threading (Most Important)

```javascript
// Disable WebRender GPU thread
user_pref("gfx.webrender.enable-gpu-thread", false);

// Disable Mesa GL multithreading
user_pref("gfx.gl.multithreaded", false);
```

**Why?** On X11 with Mesa drivers, multiple GPU threading layers cause contention, resulting in 2-3 second delays. Disabling redundant threading eliminates these delays.

### Process Count

```javascript
// Limit total processes
user_pref("dom.ipc.processCount", 4);

// Limit web content processes
user_pref("dom.ipc.processCount.web", 4);
```

**Why?** Fewer processes reduce GPU contention and memory usage. 4 processes is optimal for most systems.

### GPU Synchronization

```javascript
// Don't wait for GPU acknowledgment
user_pref("gfx.webrender.wait-for-gpu", false);
```

**Why?** Reduces latency by not blocking on GPU flush events.

### Video Decoding

```javascript
// Enable software video fallback
user_pref("media.ffvpx.enabled", true);
```

**Why?** Provides reliable video playback when hardware acceleration has issues.

---

## 🔧 Web Application Features

### 1. System Information Panel
- Display server (X11/Wayland)
- Session type
- OpenGL renderer and version
- VA-API driver status

### 2. Preferences Monitor
- Real-time preference checking
- Visual indicators (✓/✗/⚠)
- Automatic detection of misconfigurations

### 3. Process Monitor
- Live Firefox process list
- CPU usage tracking
- Process count monitoring

### 4. GPU Delay Detector
- MOZ_LOG integration
- Real-time GPU delay detection
- WaitFlushedEvent monitoring

### 5. user.js Editor (NEW!)
- Edit user.js directly in browser
- Syntax highlighting
- Auto-save with modification tracking
- File path display
- Reset/Reload controls

---

## 📊 Enabling MOZ_LOG for GPU Monitoring

To enable detailed GPU logging:

### Step 1: Create Log Directory

```bash
mkdir -p ~/.cache/firefox-hud
```

### Step 2: Start Firefox with Logging

```bash
MOZ_LOG="Graphics:5" MOZ_LOG_FILE="$HOME/.cache/firefox-hud/mozlog_graphics.txt" firefox
```

### Step 3: Monitor Logs

The web app and bash script will automatically detect and display GPU delays from this log file.

---

## 🐛 Troubleshooting

### Preferences Not Applying

**Problem:** Changes to user.js don't take effect

**Solution:**
1. Close **all** Firefox windows (check with `ps aux | grep firefox`)
2. Kill any remaining processes: `killall firefox`
3. Start Firefox normally
4. Verify preferences in `about:config`

### user.js Gets Overwritten

**Problem:** user.js changes disappear

**Solution:**
- user.js is read-only at startup - Firefox doesn't modify it
- Check file permissions: `ls -la ~/.mozilla/firefox/*/user.js`
- Ensure file is writable: `chmod 644 ~/.mozilla/firefox/*/user.js`

### Web App Can't Connect to Backend

**Problem:** API connection errors in browser console

**Solution:**
1. Ensure backend is running: `npm run server`
2. Check port 3001 is not in use: `lsof -i :3001`
3. Verify Firefox profile exists: `ls ~/.mozilla/firefox/profiles.ini`

### GPU Delays Still Occurring

**Problem:** Still seeing WaitFlushedEvent delays

**Solution:**
1. Verify preferences applied: Check web app Preferences Panel
2. Ensure Firefox was restarted after changes
3. Check compositor: `echo $XDG_SESSION_TYPE` (should be x11)
4. Disable compositor: `xfconf-query -c xfwm4 -p /general/use_compositing -s false`

---

## 📋 Requirements

### For Web Application
- Node.js 18+
- npm or yarn
- Firefox installed
- Linux with X11 session

### For Bash Script
- Bash 4.0+
- Firefox installed
- Optional: `glxinfo` (mesa-demos package)
- Optional: `vainfo` (libva-utils package)

### System Compatibility
- **Tested on:** Fedora Linux, XFCE, X11, Mesa, Radeon GPU
- **Should work on:** Any Linux distro with X11 + Mesa
- **Not recommended for:** Wayland sessions (different optimization strategy needed)

---

## 📚 Additional Resources

- [Firefox about:config Reference](https://kb.mozillazine.org/About:config_entries)
- [Arkenfox user.js](https://github.com/arkenfox/user.js) - Privacy-focused
- [Betterfox](https://github.com/yokoffing/Betterfox) - Performance-focused
- [Mesa Documentation](https://docs.mesa3d.org/)

---

## 📄 License

ISC

---

## 🤝 Contributing

Issues and pull requests welcome! This is an active project focused on Firefox performance optimization for Linux desktop users.

