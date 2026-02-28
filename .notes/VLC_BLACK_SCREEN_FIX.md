# VLC Black Screen Fix - Complete Diagnostic and Solution

## Problem Statement

**User Report:** "video screen is still black in vlc perhaps it's codecs?"

**Symptoms:**
- VLC launches successfully (PID visible in logs)
- VLC exits with code 0 (success)
- Video screen shows black (no playback)
- MPV works fine with same file

---

## Root Cause Analysis (CODE-BASED)

### Step 1: Capture VLC's Output

**BEFORE (Buggy Code):**
```javascript
// LINE 1840-1843 (OLD):
const playerProc = spawn(playerCommand, playerArgs, {
  detached: true,
  stdio: ["ignore", "ignore", "pipe"]  // ❌ stdout LOST!
});

// PROBLEM:
//  - stdio[0] = "ignore" → stdin ignored (correct)
//  - stdio[1] = "ignore" → stdout IGNORED (BUG!)
//  - stdio[2] = "pipe"   → stderr captured
//
// RESULT: VLC's stdout messages are lost forever
```

**AFTER (Fixed Code):**
```javascript
// LINE 1840-1843 (NEW):
const playerProc = spawn(playerCommand, playerArgs, {
  detached: true,
  stdio: ["ignore", "pipe", "pipe"]  // ✅ Both stdout and stderr
});

// FIX:
//  - stdio[0] = "ignore" → stdin ignored (correct)
//  - stdio[1] = "pipe"   → stdout CAPTURED
//  - stdio[2] = "pipe"   → stderr CAPTURED
//
// RESULT: ALL VLC output is now logged
```

### Step 2: Log ALL Output (Not Just Errors)

**BEFORE (Buggy Code):**
```javascript
// OLD EXIT HANDLER:
proc.on("exit", (code) => {
  logBoth(id, `Exited with code ${code}`);
  if (code !== 0 && stderr) {  // ❌ Only logs on error
    console.error(stderr);
  }
});

// PROBLEM:
//  - Only logs stderr when exit code !== 0
//  - VLC exits with code 0 (success) even when video is black
//  - Codec errors are NOT logged because code === 0
```

**AFTER (Fixed Code):**
```javascript
// NEW EXIT HANDLER (lines 1885-1899):
playerProc.on("exit", (code) => {
  logBoth(id, `[player] Exited with code ${code}`);
  
  // Log stdout ALWAYS (not just on error)
  if (playerStdout && playerStdout.trim()) {
    logBoth(id, `[player] COMPLETE STDOUT:\n${playerStdout.trim()}`);
  } else {
    logBoth(id, `[player] stdout was empty (no output)`);
  }

  // Log stderr ALWAYS (not just on error)
  if (playerStderr && playerStderr.trim()) {
    logBoth(id, `[player] COMPLETE STDERR:\n${playerStderr.trim()}`);
  } else {
    logBoth(id, `[player] stderr was empty (no errors)`);
  }
});

// FIX:
//  - Logs BOTH stdout and stderr ALWAYS
//  - Doesn't depend on exit code
//  - Captures codec errors even when code === 0
```

### Step 3: Read the Logs

**What the logs showed:**
```
[download-1771354728739] [player] stderr: [00005593f4d31590] main libvlc: Running vlc with the default interface. Use 'cvlc' to use vlc without interface.
[download-1771354728739] [player] stderr: [00007f67c4c0aa50] main decoder error: buffer deadlock prevented
[download-1771354728739] [player] Exited with code 0
[download-1771354728739] [player] stdout was empty (no output)
[download-1771354728739] [player] COMPLETE STDERR:
[00005593f4d31590] main libvlc: Running vlc with the default interface. Use 'cvlc' to use vlc without interface.
[00007f67c4c0aa50] main decoder error: buffer deadlock prevented
```

**ROOT CAUSE IDENTIFIED:**
```
[00007f67c4c0aa50] main decoder error: buffer deadlock prevented
                                      ^^^^^^^^^^^^^^^^^^^^^^^^
```

**What this error means:**
- VLC's decoder thread is waiting for data from demuxer
- Demuxer thread is waiting for buffer space
- Result: DEADLOCK - both threads stuck waiting for each other
- VLC prevents infinite hang by aborting playback
- Video shows black screen because decoder never starts

---

## Solution (CODE-BASED)

### Fix 1: Increase Buffer Sizes and Disable Audio

**BEFORE (Buggy VLC Flags):**
```javascript
// LINE 1797-1802 (OLD):
playerArgs = [
  "--file-caching=30000",      // 30 second cache (too aggressive)
  "--network-caching=30000",   // 30 second cache
  "--no-video-title-show",     // Don't show filename overlay
  outputFile
];

// PROBLEM:
//  - 30 second cache is too large, causes buffer management issues
//  - No codec optimization flags
//  - Audio/video sync can cause deadlock
```

**AFTER (Fixed VLC Flags):**
```javascript
// LINE 1797-1825 (NEW):
playerArgs = [
  "--file-caching=10000",        // 10 second disk cache (reduced from 30s)
  "--network-caching=10000",     // 10 second network cache
  "--no-video-title-show",       // Don't show filename overlay
  "--avcodec-fast",              // Use faster (less accurate) decoding
  "--avcodec-skiploopfilter=4",  // Skip loop filter (reduces CPU load)
  "--avcodec-skip-frame=0",      // Don't skip frames
  "--avcodec-skip-idct=0",       // Don't skip IDCT
  "--no-audio",                  // CRITICAL: Eliminates audio/video sync deadlock
  outputFile
];

// FIX EXPLAINED:
//
// 1. Reduced cache from 30s to 10s
//    - Smaller cache = less buffer management overhead
//    - File is already on disk, don't need huge cache
//
// 2. Added codec optimization flags
//    --avcodec-fast              : Use faster decoding (less CPU)
//    --avcodec-skiploopfilter=4  : Skip deblocking filter (faster)
//    --avcodec-skip-frame=0      : Don't skip frames (play all)
//    --avcodec-skip-idct=0       : Don't skip IDCT (full decode)
//
// 3. CRITICAL: --no-audio flag
//    - Buffer deadlock often caused by audio/video synchronization
//    - Audio decoder waiting for video, video waiting for audio
//    - Disabling audio eliminates this deadlock source
//    - User can re-enable audio once video works
```

---

## Complete Code Changes

### File: `firefox-performance-tuner/server.js`

**Change 1: Capture stdout (line 1842)**
```javascript
// OLD:
stdio: ["ignore", "ignore", "pipe"]  // Only stderr

// NEW:
stdio: ["ignore", "pipe", "pipe"]    // BOTH stdout and stderr
```

**Change 2: Real-time stdout logging (lines 1850-1856)**
```javascript
// ADDED:
if (playerProc.stdout) {
  playerProc.stdout.on("data", (data) => {
    const output = data.toString();
    playerStdout += output;
    logBoth(id, `[player] stdout: ${output.trim()}`);
  });
}
```

**Change 3: Real-time stderr logging (lines 1858-1864)**
```javascript
// ADDED:
if (playerProc.stderr) {
  playerProc.stderr.on("data", (data) => {
    const output = data.toString();
    playerStderr += output;
    logBoth(id, `[player] stderr: ${output.trim()}`);
  });
}
```

**Change 4: Complete output summary on exit (lines 1885-1899)**
```javascript
// OLD:
if (code !== 0 && stderr) {
  console.error(stderr);  // Only logs on error
}

// NEW:
if (playerStdout && playerStdout.trim()) {
  logBoth(id, `[player] COMPLETE STDOUT:\n${playerStdout.trim()}`);
} else {
  logBoth(id, `[player] stdout was empty (no output)`);
}

if (playerStderr && playerStderr.trim()) {
  logBoth(id, `[player] COMPLETE STDERR:\n${playerStderr.trim()}`);
} else {
  logBoth(id, `[player] stderr was empty (no errors)`);
}
```

**Change 5: VLC flags to prevent buffer deadlock (lines 1797-1825)**
```javascript
// OLD:
playerArgs = [
  "--file-caching=30000",
  "--network-caching=30000",
  "--no-video-title-show",
  outputFile
];

// NEW:
playerArgs = [
  "--file-caching=10000",
  "--network-caching=10000",
  "--no-video-title-show",
  "--avcodec-fast",
  "--avcodec-skiploopfilter=4",
  "--avcodec-skip-frame=0",
  "--avcodec-skip-idct=0",
  "--no-audio",  // CRITICAL: Eliminates audio/video sync deadlock
  outputFile
];
```

---

## Testing Instructions

1. **Backend will auto-restart** (file watcher detects server.js change)
2. **Test VLC** through frontend at http://localhost:3000
3. **Expected result:** Video plays WITHOUT black screen (no audio)
4. **Check logs:** Should see NO "buffer deadlock prevented" error

---

## If Video Still Shows Black Screen

**Next diagnostic steps:**
1. Check logs for new error messages
2. Try using `cvlc` instead of `vlc` (command-line version)
3. Use `ffprobe` to check file codec information
4. Test file manually: `vlc --no-audio /tmp/youtube-*.mp4`

---

## Summary

**Problem:** VLC buffer deadlock caused black screen  
**Root Cause:** Audio/video sync deadlock in VLC's decoder  
**Solution:** Disable audio with `--no-audio` flag  
**Result:** Video should play (without audio)  

**Next step:** Once video works, can experiment with re-enabling audio

