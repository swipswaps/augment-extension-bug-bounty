# VS Code Resource Guardian

**Monitors and mitigates VS Code zygote process runaway CPU/memory issues, extension host memory leaks, and Electron resource contention.**

## Problem Statement

VS Code (built on Electron/Chromium) uses **zygote processes** for sandboxing and process isolation. Under certain conditions, these processes can:

1. **Consume excessive CPU** (18%+ sustained usage instead of idle)
2. **Leak memory** (1GB+ instead of <100MB)
3. **Cause swap thrashing** (forcing system to use swap, degrading performance)
4. **Persist for days** (accumulating CPU time and memory)

### Root Causes

- **Electron/Chromium zygote bug**: Known issue in Electron 22-28 (mostly fixed in 39+)
- **Extension host memory leaks**: Long-running extensions not releasing memory
- **Event listener accumulation**: Extensions registering listeners without cleanup
- **File watcher leaks**: Watching too many files without proper disposal

### Is This an Electron Issue or VS Code Issue?

**Answer: Primarily an extension issue, exacerbated by Electron architecture.**

- **Electron 39.3.0** (current) is stable and has fixed most zygote bugs
- **VS Code 1.109.4** (current) has proper resource management
- **Extensions** (especially Augment, Watchdog, and other monitoring tools) can trigger runaway behavior

## Solution Approach

This extension provides **active monitoring and mitigation**:

1. **Monitor zygote processes** for abnormal CPU/memory usage
2. **Detect memory leaks** using linear regression on historical data
3. **Alert user** when thresholds exceeded
4. **Auto-trigger garbage collection** to reclaim memory
5. **Optionally kill runaway processes** (with user confirmation)
6. **Log metrics** for forensic analysis

## Features

### Automatic Monitoring

- **CPU threshold detection**: Alert when zygote CPU > 15% (configurable)
- **Memory threshold detection**: Alert when zygote memory > 500MB (configurable)
- **Memory leak detection**: Analyze memory growth over time using linear regression
- **Swap usage alerts**: Warn when system using swap (memory pressure)
- **Extension host monitoring**: Track extension host memory separately

### Manual Actions

- **Show Resource Status**: Display current CPU/memory usage
- **Kill Runaway Processes**: Manually kill processes exceeding thresholds
- **Restart Extension Host**: Restart extension host to clear memory leaks
- **Force Garbage Collection**: Trigger GC to reclaim memory
- **Generate Report**: Create detailed resource usage report

### Logging

- **Output channel**: Real-time logging to "Resource Guardian" output panel
- **File logging**: Persistent logs for forensic analysis
- **Metrics tracking**: Historical data for leak detection

## Installation

```bash
cd vscode-resource-guardian
npm install
npm run compile
vsce package
code --install-extension vscode-resource-guardian-1.0.0.vsix --force
```

Then **reload VS Code** (Ctrl+Shift+P → "Reload Window")

## Configuration

Open Settings (Ctrl+,) and search for "Resource Guardian":

```json
{
  "resourceGuardian.monitorInterval": 10000,
  "resourceGuardian.cpuThreshold": 15.0,
  "resourceGuardian.memoryThreshold": 500,
  "resourceGuardian.extensionHostMemoryThreshold": 400,
  "resourceGuardian.autoKillRunaway": false,
  "resourceGuardian.autoGarbageCollection": true,
  "resourceGuardian.logToFile": true,
  "resourceGuardian.alertOnSwap": true
}
```

### Configuration Options

- **monitorInterval**: How often to check resources (ms, default: 10000)
- **cpuThreshold**: CPU % threshold for zygote processes (default: 15%)
- **memoryThreshold**: Memory threshold for zygote processes (MB, default: 500)
- **extensionHostMemoryThreshold**: Memory threshold for extension host (MB, default: 400)
- **autoKillRunaway**: Automatically kill runaway processes (DANGEROUS, default: false)
- **autoGarbageCollection**: Auto-trigger GC when threshold exceeded (default: true)
- **logToFile**: Log metrics to file (default: true)
- **alertOnSwap**: Alert when system using swap (default: true)

## Usage

### View Current Status

1. Open Command Palette (Ctrl+Shift+P)
2. Run: **Resource Guardian: Show Resource Status**
3. View report in "Resource Guardian" output panel

### Kill Runaway Processes

1. Open Command Palette (Ctrl+Shift+P)
2. Run: **Resource Guardian: Kill Runaway Processes**
3. Confirm action

**WARNING**: This may cause VS Code instability. Save your work first.

### Force Garbage Collection

1. Open Command Palette (Ctrl+Shift+P)
2. Run: **Resource Guardian: Force Garbage Collection**
3. Check output panel for freed memory

### Generate Report

1. Open Command Palette (Ctrl+Shift+P)
2. Run: **Resource Guardian: Generate Resource Report**
3. Report saved to log file and displayed in output panel

## How It Works

### Memory Leak Detection Algorithm

```typescript
// Track last 60 memory samples (10 minutes at 10s interval)
// Calculate linear regression slope
// If slope > 5 MB per sample (50 MB/min), flag as leak

slope = (n * Σ(xy) - Σx * Σy) / (n * Σ(x²) - (Σx)²)

if (slope > 5.0) {
    // Memory leak detected
    alert("Memory leak in PID ${pid}");
}
```

### Garbage Collection

```typescript
// Try to use global.gc() if --expose-gc flag set
if (global.gc) {
    global.gc();
} else {
    // Fallback: Create memory pressure to trigger GC
    const arr = new Array(1000000).fill(new Array(100));
    arr.length = 0; // Clear to trigger GC
}
```

### Process Killing

```typescript
// Send SIGTERM for graceful shutdown
exec(`kill -15 ${pid}`);

// Wait 2 seconds
await sleep(2000);

// If still alive, send SIGKILL
exec(`kill -9 ${pid}`);
```

## Comparison with Hidden Terminal Watchdog

| Feature | Resource Guardian | Hidden Terminal Watchdog |
|---------|-------------------|--------------------------|
| **Purpose** | Monitor CPU/memory | Monitor terminal accumulation |
| **Target** | Zygote processes, extension host | Hidden terminals |
| **Detection** | CPU/memory thresholds | Terminal count |
| **Action** | Kill processes, trigger GC | Kill terminals |
| **Leak Detection** | Yes (linear regression) | No |
| **Auto-mitigation** | Yes (GC, optional kill) | Yes (cleanup) |

**Recommendation**: Use **both** extensions together for comprehensive protection.

## Troubleshooting

### Extension Not Working

1. Check output panel: View → Output → "Resource Guardian"
2. Verify extension activated: Check for "Resource Guardian Activated" message
3. Check configuration: Ensure thresholds are reasonable

### False Positives

1. Increase thresholds in settings
2. Disable auto-kill (set `autoKillRunaway: false`)
3. Check logs to see which processes triggered alerts

### Performance Impact

- **CPU**: <0.1% (monitoring runs every 10 seconds)
- **Memory**: <10MB (stores last 60 samples per process)
- **Disk I/O**: Minimal (logs only when events occur)

## License

MIT

## Author

Resource Guardian Team

## Related Projects

- **Hidden Terminal Watchdog**: https://github.com/swipswaps/hidden-terminal-watchdog
- **Augment Extension Bug Bounty**: https://github.com/swipswaps/augment-extension-bug-bounty

