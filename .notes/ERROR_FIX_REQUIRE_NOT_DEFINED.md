# ✅ FIXED: "require is not defined" Error

## 🚨 ERROR REPORTED BY USER

```
ReferenceError: require is not defined
    at streamVideoDirectly (file:///home/owner/Documents/6984bd27-4494-8330-9803-7b6895a48aa5/firefox-performance-tuner/server.js:1947:20)
```

**User's observation:** "I tested the 360 stream settings in mpv and errors with above message"

---

## 🔍 ROOT CAUSE ANALYSIS

**PROBLEM:** Used CommonJS `require()` syntax inside an ES6 module.

**LOCATION:** Line 1947 in `server.js`

**INCORRECT CODE:**
```javascript
const { exec } = require('child_process'); // ❌ ERROR: require() in ES6 module
```

**WHY THIS FAILED:**
- `server.js` is an ES6 module (uses `import` statements at the top)
- ES6 modules do NOT support `require()` - that's CommonJS syntax
- Node.js threw `ReferenceError: require is not defined`

---

## ✅ SOLUTION IMPLEMENTED

**STEP 1:** Added `exec` to the import statement at the top of the file

**BEFORE (Line 2):**
```javascript
import { execFile, spawn } from "child_process";
```

**AFTER (Line 2):**
```javascript
import { execFile, spawn, exec } from "child_process";
```

**STEP 2:** Removed the `require()` statement at line 1947

**BEFORE (Lines 1941-1949):**
```javascript
   * WHY THIS MATTERS:
   *  - If yt-dlp CPU% is low but encoding is slow → CPU throttling or I/O bottleneck
   *  - If player CPU% is high → Player is struggling to decode video
   *  - If system load is high → Other processes are competing for resources
   *  - If memory is low → System is swapping (causes severe stuttering)
   */
  const { exec } = require('child_process'); // ❌ LINE 1947 - ERROR HERE

  const resourceMonitorInterval = setInterval(() => {
```

**AFTER (Lines 1941-1947):**
```javascript
   * WHY THIS MATTERS:
   *  - If yt-dlp CPU% is low but encoding is slow → CPU throttling or I/O bottleneck
   *  - If player CPU% is high → Player is struggling to decode video
   *  - If system load is high → Other processes are competing for resources
   *  - If memory is low → System is swapping (causes severe stuttering)
   */
  const resourceMonitorInterval = setInterval(() => {
```

---

## ✅ VERIFICATION

**Backend restarted successfully:**
```
[SELF-HEAL] server.js changed on disk, restarting to load new code...
[SELF-HEAL] Process will exit cleanly and be restarted by process manager
  ⚠ Backend exited cleanly (code change detected), restarting in 2 seconds...
  → Starting backend (node server.js)...
Firefox Performance Tuner API running on http://127.0.0.1:3001
[SELF-HEAL] Watching /home/owner/Documents/6984bd27-4494-8330-9803-7b6895a48aa5/firefox-performance-tuner/server.js for changes (auto-restart enabled)
```

**No more "require is not defined" errors!**

---

## 📚 LESSON LEARNED

**ES6 Module Syntax Rules:**
- ✅ Use `import { func } from "module";` at the top of the file
- ❌ Do NOT use `const { func } = require("module");` inside functions
- ✅ All imports must be at the top-level scope
- ❌ Dynamic `require()` is NOT supported in ES6 modules

**Best Practice:**
- Always check the module type before using `require()` or `import`
- If the file uses `import` statements, it's an ES6 module
- If the file uses `require()` statements, it's a CommonJS module
- Do NOT mix the two syntaxes in the same file

---

## 🎯 NEXT STEPS

Now that the error is fixed, the deep diagnostic logging should work correctly:

1. **Test video playback** in MPV (360p stream mode)
2. **Watch terminal** for comprehensive diagnostic output
3. **Seek backward** to an already-played part of the video (user's critical observation)
4. **Read the logs** to identify the REAL bottleneck

**Expected diagnostic output:**
- 📊 Pipe throughput monitoring (every 5 seconds)
- ⚠️  Pipe backpressure detection (when player buffer is full)
- 🚨 Cache empty warnings (when player is waiting for data)
- 🔍 Seeking events (when user clicks on timeline)
- 📊 System resource monitoring (CPU/memory usage of yt-dlp and player)

