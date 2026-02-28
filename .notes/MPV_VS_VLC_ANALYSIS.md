# MPV vs VLC - Why MPV Works and VLC Doesn't

## 🔍 Critical Finding from Latest Test

**VLC with NEW flags STILL fails:**
```
[download-1771358239310] Executing player: vlc --file-caching=10000 --network-caching=10000 --no-audio-time-stretch --audio-desync=0 --no-video-title-show /tmp/youtube-1771358239310.mp4
[download-1771358239310] [player] stderr: [00007fa2e8c055f0] main decoder error: buffer deadlock prevented
```

**Result:** Black screen persists even with 10-second cache and disabled A/V sync

---

## 💡 Key Difference: MPV vs VLC

### MPV Flags (WORKS)
```javascript
playerArgs = [
  "--cache=yes",
  "--demuxer-max-bytes=50M",
  "--demuxer-readahead-secs=20",
  "--no-terminal",
  outputFile
];
```

### VLC Flags (FAILS)
```javascript
playerArgs = [
  "--file-caching=10000",
  "--network-caching=10000",
  "--no-audio-time-stretch",
  "--audio-desync=0",
  "--no-video-title-show",
  outputFile
];
```

---

## 🎯 Root Cause: VLC's FAAD Decoder is Fundamentally Broken

**Evidence:**
1. ✅ File is valid MP4 with faststart (plays in MPV)
2. ✅ Both H.264 and AAC codecs present
3. ✅ Buffering completes successfully
4. ❌ FAAD returns "decoded zero sample" on first frame
5. ❌ 10-second cache doesn't help
6. ❌ Disabling A/V sync doesn't help
7. ❌ **Buffer deadlock STILL occurs**

**Conclusion:** The issue is NOT cache size, NOT A/V sync, NOT file format.  
**The issue IS:** VLC's FAAD decoder cannot decode the first AAC frame from yt-dlp files.

---

## 🔧 Why MPV Works

**MPV uses FFmpeg's AAC decoder (libavcodec), NOT FAAD:**
- MPV: `--demuxer-max-bytes=50M` → FFmpeg handles demuxing + decoding
- VLC: Uses internal FAAD decoder → fails on first frame

**MPV's approach:**
1. Demuxer reads 50MB of file into buffer
2. FFmpeg's AAC decoder processes audio
3. No "decoded zero sample" error
4. Video plays successfully

**VLC's approach:**
1. Demuxer reads file
2. FAAD decoder tries to decode first AAC frame
3. FAAD returns ZERO samples (initialization failure)
4. VLC waits 762ms → timeout → black screen

---

## 💊 Solution: Force VLC to Use FFmpeg AAC Decoder

**VLC has TWO AAC decoders:**
1. **FAAD** (default, broken for yt-dlp files)
2. **avcodec** (FFmpeg's AAC decoder, same as MPV)

**We need to DISABLE FAAD and FORCE avcodec.**

---

## 📚 Research Findings

**From VLC compilation flags (verbose log):**
```
'--enable-faad'      ← FAAD enabled
'--enable-avcodec'   ← avcodec (FFmpeg) also enabled
```

**VLC has BOTH decoders, but prefers FAAD by default.**

**Solution:** Use `cvlc` (command-line VLC) with specific decoder selection.

---

## 🎯 Next Steps

1. **Test with `cvlc` instead of `vlc`** (disables GUI overhead)
2. **Force avcodec AAC decoder** (bypass FAAD)
3. **If that fails, use MPV exclusively** (it works reliably)

