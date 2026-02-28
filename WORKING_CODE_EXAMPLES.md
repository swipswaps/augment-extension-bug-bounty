# Working Code Examples - Firefox Performance Optimization Suite

**Purpose**: Working code examples for every claim in root README.md

---

## Quick Start - Web Application (README.md Line 24-42)

**Claim**: "Install dependencies and start the React web application"

**Working Code**:
```bash
# Step 1: Install dependencies
cd firefox-performance-tuner
npm install

# Step 2: Start the application
npm start

# Expected: Backend on http://localhost:3001, Frontend on http://localhost:3000
```

**Verification**:
```bash
# Check if backend is running
curl -s http://localhost:3001/api/health | jq '.'
# Expected: {"status": "ok", ...}

# Check if frontend is running
curl -s http://localhost:3000 | grep -q "Firefox Performance" && echo "✅ Frontend running" || echo "❌ Frontend not running"
```

---

## Quick Start - Bash Script (README.md Line 50-66)

**Claim**: "Run terminal-based performance HUD"

**Working Code**:
```bash
# Step 1: Make script executable
chmod +x firefox_full_performance_hud_autotune.sh

# Step 2: Run the script
./firefox_full_performance_hud_autotune.sh
```

**Expected Output**:
```
═══════════════════════════════════════════════════════════════════
🦊 FIREFOX PERFORMANCE HUD
═══════════════════════════════════════════════════════════════════

📊 System Graphics:
  GPU: Mesa Intel(R) UHD Graphics 620
  Driver: i965
  OpenGL: 4.6 Mesa 23.1.0

🔍 Firefox Profile: /home/user/.mozilla/firefox/abc123.default-release

⚙️  Preference Status:
  ✅ gfx.webrender.enable-gpu-thread: false
  ✅ dom.ipc.processCount: 4
  ✅ gfx.gl.multithreaded: false
```

---

## Create user.js - Find Profile (README.md Line 96-103)

**Claim**: "Find your Firefox profile directory"

**Working Code**:
```bash
# List all Firefox profiles
ls -la ~/.mozilla/firefox/

# Find default-release profile
PROFILE=$(ls -d ~/.mozilla/firefox/*.default-release 2>/dev/null | head -1)
echo "Profile: $PROFILE"

# Or use grep to filter
ls ~/.mozilla/firefox/ | grep -E "\.default-release|\.default"
```

**Expected Output**:
```
6nxwkfvn.default-release
```

---

## Create user.js - Manual Creation (README.md Line 107-147)

**Claim**: "Create user.js file manually"

**Working Code**:
```bash
# Find profile directory
PROFILE=$(ls -d ~/.mozilla/firefox/*.default-release 2>/dev/null | head -1)

# Navigate to profile
cd "$PROFILE"

# Create user.js with basic preferences
cat > user.js << 'EOF'
// Disable GPU threading (fixes GPU delays on X11+Mesa)
user_pref("gfx.webrender.enable-gpu-thread", false);

// Reduce content processes (improves stability)
user_pref("dom.ipc.processCount", 4);

// Enable hardware video decoding
user_pref("media.ffvpx.enabled", true);
EOF

# Verify file was created
cat user.js

# Restart Firefox
killall firefox
sleep 1
firefox &
```

---

## Create user.js - Use Template (README.md Line 151-161)

**Claim**: "Use the provided user.js template"

**Working Code**:
```bash
# Run the installation script
./apply_firefox_optimizations.sh
```

**Expected Output**:
```
🔍 Finding Firefox profile...
✅ Found profile: /home/user/.mozilla/firefox/abc123.default-release

💾 Backing up existing user.js...
✅ Backup created: user.js.backup-20260218-084500

📝 Copying optimized user.js...
✅ user.js installed successfully

🔄 Please restart Firefox to apply changes
```

**Verification**:
```bash
# Check if user.js exists
PROFILE=$(ls -d ~/.mozilla/firefox/*.default-release 2>/dev/null | head -1)
ls -lh "$PROFILE/user.js"

# View content
cat "$PROFILE/user.js" | head -20
```

---

## Critical Preferences - GPU Threading (README.md Line 170-178)

**Claim**: "Disable WebRender GPU thread and Mesa GL multithreading"

**Working Code**:
```bash
PROFILE=$(ls -d ~/.mozilla/firefox/*.default-release 2>/dev/null | head -1)

# Add GPU threading preferences
cat >> "$PROFILE/user.js" << 'EOF'

// Disable WebRender GPU thread
user_pref("gfx.webrender.enable-gpu-thread", false);

// Disable Mesa GL multithreading
user_pref("gfx.gl.multithreaded", false);
EOF

# Restart Firefox
killall firefox && sleep 1 && firefox &
```

**Verification**:
```bash
# Check if preferences are applied (after Firefox restart)
grep -E "gfx.webrender.enable-gpu-thread|gfx.gl.multithreaded" "$PROFILE/prefs.js"
# Expected:
# user_pref("gfx.webrender.enable-gpu-thread", false);
# user_pref("gfx.gl.multithreaded", false);
```

---

## Critical Preferences - Process Count (README.md Line 180-190)

**Claim**: "Limit total processes to 4"

**Working Code**:
```bash
PROFILE=$(ls -d ~/.mozilla/firefox/*.default-release 2>/dev/null | head -1)

# Add process count preferences
cat >> "$PROFILE/user.js" << 'EOF'

// Limit total processes
user_pref("dom.ipc.processCount", 4);

// Limit web content processes
user_pref("dom.ipc.processCount.web", 4);
EOF

# Restart Firefox
killall firefox && sleep 1 && firefox &
```

**Verification**:
```bash
# Count Firefox processes
ps aux | grep firefox | grep -v grep | wc -l
# Expected: ~5-8 processes (1 main + 4 content + a few utility processes)
```

---

## Critical Preferences - GPU Synchronization (README.md Line 192-199)

**Claim**: "Don't wait for GPU acknowledgment"

**Working Code**:
```bash
PROFILE=$(ls -d ~/.mozilla/firefox/*.default-release 2>/dev/null | head -1)

# Add GPU sync preference
cat >> "$PROFILE/user.js" << 'EOF'

// Don't wait for GPU acknowledgment
user_pref("gfx.webrender.wait-for-gpu", false);
EOF

# Restart Firefox
killall firefox && sleep 1 && firefox &
```

---

## Verify Preferences Applied

**Working Code**:
```bash
PROFILE=$(ls -d ~/.mozilla/firefox/*.default-release 2>/dev/null | head -1)

# Check all critical preferences
echo "═══════════════════════════════════════════════════════════════════"
echo "🔍 VERIFYING FIREFOX PREFERENCES"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

# GPU Threading
echo "GPU Threading:"
grep "gfx.webrender.enable-gpu-thread" "$PROFILE/prefs.js" || echo "  ❌ Not set"
grep "gfx.gl.multithreaded" "$PROFILE/prefs.js" || echo "  ❌ Not set"
echo ""

# Process Count
echo "Process Count:"
grep "dom.ipc.processCount" "$PROFILE/prefs.js" || echo "  ❌ Not set"
echo ""

# GPU Sync
echo "GPU Synchronization:"
grep "gfx.webrender.wait-for-gpu" "$PROFILE/prefs.js" || echo "  ❌ Not set"
echo ""

echo "═══════════════════════════════════════════════════════════════════"
```

---

## Monitor Firefox Performance

**Working Code**:
```bash
# Real-time monitoring script
cat > /tmp/monitor-firefox.sh << 'EOF'
#!/usr/bin/env bash
while true; do
    clear
    echo "═══════════════════════════════════════════════════════════════════"
    echo "🦊 FIREFOX PERFORMANCE MONITOR"
    echo "═══════════════════════════════════════════════════════════════════"
    echo ""
    
    # Process count
    PROC_COUNT=$(ps aux | grep firefox | grep -v grep | wc -l)
    echo "📊 Process Count: $PROC_COUNT"
    
    # Memory usage
    MEM_USAGE=$(ps aux | grep firefox | grep -v grep | awk '{sum+=$6} END {print int(sum/1024) " MB"}')
    echo "💾 Memory Usage: $MEM_USAGE"
    
    # CPU usage
    CPU_USAGE=$(ps aux | grep firefox | grep -v grep | awk '{sum+=$3} END {print sum "%"}')
    echo "⚡ CPU Usage: $CPU_USAGE"
    
    echo ""
    echo "Press Ctrl+C to exit"
    sleep 2
done
EOF

chmod +x /tmp/monitor-firefox.sh
/tmp/monitor-firefox.sh
```

---

## Backup and Restore user.js

**Working Code**:
```bash
PROFILE=$(ls -d ~/.mozilla/firefox/*.default-release 2>/dev/null | head -1)

# Backup current user.js
cp "$PROFILE/user.js" "$PROFILE/user.js.backup-$(date +%Y%m%d-%H%M%S)"
echo "✅ Backup created"

# List all backups
ls -lh "$PROFILE"/user.js.backup-*

# Restore from backup
LATEST_BACKUP=$(ls -t "$PROFILE"/user.js.backup-* | head -1)
cp "$LATEST_BACKUP" "$PROFILE/user.js"
echo "✅ Restored from: $LATEST_BACKUP"

# Restart Firefox
killall firefox && sleep 1 && firefox &
```

---

## Reset to Default (Remove user.js)

**Working Code**:
```bash
PROFILE=$(ls -d ~/.mozilla/firefox/*.default-release 2>/dev/null | head -1)

# Backup before removing
cp "$PROFILE/user.js" "$PROFILE/user.js.backup-$(date +%Y%m%d-%H%M%S)"

# Remove user.js
rm "$PROFILE/user.js"
echo "✅ user.js removed (Firefox will use defaults)"

# Restart Firefox
killall firefox && sleep 1 && firefox &
```

---

## Complete Installation Test

**Working Code**:
```bash
# Full installation and verification test
echo "🚀 Starting Firefox Performance Suite Installation Test"
echo ""

# Test 1: Find profile
echo "Test 1: Finding Firefox profile..."
PROFILE=$(ls -d ~/.mozilla/firefox/*.default-release 2>/dev/null | head -1)
if [ -n "$PROFILE" ]; then
    echo "✅ Profile found: $PROFILE"
else
    echo "❌ No profile found"
    exit 1
fi

# Test 2: Install user.js
echo ""
echo "Test 2: Installing user.js..."
./apply_firefox_optimizations.sh
if [ -f "$PROFILE/user.js" ]; then
    echo "✅ user.js installed"
else
    echo "❌ user.js not found"
    exit 1
fi

# Test 3: Verify preferences
echo ""
echo "Test 3: Verifying preferences..."
grep -q "gfx.webrender.enable-gpu-thread" "$PROFILE/user.js" && echo "✅ GPU threading preference found" || echo "❌ Missing"
grep -q "dom.ipc.processCount" "$PROFILE/user.js" && echo "✅ Process count preference found" || echo "❌ Missing"

# Test 4: Start web app
echo ""
echo "Test 4: Starting web application..."
cd firefox-performance-tuner
npm start &
sleep 5
curl -s http://localhost:3000 | grep -q "Firefox Performance" && echo "✅ Web app running" || echo "❌ Web app not responding"

echo ""
echo "🎉 Installation test complete!"
```

---

**✅ ALL CLAIMS IN ROOT README NOW HAVE WORKING CODE EXAMPLES**

