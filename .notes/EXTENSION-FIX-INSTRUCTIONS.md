# EXTENSION.JS FIX INSTRUCTIONS

## File Location
```
~/.vscode/extensions/augment.vscode-augment-0.792.0/out/extension.js.pretty
```

**File is already open in VS Code** (you opened it earlier)

---

## ROOT CAUSE (Forensic Evidence)

From `.notes/699eec25-5120-832b-9948-5e142d18cd90_0127.txt`:

1. **106-117 leaked Chromium shared memory segments** in zygote PID 3552611
2. **0 AbortErrors** (async iterator fix is working)
3. **RemoteAgentsMessenger initialized 5 times** in rapid succession (10:48:19, 10:48:21, 10:48:22, 10:48:26, 10:48:31)
4. **strace shows mmap on FDs 41,42,43,44** creating shared memory segments
5. **Leak is NOT from async iterators** - it's from Chromium IPC context creation

**DEFINITIVE CAUSE:**
- `updateStatusTrace()` fires multiple times simultaneously (no mutex)
- Completion requests overlap (no queue)
- Webview messages fire rapidly (no debouncing)
- Each overlapping operation creates new Chromium IPC contexts
- IPC contexts leak shared memory when destroyed

---

## THREE FIXES REQUIRED

### FIX 1: Add Mutex to `updateStatusTrace()` (Line ~300033 and ~302773)

**Current code:**
```javascript
async updateStatusTrace(r) {
    // ...existing code...
}
```

**Fixed code:**
```javascript
// Add property at class level:
_statusTraceLock = false;

async updateStatusTrace(r) {
    if (this._statusTraceLock) return; // skip if previous update in progress
    this._statusTraceLock = true;
    
    try {
        // ...existing code...
    } finally {
        this._statusTraceLock = false;
    }
}
```

---

### FIX 2: Add Queue to Completion Requests

**Search for:** `_apiServer.complete`

**Current code:**
```javascript
let u = await this._apiServer.complete(c, "prefix", "suffix", ...);
```

**Fixed code:**
```javascript
// Add property at class level:
_completionInFlight = null;

async runCompletion(c) {
    if (this._completionInFlight) return; // skip overlapping
    this._completionInFlight = this._apiServer.complete(c, ...);
    try {
        return await this._completionInFlight;
    } finally {
        this._completionInFlight = null;
    }
}
```

---

### FIX 3: Add Debouncing to Webview Messages

**Search for:** `_nextEditVSCodeToWebviewMessage.fire`

**Current code:**
```javascript
this._nextEditVSCodeToWebviewMessage.fire(message);
```

**Fixed code:**
```javascript
// Add property at class level:
_fireDebounced = undefined;

fireMessage(message) {
    if (this._fireDebounced) clearTimeout(this._fireDebounced);
    this._fireDebounced = setTimeout(() => {
        this._nextEditVSCodeToWebviewMessage.fire(message);
    }, 50); // 50ms debounce
}
```

---

## VERIFICATION

After applying fixes:

1. **Reload VS Code window** (Ctrl+Shift+P → "Developer: Reload Window")
2. **Monitor zygote:** `watch -n 5 'ps aux | grep zygote'`
3. **Monitor shared memory:** `watch -n 5 'lsof -p $(pgrep -f "code --type=zygote" | head -1) 2>/dev/null | grep -c DEL'`
4. **Check Augment logs:** `tail -f ~/.config/Code/logs/*/window1/exthost/Augment.vscode-augment/Augment.log`

**Expected results:**
- Shared memory leak count should stabilize (not grow)
- RemoteAgentsMessenger should initialize only ONCE per session
- No "Cancelled by user" errors

---

## BACKUP

Before editing, backup was created at:
```
~/.vscode/extensions/augment.vscode-augment-0.792.0/out/extension.js.backup-TIMESTAMP
```

To restore:
```bash
cp ~/.vscode/extensions/augment.vscode-augment-0.792.0/out/extension.js.backup-* \
   ~/.vscode/extensions/augment.vscode-augment-0.792.0/out/extension.js
```

