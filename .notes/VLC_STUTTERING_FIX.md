# VLC Stuttering Fix - Self-Healing Implementation

## 📊 **PROBLEM: VLC Severe Stuttering (1 frame/5 seconds)**

**User report:** "vlc started faster, but stutters at about 1 frame /5 seconds and controls seem to fail"

**Evidence from terminal logs:**
```
[yt-dlp] Stream #0:0[0x1](und): Video: av1 (libdav1d) (Main) (av01 / 0x31307661), yuv420p(tv, bt709), 7680x4320, 17720 kb/s, 23.98 fps
[yt-dlp] frame=  598 fps= 12 q=-1.0 size=   77970KiB time=00:00:25.06 bitrate=25481.2kbits/s speed=0.5x
[vlc] stderr: [00007f73880011e0] mkv demux error: cannot find any cluster or chapter, damaged file ?
[vlc] stderr: [00007f7390000d00] main input error: ES_OUT_SET_(GROUP_)PCR  is called too late (pts_delay increased to 5609 ms)
[vlc] stderr: [00007f73880018d0] prefetch stream error: reading while paused (buggy demux?)
[vlc] stderr: [000055af4edcf430] main playlist: end of playlist, exiting
Error: write EPIPE
```

**Root causes:**
1. **8K AV1 video (7680x4320)** - VLC cannot decode in realtime
2. **yt-dlp encoding speed 0.5x** - Encoding slower than realtime
3. **VLC demuxer errors** - Buffer underruns, timing errors
4. **EPIPE crash** - Node.js backend crashes when VLC exits

---

## 🛠️ **SELF-HEALING FIXES**

### **Fix 1: Force 1080p H.264 (Prevents 8K AV1 Selection)**

**File:** `firefox-performance-tuner/server.js` (lines 1329-1349)

```javascript
/**
 * SELF-HEALING FORMAT SELECTION:
 *  - Limit to 1080p max (prevents 8K/4K that VLC cannot decode in realtime)
 *  - Prefer H.264 (avc) over AV1 (less CPU-intensive)
 *  - Fallback to best available if no H.264 1080p exists
 */
const ytdlpProc = spawn("yt-dlp", [
  "-f", "bestvideo[height<=1080][vcodec^=avc]+bestaudio/bestvideo[height<=1080]+bestaudio/best[height<=1080]/best",
  // FORMAT SELECTION BREAKDOWN:
  //  1. bestvideo[height<=1080][vcodec^=avc]+bestaudio  → 1080p H.264 + best audio (PREFERRED)
  //  2. bestvideo[height<=1080]+bestaudio               → 1080p any codec + best audio (FALLBACK 1)
  //  3. best[height<=1080]                              → 1080p single stream (FALLBACK 2)
  //  4. best                                            → Best available (FALLBACK 3)
  "-o", "-",
  "--no-part",
  url
], {
  stdio: ["ignore", "pipe", "pipe"]
});
```

**Why this works:**
- 8K AV1 requires ~17720 kb/s bitrate → VLC cannot decode in realtime
- 1080p H.264 requires ~5000 kb/s bitrate → VLC can decode smoothly
- H.264 is hardware-accelerated, AV1 is software-only (CPU-intensive)

### **Fix 2: Increase VLC Buffer (60 seconds)**

**File:** `firefox-performance-tuner/server.js` (lines 1454-1472)

```javascript
/**
 * SELF-HEALING BUFFER STRATEGY (prevents stuttering on slow encoding):
 *  - --file-caching=5000 (5 seconds) → Balance between fast start and buffer safety
 *  - --network-caching=60000 (60 seconds) → LARGE buffer prevents stuttering when yt-dlp encoding is slow
 *  - Rationale: yt-dlp often encodes at 0.5x speed (slower than realtime), VLC needs large buffer
 */
playerFlags = [
  "--file-caching=5000",         // 5 seconds cache for stdin
  "--network-caching=60000",     // 60 seconds cache for network
  "--no-audio-time-stretch",
  "--no-video-title-show",
  "--play-and-exit",
  "-"
];
```

**Why this works:**
- yt-dlp encoding at 0.5x speed means VLC receives data slower than playback rate
- 60-second buffer gives VLC enough data to play smoothly even when yt-dlp is slow

### **Fix 3: EPIPE Error Handler (Prevents Crash)**

**File:** `firefox-performance-tuner/server.js` (lines 1523-1552)

```javascript
/**
 * SELF-HEALING EPIPE ERROR HANDLING:
 *  - When player exits, it closes stdin pipe
 *  - yt-dlp may still be writing → EPIPE error
 *  - Without error handler, Node.js crashes with "Unhandled 'error' event"
 *  - With error handler, gracefully stop yt-dlp and log the event
 */
ytdlpProc.stdout.on('error', (err) => {
  if (err.code === 'EPIPE') {
    logBoth(downloadId, `⚠️  Player closed stdin pipe (EPIPE), stopping yt-dlp gracefully`);
    if (ytdlpProc && !ytdlpProc.killed) {
      ytdlpProc.kill('SIGTERM');  // Gracefully stop yt-dlp
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
```

**Why this works:**
- VLC exits when user closes window or video finishes
- Without error handler, Node.js crashes with "Unhandled 'error' event"
- With error handler, backend logs the event and continues running

---

## 📋 **TESTING INSTRUCTIONS**

**What you must do:**
1. Backend should auto-restart (if not, manually restart with Ctrl+C and `npm run dev`)
2. Open http://localhost:3000
3. Navigate to "External Video Player Fallback" section
4. Paste YouTube URL: `https://www.youtube.com/watch?v=-kB-BGMXxZc`
5. Select **VLC** player
6. Click **"Play in VLC"**

**Expected results:**
- ✅ VLC opens within 5-10 seconds
- ✅ Video plays smoothly (1080p H.264 instead of 8K AV1)
- ✅ Controls work properly
- ✅ No EPIPE errors in backend
- ✅ Backend does NOT crash when VLC exits

**Log messages to verify:**
```
[download-stream-XXXXX] yt-dlp spawned with PID XXXXX (streaming to stdout, max 1080p H.264)
[download-stream-XXXXX] Using VLC-specific streaming flags (SELF-HEALING: 5s file cache, 60s network cache, VLC 3.x compatible)
[download-stream-XXXXX] ✅ Streaming pipeline connected: yt-dlp stdout → vlc stdin
```

---

## 🎯 **SELF-HEALING FEATURES**

1. **Automatic resolution limiting** - Prevents 8K/4K selection
2. **Codec preference** - Prefers H.264 over AV1
3. **Adaptive buffering** - Large buffer handles slow encoding
4. **Graceful error handling** - EPIPE errors don't crash backend
5. **Comprehensive logging** - All events logged

---

## 📚 **REFERENCES**

- **VLC caching:** https://wiki.videolan.org/VLC_command-line_help/
- **yt-dlp format selection:** https://github.com/yt-dlp/yt-dlp#format-selection
- **Node.js stream errors:** https://nodejs.org/api/stream.html#event-error
- **AV1 vs H.264:** https://en.wikipedia.org/wiki/AV1#Performance

