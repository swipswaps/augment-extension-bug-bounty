# FILE DESCRIPTOR LEAK FIX STRATEGY

**Date**: 2026-02-22  
**Status**: ACTIVE LEAK (55,573 FDs as of 18:10:48)  
**Root Cause**: AbortError from getRemoteAgentOverviewsStream leaves file descriptors open

---

## PROBLEM ANALYSIS

### Current FD Count
```
2026-02-22T18:10:48 - 55,159 FDs (threshold: 50,000)
2026-02-22T18:09:52 - 55,573 FDs (threshold: 50,000)
2026-02-22T18:08:46 - 54,718 FDs (threshold: 50,000)
```

**Leak rate**: ~400-800 FDs per minute during active periods

### Root Causes (from database analysis)

1. **AbortError from getRemoteAgentOverviewsStream**: 803 occurrences
   - Call chain: `d2@64:59334 → callApiStream@250:8939 → callApiStream@252:479212 → getRemoteAgentOverviewsStream@252:493`
   - Repeats every ~60 seconds
   - Each AbortError leaves file descriptors open

2. **Chat input completion API**: 30 "Request cancelled" errors
   - Already disabled via `augment.completions.enableChatInputCompletions = false`
   - But FD leak persists after disabling

3. **File descriptor types leaking**:
   - **REG** (regular files) - file watcher leak
   - **unix** (Unix domain sockets) - IPC socket leak
   - **pipe** (pipes) - subprocess leak

---

## FIX STRATEGY

### Fix #1: Add Aggressive FD Cleanup to Watchdog

**What**: Periodically close leaked file descriptors
**Why**: Extension code is leaking FDs; we can't fix minified extension.js directly
**How**: Use `lsof` to identify leaked FDs and close them

**Implementation**:
```bash
#!/bin/bash
# .augment/scripts/cleanup-leaked-fds.sh

# Find all VS Code processes with excessive FDs
lsof -n 2>/dev/null | grep code | awk '{print $2}' | sort | uniq -c | sort -rn | while read count pid; do
    if [ "$count" -gt 1000 ]; then
        echo "[FD CLEANUP] Process $pid has $count FDs, investigating..."
        
        # Find leaked file descriptors (pipes, sockets that are not connected)
        lsof -p $pid 2>/dev/null | grep -E "(pipe|unix|sock)" | awk '{print $4}' | sed 's/[urw]$//' | while read fd; do
            # Close the FD (requires gdb or /proc manipulation)
            echo "[FD CLEANUP] Would close FD $fd in PID $pid"
        done
    fi
done
```

### Fix #2: Disable Remote Agent Overview Polling

**What**: Stop the background polling that's causing AbortErrors
**Why**: 803 AbortErrors indicate this feature is broken
**How**: Add VS Code setting to disable remote agent polling

**Implementation**:
```json
// settings.json
{
  "augment.remoteAgents.enableBackgroundPolling": false
}
```

### Fix #3: Add Circuit Breaker to Extension (Requires Source Code)

**What**: Stop retrying after N consecutive failures
**Why**: Extension retries indefinitely, amplifying the leak
**How**: Modify extension source to add exponential backoff

**Pseudocode** (for Augment team):
```typescript
class RemoteAgentStreamManager {
    private consecutiveFailures = 0;
    private readonly MAX_FAILURES = 5;
    private backoffMs = 1000;
    
    async getRemoteAgentOverviewsStream() {
        if (this.consecutiveFailures >= this.MAX_FAILURES) {
            console.warn(`Circuit breaker open: ${this.consecutiveFailures} consecutive failures`);
            return;
        }
        
        try {
            const result = await this.callApiStream();
            this.consecutiveFailures = 0;  // Reset on success
            this.backoffMs = 1000;
            return result;
        } catch (error) {
            this.consecutiveFailures++;
            this.backoffMs = Math.min(this.backoffMs * 2, 60000);  // Max 60s
            
            console.error(`Stream failed (${this.consecutiveFailures}/${this.MAX_FAILURES}), backing off ${this.backoffMs}ms`);
            
            // CRITICAL: Clean up file descriptors on error
            if (error.signal) {
                error.signal.removeEventListener('abort', this.cleanup);
            }
            
            throw error;
        }
    }
}
```

### Fix #4: Immediate Workaround - Restart VS Code Periodically

**What**: Automated VS Code window reload every 4 hours
**Why**: Reloading clears all leaked FDs
**How**: Watchdog triggers reload when FD count > 55,000

**Implementation**:
```typescript
// Add to hidden-terminal-watchdog/src/extension.ts
if (fdCount > 55000) {
    vscode.window.showWarningMessage(
        `File descriptor leak detected (${fdCount} FDs). Reload VS Code to prevent system instability.`,
        'Reload Now',
        'Remind Me Later'
    ).then(selection => {
        if (selection === 'Reload Now') {
            vscode.commands.executeCommand('workbench.action.reloadWindow');
        }
    });
}
```

---

## IMMEDIATE ACTION PLAN

1. ✅ **Document the leak** (this file)
2. ⏳ **Add FD cleanup to watchdog** (Fix #4 - immediate)
3. ⏳ **Create bug report for Augment team** (Fix #3 - requires source code access)
4. ⏳ **Test disabling remote agent polling** (Fix #2 - user can test)
5. ⏳ **Monitor FD count after fixes** (verify effectiveness)

---

## TESTING PLAN

### Test 1: Disable Remote Agent Polling
```bash
# Add to VS Code settings.json
echo '{"augment.remoteAgents.enableBackgroundPolling": false}' >> ~/.config/Code/User/settings.json

# Monitor FD count for 1 hour
watch -n 60 'lsof 2>/dev/null | grep -c code'
```

### Test 2: Verify Watchdog Auto-Reload
```bash
# Manually set FD count high (for testing)
# Watchdog should trigger reload prompt

# Check watchdog logs
tail -f ~/.vscode/extensions/hidden-terminal-watchdog-*/out/watchdog.log
```

---

## SUCCESS CRITERIA

- ✅ FD count stays below 50,000 for 24 hours
- ✅ No AbortError occurrences for 24 hours
- ✅ No runaway zygote processes for 24 hours
- ✅ No cancellation latch triggers for 24 hours

---

## NOTES FOR AUGMENT TEAM

**Bug Report Summary**:
- **Issue**: getRemoteAgentOverviewsStream leaks file descriptors on AbortError
- **Frequency**: 803 occurrences, repeats every ~60 seconds
- **Impact**: System instability, runaway zygotes, cancellation latch triggers
- **Fix**: Add proper cleanup in catch block + circuit breaker pattern
- **Location**: extension.js lines 64:59334, 250:8939, 252:479212, 252:493

**Recommended Fix** (for extension source code):
```typescript
// In getRemoteAgentOverviewsStream method
try {
    const controller = new AbortController();
    const response = await fetch(url, { signal: controller.signal });
    // ... process stream
} catch (error) {
    // CRITICAL: Clean up resources on error
    if (controller) {
        controller.abort();  // Ensure signal is aborted
    }
    // Close any open streams
    if (response && response.body) {
        await response.body.cancel();  // Close ReadableStream
    }
    throw error;
} finally {
    // Always clean up, even on success
    // ... cleanup code
}
```

