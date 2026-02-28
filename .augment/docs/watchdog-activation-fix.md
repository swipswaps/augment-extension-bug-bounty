# Watchdog Extension Activation Fix

## WHAT
Added comprehensive error handling and debug logging to watchdog extension activate() function

## WHY
Extension was activating (per VS Code logs) but not creating output channel or logging to database

## HOW
Wrapped activate() function in try-catch with console.log statements at each step

---

## ROOT CAUSE ANALYSIS

### Evidence
```
✅ Extension installed: prf-compliance.hidden-terminal-watchdog@1.0.0
✅ Extension activates 5 times (per exthost.log)
✅ exports.activate exists in compiled code (line 36)
✅ No errors in extension host log after activation
❌ No "Watchdog Log" output channel created
❌ No watchdog log file created
❌ No database entries from watchdog
```

### Hypothesis
activate() function is called by VS Code but fails silently during execution

### Likely Failure Points
1. `log()` function fails to create output channel
2. `getTerminal()` or `getChannel()` throws error
3. One of the monitor functions throws error
4. Error is caught somewhere and not logged

---

## FIX APPLIED

### Before (No Error Handling)
```typescript
export function activate(context: vscode.ExtensionContext) {
    log("Watchdog activated.");
    
    const terminal = getTerminal();
    terminal.show(true);
    
    monitorEventLoop();
    monitorTerminals();
    // ... more monitors
}
```

### After (With Error Handling and Debug Logging)
```typescript
export function activate(context: vscode.ExtensionContext) {
    // WHAT: Log to console for debugging activation
    // WHY: Extension activates but no output channel appears - need to see if activate() runs
    // HOW: console.log writes to extension host log, visible even if extension fails
    console.log("[WATCHDOG] activate() function called - extension is loading");
    
    try {
        // WHAT: Log activation message to output channel
        // WHY: First indication that extension is running
        // HOW: Call log() which creates output channel and terminal
        log("Watchdog activated.");
        console.log("[WATCHDOG] log() call succeeded");

        // WHAT: Show terminal immediately
        // WHY: Make watchdog output visible to user
        // HOW: Get terminal instance and call show()
        const terminal = getTerminal();
        terminal.show(true);
        console.log("[WATCHDOG] Terminal shown");

        // WHAT: Start all monitoring functions
        // WHY: Core watchdog functionality
        // HOW: Call each monitor function to set up intervals
        monitorEventLoop();
        monitorTerminals();
        monitorProcesses();
        monitorCancellationPatterns();
        monitorTerminalOutput();
        monitorSystemEvents();
        monitorApplicationEvents();
        console.log("[WATCHDOG] All monitors started");

        // WHAT: Monitor zygote processes every 30 seconds
        // WHY: Detect runaway zygote processes causing resource leaks
        // HOW: setInterval calls monitorZygoteProcesses every ZYGOTE_CHECK_INTERVAL
        setInterval(monitorZygoteProcesses, ZYGOTE_CHECK_INTERVAL);
        log(`INFO | Zygote monitoring started (CPU > ${ZYGOTE_CPU_THRESHOLD}%, Memory > ${ZYGOTE_MEMORY_THRESHOLD}MB)`);

        // WHAT: Start heartbeat to show extension is alive
        // WHY: Periodic status updates for debugging
        // HOW: setInterval calls heartbeat every HEARTBEAT_INTERVAL
        setInterval(heartbeat, HEARTBEAT_INTERVAL);
        console.log("[WATCHDOG] Heartbeat started");
        
        console.log("[WATCHDOG] activate() completed successfully");
    } catch (err) {
        // WHAT: Catch and log any errors during activation
        // WHY: Silent failures prevent debugging
        // HOW: Log error to console (always visible) and try to log to output channel
        console.error("[WATCHDOG] ACTIVATION FAILED:", err);
        try {
            log(`CRITICAL | Activation failed: ${err}`);
        } catch (logErr) {
            console.error("[WATCHDOG] Failed to call log():", logErr);
        }
    }
}
```

---

## VERIFICATION STEPS

### After Reload
1. **Check extension host log for console.log messages**:
   ```bash
   grep 'WATCHDOG' ~/.config/Code/logs/*/exthost/exthost.log | tail -20
   ```

2. **Expected output if activate() runs successfully**:
   ```
   [WATCHDOG] activate() function called - extension is loading
   [WATCHDOG] log() call succeeded
   [WATCHDOG] Terminal shown
   [WATCHDOG] All monitors started
   [WATCHDOG] Heartbeat started
   [WATCHDOG] activate() completed successfully
   ```

3. **Expected output if activate() fails**:
   ```
   [WATCHDOG] activate() function called - extension is loading
   [WATCHDOG] ACTIVATION FAILED: <error message>
   ```

4. **Check for output channel**:
   - Open VS Code Output panel (View → Output)
   - Look for "Watchdog Log" in dropdown
   - Should see activation messages

5. **Check for database entries**:
   ```bash
   sqlite3 .augment/error_tracking.db "SELECT COUNT(*) FROM errors WHERE log_file = 'watchdog-extension';"
   ```

---

## FILES MODIFIED

- `hidden-terminal-watchdog/src/extension.ts` - Added try-catch and console.log to activate()
- Recompiled to `hidden-terminal-watchdog/out/extension.js`
- Repackaged to `hidden-terminal-watchdog-1.0.0.vsix`
- Reinstalled extension

---

## NEXT STEPS

1. **Reload VS Code**: Ctrl+Shift+P → "Developer: Reload Window"
2. **Check logs**: Run verification commands above
3. **If successful**: Watchdog will start monitoring and logging to database
4. **If failed**: Error message will show exact failure point

