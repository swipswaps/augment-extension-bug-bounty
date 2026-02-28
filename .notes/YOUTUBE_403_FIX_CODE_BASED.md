# 🔧 YouTube 403 Forbidden Error - Code-Based Fix

## 📋 **PROBLEM ANALYSIS**

**Error from logs:**
```
[yt-dlp] [https @ 0x564f80b10500] HTTP error 403 Forbidden
[yt-dlp] [in#0 @ 0x564f80b0f640] Error opening input: Server returned 403 Forbidden (access denied)
[yt-dlp] ERROR: ffmpeg exited with code 8
```

**Root Causes (from yt-dlp GitHub issues #12482):**
1. **YouTube forcing SABR streaming** - Some formats missing direct URLs
2. **yt-dlp version outdated** - User's version (2025.10.22) is 90+ days old
3. **Missing authentication** - YouTube may require browser cookies for some videos
4. **Rate limiting** - YouTube blocking requests from IP address

---

## 🛠️ **SOLUTION 1: Update yt-dlp (RECOMMENDED)**

### **Why This Works:**
- YouTube changes API frequently (every 2-4 weeks)
- yt-dlp releases updates to match YouTube changes
- Outdated yt-dlp = broken extraction

### **Code-Based Implementation:**

```bash
#!/bin/bash
# File: firefox-performance-tuner/scripts/update-ytdlp.sh
# Purpose: Update yt-dlp to latest version (fixes YouTube API changes)

set -euo pipefail  # Exit on error, undefined vars, pipe failures

echo "━━━ yt-dlp Update Script ━━━"
echo ""

# STEP 1: Check current version
echo "[1/4] Checking current yt-dlp version..."
CURRENT_VERSION=$(yt-dlp --version 2>/dev/null || echo "NOT_INSTALLED")
echo "  Current version: $CURRENT_VERSION"
echo ""

# STEP 2: Detect installation method
echo "[2/4] Detecting installation method..."
if command -v pip &>/dev/null && pip show yt-dlp &>/dev/null; then
  INSTALL_METHOD="pip"
  echo "  Detected: pip (Python package manager)"
elif command -v dnf &>/dev/null && dnf list installed yt-dlp &>/dev/null; then
  INSTALL_METHOD="dnf"
  echo "  Detected: dnf (Fedora package manager)"
elif command -v apt &>/dev/null && dpkg -l yt-dlp &>/dev/null; then
  INSTALL_METHOD="apt"
  echo "  Detected: apt (Debian/Ubuntu package manager)"
else
  INSTALL_METHOD="unknown"
  echo "  ⚠️  WARNING: Could not detect installation method"
fi
echo ""

# STEP 3: Update yt-dlp
echo "[3/4] Updating yt-dlp..."
case "$INSTALL_METHOD" in
  pip)
    echo "  Running: pip install --upgrade yt-dlp"
    pip install --upgrade yt-dlp
    ;;
  dnf)
    echo "  Running: sudo dnf upgrade -y yt-dlp"
    sudo dnf upgrade -y yt-dlp
    ;;
  apt)
    echo "  Running: sudo apt update && sudo apt upgrade -y yt-dlp"
    sudo apt update && sudo apt upgrade -y yt-dlp
    ;;
  unknown)
    echo "  ⚠️  Manual update required:"
    echo "     - If installed via pip: pip install --upgrade yt-dlp"
    echo "     - If installed via package manager: use your package manager"
    exit 1
    ;;
esac
echo ""

# STEP 4: Verify new version
echo "[4/4] Verifying new version..."
NEW_VERSION=$(yt-dlp --version)
echo "  New version: $NEW_VERSION"
echo ""

if [ "$NEW_VERSION" != "$CURRENT_VERSION" ]; then
  echo "✅ SUCCESS: yt-dlp updated from $CURRENT_VERSION to $NEW_VERSION"
else
  echo "⚠️  WARNING: Version unchanged (may already be latest)"
fi
echo ""
echo "━━━ Update Complete ━━━"
```

**Usage:**
```bash
cd firefox-performance-tuner
chmod +x scripts/update-ytdlp.sh
./scripts/update-ytdlp.sh
```

---

## 🛠️ **SOLUTION 2: Add Browser Cookies Authentication**

### **Why This Works:**
- YouTube uses cookies to track authenticated users
- Authenticated users get better access to videos
- yt-dlp can extract cookies from browser

### **Code-Based Implementation:**

```javascript
// File: firefox-performance-tuner/server.js
// Function: streamVideoDirectly()
// Location: Line 1294 (yt-dlp spawn)

/**
 * ENHANCED yt-dlp FLAGS WITH COOKIE AUTHENTICATION
 *
 * NEW FLAGS ADDED:
 *  --cookies-from-browser firefox
 *    - Extract cookies from Firefox browser
 *    - Provides YouTube authentication
 *    - Bypasses 403 errors for authenticated content
 *    - Requires Firefox to be installed and have YouTube cookies
 *
 *  --extractor-args "youtube:player_client=android,web"
 *    - Force specific YouTube player clients
 *    - Android client often has better format availability
 *    - Web client as fallback
 *    - Bypasses SABR streaming issues
 *
 *  --no-check-certificates
 *    - Skip SSL certificate verification (use with caution)
 *    - Helps with some network configurations
 *    - Only use if other methods fail
 */

const ytdlpProc = spawn("yt-dlp", [
  "-f", "bestvideo+bestaudio/best",
  "-o", "-",                                    // CRITICAL: stdout streaming
  "--no-part",                                  // No .part file
  "--cookies-from-browser", "firefox",          // NEW: Use Firefox cookies for auth
  "--extractor-args", "youtube:player_client=android,web",  // NEW: Force Android/Web clients
  url
], {
  stdio: ["ignore", "pipe", "pipe"]
});
```

**Alternative (if Firefox not available):**
```javascript
// Use Chrome/Chromium cookies instead
"--cookies-from-browser", "chrome"

// Or use cookie file
"--cookies", "/path/to/cookies.txt"
```

---

## 🛠️ **SOLUTION 3: Use Alternative Format Selection**

### **Why This Works:**
- Some YouTube formats are blocked with 403
- Alternative formats may be accessible
- HLS (m3u8) streams often work when DASH fails

### **Code-Based Implementation:**

```javascript
// File: firefox-performance-tuner/server.js
// Function: streamVideoDirectly()
// Location: Line 1294 (yt-dlp spawn)

/**
 * ALTERNATIVE FORMAT SELECTION STRATEGY
 *
 * STRATEGY 1: Prefer HLS (m3u8) streams
 *  -f "best[protocol=m3u8]/best"
 *    - HLS streams are often more reliable
 *    - Less likely to get 403 errors
 *    - Works well with VLC/MPV
 *
 * STRATEGY 2: Avoid DASH formats
 *  -f "best[protocol!=dash]/best"
 *    - DASH formats more likely to be blocked
 *    - HTTP progressive download more reliable
 *
 * STRATEGY 3: Use lower quality as fallback
 *  -f "bestvideo[height<=720]+bestaudio/best[height<=720]/best"
 *    - Lower quality formats less likely to be blocked
 *    - Still good viewing experience
 *    - Faster download/streaming
 */

// OPTION A: Prefer HLS streams
const ytdlpProc = spawn("yt-dlp", [
  "-f", "best[protocol=m3u8]/bestvideo+bestaudio/best",
  "-o", "-",
  "--no-part",
  "--cookies-from-browser", "firefox",
  url
], {
  stdio: ["ignore", "pipe", "pipe"]
});

// OPTION B: Avoid DASH, prefer 720p
const ytdlpProc = spawn("yt-dlp", [
  "-f", "bestvideo[height<=720][protocol!=dash]+bestaudio/best[height<=720]/best",
  "-o", "-",
  "--no-part",
  "--cookies-from-browser", "firefox",
  url
], {
  stdio: ["ignore", "pipe", "pipe"]
});
```

---

## 🧪 **TESTING PROCEDURE**

### **Test 1: Verify yt-dlp Update**
```bash
# Check version
yt-dlp --version

# Test download (no streaming, just check if 403 is fixed)
yt-dlp -f best --no-part "https://www.youtube.com/watch?v=-kB-BGMXxZc" -o /tmp/test.mp4

# Expected: Download succeeds without 403 error
```

### **Test 2: Test Cookie Authentication**
```bash
# Test with Firefox cookies
yt-dlp -f best --cookies-from-browser firefox "https://www.youtube.com/watch?v=-kB-BGMXxZc" -o /tmp/test.mp4

# Expected: Download succeeds with authentication
```

### **Test 3: Test Alternative Formats**
```bash
# Test HLS format
yt-dlp -f "best[protocol=m3u8]/best" "https://www.youtube.com/watch?v=-kB-BGMXxZc" -o /tmp/test.mp4

# Expected: Download succeeds using HLS stream
```

---

## 📚 **REFERENCES**

- **yt-dlp GitHub Issue #12482**: https://github.com/yt-dlp/yt-dlp/issues/12482
  - "YouTube forcing SABR streaming for some clients"
  - Workaround: Use `--extractor-args "youtube:player_client=android"`

- **yt-dlp Documentation - Authentication**: https://github.com/yt-dlp/yt-dlp#authentication-with-netrc-file
  - Cookie extraction from browsers
  - Using cookie files

- **yt-dlp Documentation - Format Selection**: https://github.com/yt-dlp/yt-dlp#format-selection
  - Format selection syntax
  - Protocol filtering

---

## ✅ **RECOMMENDED ACTION PLAN**

1. **FIRST:** Update yt-dlp (run `scripts/update-ytdlp.sh`)
2. **SECOND:** Test if update fixed 403 error
3. **IF STILL FAILING:** Add cookie authentication to server.js
4. **IF STILL FAILING:** Try alternative format selection
5. **IF STILL FAILING:** Check YouTube rate limiting (wait 1 hour, try again)


