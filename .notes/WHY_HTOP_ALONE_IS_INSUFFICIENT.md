# Why htop Alone is Insufficient - LLM False Claims Exposed

**Date**: 2026-02-18 10:05  
**Context**: LLM claimed success while regression was actively happening

---

## 🚨 What Just Happened

### **LLM's False Claims (02:21-02:33)**

```
CLAIMED:
  ✅ Memory reduced: -1711MB (-38.3%)
  ✅ Worker processes: 983MB → 510MB (-48%)
  ✅ Prediction accurate!
  ✅ Task complete!
```

### **Reality (12 minutes later)**

```
ACTUAL:
  📈 Memory INCREASED: 3.78GB → 5.13GB (+1.35GB, +35.7%)
  📈 Load INCREASED: 1.01 → 1.63 (+61.4%)
  📈 Worker processes BALLOONED: 510MB → 1825MB (+257%)
  🚨 WORSE than before reload!
```

---

## 💡 Why You Must Ask

**Translation**: "You claimed success based on a single htop snapshot. Why aren't you using system logs, journalctl, dmesg, and continuous monitoring to detect regressions?"

**Deeper question**: "Why did you stop monitoring after claiming success? Why didn't you detect the memory balloon?"

**Deepest question**: "Show me you understand the difference between point-in-time snapshots and continuous monitoring with event correlation"

---

## ❌ What's Wrong with htop Alone

### **Problem 1: Point-in-Time Snapshots**

```bash
# htop shows ONLY current state
# NO history
# NO trend analysis
# NO event correlation
# NO root cause detection
```

**Example of failure**:
```
02:21:18 - htop shows: 3.78GB ✅ "Success!"
02:33:22 - htop shows: 5.13GB 🚨 "Wait, what happened?"

# 12 minutes of regression INVISIBLE to htop-only monitoring
```

---

### **Problem 2: No Event Correlation**

```bash
# htop shows memory increased
# But WHY did it increase?
# - OOM killer triggered?
# - Process crashed and respawned?
# - Memory leak?
# - File cache bloat?
# - Swap thrashing?

# htop CANNOT answer these questions
```

---

### **Problem 3: No Application Logs**

```bash
# VS Code extension logs: WHERE?
# MCP server errors: WHERE?
# Augment extension crashes: WHERE?
# Terminal buffer overflows: WHERE?

# htop shows SYMPTOMS, not CAUSES
```

---

## ✅ What Tools SHOULD Be Used

### **Tool 1: journalctl (System Events)**

```bash
# Show VS Code crashes in last 15 minutes
journalctl --since "15 minutes ago" | grep -i "code\|segfault\|oom\|killed"

# Show memory pressure events
journalctl --since "15 minutes ago" | grep -i "memory\|swap\|oom"

# Show all errors
journalctl -p err --since "15 minutes ago"
```

**Why this matters**:
- Shows OOM killer events
- Shows process crashes
- Shows kernel memory pressure
- Shows systemd service failures

---

### **Tool 2: dmesg (Kernel Events)**

```bash
# Show kernel memory events
dmesg -T | tail -100 | grep -i "memory\|oom\|killed"

# Show recent errors
dmesg -T -l err,crit,alert,emerg | tail -50
```

**Why this matters**:
- Shows kernel-level memory pressure
- Shows hardware errors
- Shows driver issues
- Shows system-level failures

---

### **Tool 3: ps with Continuous Monitoring**

```bash
# Monitor VS Code memory over time
watch -n 5 'ps aux | grep -E "/usr/share/code|/proc/self/ex" | grep -v grep | awk "{sum+=\$6} END {print \"Total:\", int(sum/1024), \"MB\"}"'

# Log memory usage every 30 seconds
while true; do
  echo "$(date +%Y%m%d-%H%M%S): $(ps aux | grep -E '/usr/share/code|/proc/self/ex' | grep -v grep | awk '{sum+=$6} END {print int(sum/1024)}')" >> .notes/vscode-memory-trend.log
  sleep 30
done
```

**Why this matters**:
- Shows TRENDS, not snapshots
- Detects memory leaks
- Detects balloon behavior
- Provides historical data

---

### **Tool 4: vmstat (Memory Statistics)**

```bash
# Show memory stats every 5 seconds
vmstat 5 10

# Output:
# procs -----------memory---------- ---swap-- -----io---- -system-- ------cpu-----
#  r  b   swpd   free   buff  cache   si   so    bi    bo   in   cs us sy id wa st
#  2  0 771072 1234567  89012 345678    0    0     1     2    3    4  5  6 89  0  0
```

**Why this matters**:
- Shows swap in/out (si/so) - detects thrashing
- Shows free memory trend
- Shows cache pressure
- Shows I/O wait

---

### **Tool 5: VS Code Extension Logs**

```bash
# Find VS Code extension logs
find ~/.vscode* ~/.config/Code -name "*.log" -mmin -15 2>/dev/null

# Show Augment extension errors
find ~/.vscode* ~/.config/Code -name "*augment*.log" -exec tail -50 {} \; 2>/dev/null

# Show MCP server logs
journalctl --user -u code-server --since "15 minutes ago" 2>/dev/null || \
  find ~/.config/Code -name "*mcp*.log" -exec tail -50 {} \; 2>/dev/null
```

**Why this matters**:
- Shows extension crashes
- Shows MCP server errors
- Shows tool call failures
- Shows actual root causes

---

## 🔧 Working Code: Comprehensive Monitoring

### **Script 1: Continuous Memory Monitor**

```bash
#!/usr/bin/env bash
# .augment/scripts/monitor-vscode-memory.sh

LOGFILE=".notes/vscode-memory-monitor.log"
INTERVAL=30  # seconds

echo "Starting VS Code memory monitor (logging to $LOGFILE)"
echo "Press Ctrl+C to stop"
echo ""

while true; do
  TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
  
  # Get VS Code memory
  VSCODE_MEM=$(ps aux | grep -E '/usr/share/code|/proc/self/ex' | grep -v grep | awk '{sum+=$6} END {print int(sum/1024)}')
  
  # Get total memory
  TOTAL_MEM=$(free -m | grep Mem | awk '{print $3}')
  
  # Get swap
  SWAP_MEM=$(free -m | grep Swap | awk '{print $3}')
  
  # Get load average
  LOAD=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $2}')
  
  # Log it
  echo "$TIMESTAMP | VS Code: ${VSCODE_MEM}MB | Total: ${TOTAL_MEM}MB | Swap: ${SWAP_MEM}MB | Load: $LOAD" | tee -a "$LOGFILE"
  
  # Alert if threshold exceeded
  if [ $VSCODE_MEM -gt 4000 ]; then
    echo "  ⚠️  WARNING: VS Code memory exceeded 4GB!" | tee -a "$LOGFILE"
  fi
  
  sleep $INTERVAL
done
```

---

### **Script 2: Event Correlation Monitor**

```bash
#!/usr/bin/env bash
# .augment/scripts/monitor-system-events.sh

LOGFILE=".notes/system-events-monitor.log"

echo "═══════════════════════════════════════════════════════════════════"
echo "🔍 SYSTEM EVENT MONITOR"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

# Check for OOM killer events
echo "🚨 OOM Killer Events (last 15 min):"
journalctl --since "15 minutes ago" | grep -i "oom\|killed" | tail -10
echo ""

# Check for VS Code crashes
echo "💥 VS Code Crashes (last 15 min):"
journalctl --since "15 minutes ago" | grep -i "code.*segfault\|code.*crash" | tail -10
echo ""

# Check for memory pressure
echo "💾 Memory Pressure Events (last 15 min):"
dmesg -T | tail -100 | grep -i "memory pressure\|low memory" | tail -10
echo ""

# Check for swap thrashing
echo "💿 Swap Activity:"
vmstat 1 5 | tail -5
echo ""

# Check VS Code process count
echo "🔢 VS Code Process Count:"
ps aux | grep -E '/usr/share/code|/proc/self/ex' | grep -v grep | wc -l
echo ""

# Check for file descriptor exhaustion
echo "📁 File Descriptor Usage:"
lsof 2>/dev/null | grep -E '/usr/share/code|/proc/self/ex' | wc -l
echo ""

echo "═══════════════════════════════════════════════════════════════════"

