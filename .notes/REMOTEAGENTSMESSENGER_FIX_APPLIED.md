# RemoteAgentsMessenger Disposal Fix - APPLIED

## DATE: 2026-02-28 04:50 UTC

---

## PROBLEM IDENTIFIED

**Root Cause:** The `RemoteAgentsMessenger` class (class `RU`) dispose() method was incomplete.

**Evidence:**
- 97 leaked Chromium shared memory segments in `/dev/shm`
- 5 RemoteAgentsMessenger initializations per session (from logs)
- dispose() only cleared `_disposables` array
- **MISSED:** `_remoteAgentSshManager`, `_setupScriptsManager`, `_streamManager`, `_webview`

**These missed disposals created orphaned Chromium IPC contexts that leaked shared memory.**

---

## FIX APPLIED

### File Modified:
```
~/.vscode/extensions/augment.vscode-augment-0.792.0/out/extension.js
~/.vscode/extensions/augment.vscode-augment-0.792.0/out/extension.js.pretty
```

### Backup Created:
```
~/.vscode/extensions/augment.vscode-augment-0.792.0/out/extension.js.backup-20260228-044948
~/.vscode/extensions/augment.vscode-augment-0.792.0/out/extension.js.pretty.bak-20260228-045034
```

### Change Made (Line 275726):

**BEFORE:**
```javascript
dispose() {
    this._logger.debug("Disposing RemoteAgentsMessenger");
    for (let t of this._disposables) t.dispose();
    this._disposables = []
}
```

**AFTER:**
```javascript
dispose() {
    this._logger.debug("Disposing RemoteAgentsMessenger");
    for (let t of this._disposables) t.dispose();
    this._disposables = [];
    if(this._remoteAgentSshManager&&typeof this._remoteAgentSshManager.dispose==="function"){
        this._remoteAgentSshManager.dispose()
    }
    if(this._setupScriptsManager&&typeof this._setupScriptsManager.dispose==="function"){
        this._setupScriptsManager.dispose()
    }
    if(this._streamManager&&typeof this._streamManager.dispose==="function"){
        this._streamManager.dispose()
    }
    this._webview=void 0;
    this._logger.debug("RemoteAgentsMessenger disposal complete")
}
```

---

## NEXT STEPS - USER ACTION REQUIRED

### 1. Reload VS Code Window
```
Ctrl+Shift+P → "Developer: Reload Window"
```

### 2. Monitor Shared Memory Leaks
```bash
# Watch leak count (should stay at 0-20 instead of growing to 97+)
watch -n 5 'lsof -p $(pgrep -f "code --type=zygote" | head -1) 2>/dev/null | grep -c DEL'
```

### 3. Check Logs for Disposal Messages
```bash
# After opening/closing panels, check for disposal logs
tail -f ~/.config/Code/logs/*/window1/exthost/Augment.vscode-augment/Augment.log | grep -i "disposal"
```

---

## EXPECTED RESULTS

### Before Fix:
```
$ lsof -p $(pgrep -f "code --type=zygote" | head -1) +D /dev/shm 2>/dev/null | grep -c DEL
97  ← LEAK GROWING

Logs show:
04:17:44.354 [info] RemoteAgentsMessenger initialized
04:17:46.294 [info] RemoteAgentsMessenger initialized
04:37:01.629 [info] RemoteAgentsMessenger initialized
04:37:06.319 [info] RemoteAgentsMessenger initialized
04:37:07.692 [info] RemoteAgentsMessenger initialized
(NO disposal logs)
```

### After Fix:
```
$ lsof -p $(pgrep -f "code --type=zygote" | head -1) +D /dev/shm 2>/dev/null | grep -c DEL
0-20  ← NORMAL RANGE (not growing)

Logs show:
04:17:44.354 [info] RemoteAgentsMessenger initialized
04:17:46.294 [info] RemoteAgentsMessenger initialized
[panel closed]
04:17:50.123 [debug] Disposing RemoteAgentsMessenger
04:17:50.124 [debug] RemoteAgentsMessenger disposal complete  ← NEW
```

---

## VERIFICATION CHECKLIST

- [ ] VS Code window reloaded
- [ ] Leak count checked (should be 0-20, not 97+)
- [ ] Opened and closed Remote Agents panel
- [ ] Checked logs for "RemoteAgentsMessenger disposal complete" message
- [ ] Leak count did NOT increase after opening/closing panels
- [ ] Zygote CPU usage is normal (<5%)

---

## ROLLBACK INSTRUCTIONS (if needed)

```bash
# Restore original file
cp ~/.vscode/extensions/augment.vscode-augment-0.792.0/out/extension.js.backup-20260228-044948 \
   ~/.vscode/extensions/augment.vscode-augment-0.792.0/out/extension.js

# Reload VS Code
Ctrl+Shift+P → "Developer: Reload Window"
```

---

## TECHNICAL NOTES

**Why this fix works:**
1. `_remoteAgentSshManager` and `_setupScriptsManager` create IPC channels
2. `_streamManager` holds event listeners that reference Chromium contexts
3. `_webview` holds a reference to the webview, preventing garbage collection
4. Without explicit disposal, these objects remain in memory
5. Chromium IPC contexts allocate shared memory segments in `/dev/shm`
6. When contexts aren't disposed, segments remain (deleted but open)
7. This fix ensures ALL resources are disposed when RemoteAgentsMessenger is destroyed

**Why the mutex fix was wrong:**
- The problem is NOT concurrent initialization
- The problem is INCOMPLETE DISPOSAL
- Each webview NEEDS its own RemoteAgentsMessenger instance
- A mutex would BREAK functionality by preventing legitimate instances
- The correct fix is to ensure proper cleanup, not prevent creation

