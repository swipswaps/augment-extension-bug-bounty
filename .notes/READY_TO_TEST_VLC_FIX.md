# ✅ READY TO TEST: VLC Streaming Fix

## 🎯 **WHAT WAS FIXED**

### **Problem:**
```
[vlc] stderr: vlc: unknown option or missing mandatory argument `--cache=yes'
[vlc] Exited with code 1
```

### **Root Cause:**
- Streaming pipeline used **MPV-specific flags** (`--cache=yes`, `--demuxer-max-bytes`, etc.)
- VLC has **completely different command-line syntax**
- VLC doesn't recognize MPV flags → immediate exit

### **Solution:**
- Added **player detection logic** (VLC vs MPV vs unknown)
- VLC now gets **VLC-specific flags** (`--file-caching`, `--network-caching`, etc.)
- MPV still gets **MPV-specific flags** (unchanged)
- Comprehensive logging shows which flags are being used

---

## 📋 **CHANGES MADE**

### **File:** `firefox-performance-tuner/server.js`
### **Function:** `streamVideoDirectly(url, downloadId, playerCommand)`
### **Lines:** 1305-1428

**Key Changes:**
1. Added player detection: `const isVLC = playerCommand.toLowerCase().includes("vlc")`
2. VLC flags: `--file-caching=10000`, `--network-caching=10000`, `--no-audio-time-stretch`, `--no-video-title-show`, `--play-and-exit`, `-`
3. MPV flags: (unchanged) `--cache=yes`, `--demuxer-max-bytes=100M`, etc.
4. Logging: Shows which player type detected and which flags used

---

## 🧪 **HOW TO TEST**

### **Step 1: Verify Backend Restarted**
✅ **CONFIRMED** - Backend auto-restarted twice (visible in terminal output)
```
[SELF-HEAL] server.js changed on disk, restarting to load new code...
Firefox Performance Tuner API running on http://127.0.0.1:3001
```

### **Step 2: Test VLC Streaming**
1. Open frontend: http://localhost:3000
2. Navigate to "External Video Player Fallback" section
3. Paste YouTube URL: `https://www.youtube.com/watch?v=dQw4w9WgXcQ`
4. Select **VLC** player
5. Click "Play in VLC"

### **Step 3: Check Logs**
**Expected VLC logs:**
```
[download-stream-XXXXX] ═══════════════════════════════════════════════════════
[download-stream-XXXXX] STREAMING PIPELINE MODE (No temp file, instant playback)
[download-stream-XXXXX] ═══════════════════════════════════════════════════════
[download-stream-XXXXX] yt-dlp spawned with PID XXXXX (streaming to stdout)
[download-stream-XXXXX] Using VLC-specific streaming flags (--file-caching, --network-caching)
[download-stream-XXXXX] vlc spawned with PID XXXXX (reading from stdin)
[download-stream-XXXXX] ✅ Streaming pipeline connected: yt-dlp stdout → vlc stdin
[download-stream-XXXXX] [vlc] VLC media player 3.0.23 Vetinari
[download-stream-XXXXX] [vlc] Playing: -
[download-stream-XXXXX] [yt-dlp] [download]  23.4% of 12.34MiB at 1.23MiB/s ETA 00:10
[download-stream-XXXXX] [yt-dlp] [download] 100.0% of 12.34MiB at 3.45MiB/s
[download-stream-XXXXX] [yt-dlp] Exited with code 0
[download-stream-XXXXX] [vlc] Exited with code 0
```

**Key indicators of success:**
- ✅ "Using VLC-specific streaming flags" message
- ✅ NO "unknown option" error
- ✅ VLC window opens
- ✅ Video plays smoothly

---

## 🚨 **KNOWN ISSUE: YouTube 403 Forbidden**

**Separate issue from VLC flags:**
```
[yt-dlp] [https @ 0x56218a1a9540] HTTP error 403 Forbidden
[yt-dlp] ERROR: ffmpeg exited with code 8
```

**This is NOT related to VLC flags fix.**

**Possible causes:**
1. YouTube rate limiting
2. yt-dlp version too old (2025.10.22 is 90+ days old)
3. YouTube changed API/authentication
4. IP address blocked by YouTube

**Recommended fix:**
```bash
# Update yt-dlp to latest version:
pip install --upgrade yt-dlp

# Or if installed via package manager:
sudo dnf upgrade yt-dlp  # Fedora
sudo apt upgrade yt-dlp  # Ubuntu/Debian
```

---

## 📊 **VLC vs MPV FLAGS COMPARISON**

| Feature | VLC Flag | MPV Flag |
|---------|----------|----------|
| Cache Duration | `--file-caching=10000` (10 sec) | `--cache-secs=20` (20 sec) |
| Network Cache | `--network-caching=10000` | N/A |
| Demuxer Buffer | N/A | `--demuxer-max-bytes=100M` |
| Read-Ahead | N/A | `--demuxer-readahead-secs=30` |
| Low Latency | N/A | `--profile=low-latency` |
| Audio Stretch | `--no-audio-time-stretch` | N/A |
| Title Overlay | `--no-video-title-show` | N/A |
| Auto Exit | `--play-and-exit` | N/A |
| Terminal Output | N/A | `--no-terminal` |
| Stdin Input | `-` | `-` |

---

## 🎓 **KEY LEARNINGS**

1. **VLC uses milliseconds** (`--file-caching=10000` = 10 seconds)
2. **MPV uses seconds** (`--cache-secs=20` = 20 seconds)
3. **VLC doesn't support demuxer flags** (uses internal demuxer)
4. **MPV has more granular control** (demuxer buffer, read-ahead, profiles)
5. **Both support stdin streaming** (the `-` flag)

---

## 📚 **DOCUMENTATION CREATED**

1. `.notes/VLC_VS_MPV_STREAMING_FLAGS_FIX.md` - Comprehensive fix documentation
2. `.notes/READY_TO_TEST_VLC_FIX.md` - This file (testing instructions)

---

## ✅ **NEXT STEPS**

1. **Test VLC streaming** (follow Step 2 above)
2. **Verify logs** (should see "Using VLC-specific streaming flags")
3. **If YouTube 403 error persists** → Update yt-dlp
4. **If VLC still fails** → Check `/tmp/vlc-debug.log` for detailed errors

---

## 🔧 **ROLLBACK (If Needed)**

If the fix causes issues, the old code can be restored from git:
```bash
cd firefox-performance-tuner
git diff server.js  # See changes
git checkout server.js  # Restore old version
```

Backend will auto-restart and load the old code.

