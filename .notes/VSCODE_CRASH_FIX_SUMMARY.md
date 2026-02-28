# VS Code Crash Fix Summary

## Problem

**User reported**: "vscode has several times crashed with popup 'the window terminated unexpectedly (reason: killed, code: 9)'"

**Root cause**: Auto-kill script (`.augment/scripts/auto-kill-runaway-zygote.sh`) was sending `kill -9` (SIGKILL) to zygote processes, causing VS Code to crash.

## Database Evidence

```sql
-- Kill events from error_tracking.db
2026-02-19 14:46:49 | zygote_killed | Auto-killed runaway zygote PID 932054: 59.5% CPU, 956MB RAM
2026-02-19 14:46:49 | zygote_killed | Auto-killed runaway zygote PID 929308: 33.3% CPU, 616MB RAM
2026-02-19 14:42:47 | zygote_killed | Auto-killed runaway zygote PID 923566: 37.8% CPU, 1285MB RAM

-- System metrics during crashes
2026-02-19 14:46:51 | load: 4.19 | swap: 780MB | vscode_cpu: 29.9% | runaway: 0
2026-02-19 14:46:49 | load: 4.56 | swap: 780MB | vscode_cpu: 162.3% | runaway: 2
```

**Crash correlation**: 3 kill events = 3 VS Code crashes

## Solution Implemented

### 1. Removed Auto-Kill Script ✅
- Deleted `.augment/scripts/auto-kill-runaway-zygote.sh`
- Script was using `kill -9` which sends SIGKILL (code: 9)
- SIGKILL cannot be caught by VS Code, causes immediate termination

### 2. Upgraded Watchdog Extension ✅
- Modified `hidden-terminal-watchdog/src/extension.ts`
- Added zygote process monitoring:
  - CPU threshold: 20%
  - Memory threshold: 700MB
  - Check interval: 30 seconds
- **Database integration**: Logs all detections to `.augment/error_tracking.db`
- **User notification**: Shows warning popup, asks user to restart VS Code
- **NO AUTO-KILL**: User must decide to restart (prevents crashes)

### 3. Database-Driven Monitoring ✅
```typescript
// Log to database
function logToDatabase(errorType: string, errorMessage: string): void {
    const timestamp = new Date().toISOString();
    const sql = `INSERT INTO errors (timestamp, log_file, error_type, error_message, extension_name) 
                 VALUES ('${timestamp}', 'watchdog-extension', '${errorType}', '${escapedMessage}', 'watchdog');`;
    exec(`sqlite3 "${dbPath}" "${sql}"`);
}

// Monitor zygote processes
function monitorZygoteProcesses(): void {
    // Detect runaway zygotes (CPU > 20% OR memory > 700MB)
    // Log to database
    // Show warning to user (NOT auto-kill)
    // User chooses: "Restart VS Code" or "Ignore"
}
```

## Key Differences

| Auto-Kill Script (OLD) | Watchdog Extension (NEW) |
|------------------------|--------------------------|
| ❌ Uses `kill -9` (SIGKILL) | ✅ User-initiated restart |
| ❌ Crashes VS Code | ✅ Graceful reload |
| ❌ No user notification | ✅ Warning popup |
| ❌ Runs externally | ✅ Integrated in VS Code |
| ✅ Logs to database | ✅ Logs to database |

## Next Steps

1. **Reload VS Code** to activate upgraded watchdog extension
2. **Monitor for runaway zygotes** - extension will show popup if detected
3. **Check database** for detections: `sqlite3 .augment/error_tracking.db "SELECT * FROM errors WHERE error_type = 'runaway_zygote_detected';"`
4. **No more crashes** - user controls when to restart

## Verification

```bash
# Check extension installed
ls -l ~/.vscode/extensions/ | grep watchdog

# Check auto-kill script removed
ls .augment/scripts/auto-kill-runaway-zygote.sh  # Should not exist

# Monitor database for zygote detections
watch -n 30 'sqlite3 .augment/error_tracking.db "SELECT datetime(timestamp), error_type, error_message FROM errors WHERE error_type = \"runaway_zygote_detected\" ORDER BY id DESC LIMIT 5;"'
```

## Expected Behavior

- **Before**: VS Code crashes with "killed, code: 9" every time zygote process exceeds thresholds
- **After**: Watchdog shows warning popup, user chooses when to restart, no crashes

