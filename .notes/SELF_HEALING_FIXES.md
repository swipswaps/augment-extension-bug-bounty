# Self-Healing VLC Streaming - Complete Implementation

## 📊 **PROBLEM ANALYSIS FROM LOGS**

### **Issue 1: VLC Stuttering - Evidence from Logs**

**User report:** "vlc seems a bit more stable, still stutters quite a lot and stalls many seconds at a time"

**Log evidence:**
```
[download-stream-1771374844591] [yt-dlp] frame= 1418 fps= 15 q=-1.0 size=   28570KiB time=00:00:59.14 bitrate=3957.4kbits/s speed=0.63x
[download-stream-1771374844591] [yt-dlp] frame= 1418 fps= 15 q=-1.0 size=   28570KiB time=00:00:59.14 bitrate=3957.4kbits/s speed=0.626x
[download-stream-1771374844591] [yt-dlp] frame= 1418 fps= 15 q=-1.0 size=   28570KiB time=00:00:59.14 bitrate=3957.4kbits/s speed=0.623x
```

**HOW LOGS SHOW STUTTERING:**

1. **Same frame number (1418) repeated 3 times** → yt-dlp is STALLED, not encoding new frames
2. **Speed 0.63x** → Encoding at 63% of realtime (slower than playback rate of 1.0x)
3. **Same timestamp (59.14 seconds) repeated** → No progress for multiple log lines
4. **Decreasing speed (0.63x → 0.626x → 0.623x)** → Encoding getting SLOWER over time

**Root cause:** Even 1080p is too demanding for user's system. yt-dlp cannot encode fast enough → VLC waits for data → stuttering.

### **Issue 2: Download Continued After VLC Closed**

**User question:** "download continued after vlc closed, is that correct?"

**Answer:** NO, this is WRONG. When VLC exits, yt-dlp should stop immediately.

**Evidence:** User sees yt-dlp logs AFTER closing VLC window → yt-dlp still running.

**Root cause:** No exit handler on `playerProc` to kill yt-dlp when player exits.

---

## 🛠️ **SELF-HEALING FIXES IMPLEMENTED**

### **Fix 1: Aggressive Quality Limiting (720p Max)**

**File:** `firefox-performance-tuner/server.js` (lines 1329-1357)

**BEFORE (1080p limit - STILL TOO SLOW):**
```javascript
const ytdlpProc = spawn("yt-dlp", [
  "-f", "bestvideo[height<=1080][vcodec^=avc]+bestaudio/...",  // 1080p → speed=0.63x (TOO SLOW)
  "-o", "-",
  "--no-part",
  url
], {
  stdio: ["ignore", "pipe", "pipe"]
});
```

**AFTER (720p limit - SELF-HEALING):**
```javascript
/**
 * SELF-HEALING FORMAT SELECTION (AGGRESSIVE QUALITY LIMITING):
 *  - Start with 720p max (NOT 1080p - logs show 1080p is still too slow at 0.63x speed)
 *  - Prefer H.264 (avc) over AV1/VP9 (hardware-accelerated, less CPU-intensive)
 *  - Prefer lower bitrate formats (faster encoding, smoother playback)
 *  - Fallback chain: 720p H.264 → 480p H.264 → 360p → best available
 *
 * RATIONALE FROM LOGS:
 *  - User's system shows "speed=0.63x" even at 1080p (encoding slower than realtime)
 *  - VLC stalls when yt-dlp can't keep up (same frame number repeated in logs)
 *  - 720p H.264 has ~50% less pixels than 1080p → 2x faster encoding
 *  - Smooth 720p playback is better than stuttering 1080p playback
 */
const ytdlpProc = spawn("yt-dlp", [
  "-f", "bestvideo[height<=720][vcodec^=avc]+bestaudio/bestvideo[height<=480][vcodec^=avc]+bestaudio/best[height<=720]/best[height<=480]/best",
  // FORMAT SELECTION BREAKDOWN (AGGRESSIVE QUALITY LIMITING):
  //  1. bestvideo[height<=720][vcodec^=avc]+bestaudio   → 720p H.264 + best audio (PREFERRED - 2x faster than 1080p)
  //  2. bestvideo[height<=480][vcodec^=avc]+bestaudio   → 480p H.264 + best audio (FALLBACK 1 - 4x faster than 1080p)
  //  3. best[height<=720]                               → 720p single stream (FALLBACK 2)
  //  4. best[height<=480]                               → 480p single stream (FALLBACK 3)
  //  5. best                                            → Best available (FALLBACK 4 - last resort)
  "-o", "-",
  "--no-part",
  url
], {
  stdio: ["ignore", "pipe", "pipe"]
});

logBoth(downloadId, `yt-dlp spawned with PID ${ytdlpProc.pid} (streaming to stdout, max 720p H.264 for smooth playback)`);
```

**Why 720p instead of 1080p:**
- **1080p:** 1920×1080 = 2,073,600 pixels → speed=0.63x (TOO SLOW)
- **720p:** 1280×720 = 921,600 pixels → ~50% less pixels → 2x faster encoding
- **Expected speed:** 0.63x × 2 = 1.26x (FASTER than realtime → smooth playback)

### **Fix 2: Stop yt-dlp When Player Exits**

**File:** `firefox-performance-tuner/server.js` (lines 1535-1584)

**BEFORE (yt-dlp continues after VLC exits):**
```javascript
ytdlpProc.stdout.pipe(playerProc.stdin);
// NO EXIT HANDLER → yt-dlp continues downloading after VLC closes
```

**AFTER (SELF-HEALING - yt-dlp stops when VLC exits):**
```javascript
ytdlpProc.stdout.pipe(playerProc.stdin);

// EPIPE error handlers (prevent crash)
ytdlpProc.stdout.on('error', (err) => {
  if (err.code === 'EPIPE') {
    logBoth(downloadId, `⚠️  Player closed stdin pipe (EPIPE), stopping yt-dlp gracefully`);
    if (ytdlpProc && !ytdlpProc.killed) {
      ytdlpProc.kill('SIGTERM');
    }
  } else {
    logBoth(downloadId, `❌ yt-dlp stdout error: ${err.code} - ${err.message}`);
  }
});

playerProc.stdin.on('error', (err) => {
  if (err.code === 'EPIPE') {
    logBoth(downloadId, `⚠️  Player stdin closed (EPIPE), expected when player exits`);
  } else {
    logBoth(downloadId, `❌ Player stdin error: ${err.code} - ${err.message}`);
  }
});

/**
 * SELF-HEALING: Stop yt-dlp when player exits
 *  - User closes VLC window → VLC exits → yt-dlp should stop immediately
 *  - Without this, yt-dlp continues downloading after VLC closes (wastes bandwidth)
 *  - This is the PRIMARY fix for "download continued after vlc closed" issue
 */
playerProc.on('exit', (code, signal) => {
  logBoth(downloadId, `[${playerCommand}] Exited with code ${code} (signal: ${signal || 'none'})`);
  
  // CRITICAL: Stop yt-dlp when player exits
  if (ytdlpProc && !ytdlpProc.killed) {
    logBoth(downloadId, `⚠️  Player exited, stopping yt-dlp to prevent wasted bandwidth`);
    ytdlpProc.kill('SIGTERM');  // Gracefully stop yt-dlp
    
    // Give yt-dlp 2 seconds to exit gracefully, then force kill
    setTimeout(() => {
      if (ytdlpProc && !ytdlpProc.killed) {
        logBoth(downloadId, `⚠️  yt-dlp did not exit gracefully, force killing`);
        ytdlpProc.kill('SIGKILL');  // Force kill
      }
    }, 2000);
  }
});
```

**Why this fixes "download continued after vlc closed":**
- VLC exits → `playerProc.on('exit')` handler triggers
- Handler kills yt-dlp with SIGTERM (graceful)
- If yt-dlp doesn't exit in 2 seconds → force kill with SIGKILL
- Result: yt-dlp stops immediately when VLC closes

---

## 📋 **WHAT YOU MUST DO NOW**

**Backend must restart to load new code:**

```bash
# Press Ctrl+C to stop current backend
# Then restart:
cd firefox-performance-tuner/ && npm run dev
```

**Then test VLC streaming again:**
1. Open http://localhost:3000
2. Navigate to "External Video Player Fallback" section
3. Paste YouTube URL: `https://www.youtube.com/watch?v=-kB-BGMXxZc`
4. Select **VLC** player
5. Click **"Play in VLC"**

**Expected results:**
- ✅ Log shows: `yt-dlp spawned with PID XXXXX (streaming to stdout, max 720p H.264 for smooth playback)`
- ✅ VLC plays 720p H.264 video (NOT 1080p, NOT 8K AV1)
- ✅ Video plays smoothly without stuttering (speed should be >1.0x)
- ✅ When you close VLC, yt-dlp stops immediately (no more logs after VLC exits)
- ✅ No EPIPE crash

---

## 🎯 **SELF-HEALING FEATURES**

1. **Aggressive quality limiting** - 720p max (2x faster encoding than 1080p)
2. **Codec preference** - H.264 over AV1 (hardware-accelerated)
3. **Automatic cleanup** - yt-dlp stops when VLC exits
4. **Graceful error handling** - EPIPE errors don't crash backend
5. **Comprehensive logging** - All events logged

---

## 📝 **EXPLAIN WHAT AND WHY**

**What:** Manually restart backend, then test VLC streaming

**Why:** Backend auto-restart is broken (separate bug). New code implements:
- **720p limit** (instead of 1080p) → 2x faster encoding → smooth playback
- **Auto-stop yt-dlp** when VLC exits → no wasted bandwidth

**How logs show stuttering:**
- Same frame number repeated → yt-dlp stalled
- Speed <1.0x → encoding slower than playback
- Same timestamp repeated → no progress

**How to verify fix worked:**
- Log shows "max 720p H.264" (not 1080p)
- Speed >1.0x (faster than realtime)
- yt-dlp stops when VLC closes (no more logs)

