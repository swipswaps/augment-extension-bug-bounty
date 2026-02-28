# VS Code Resource Guardian - Code-Based Prompt

## CRITICAL SYSTEM STATE (2026-02-19 08:00)

```bash
# EMERGENCY: System severely overloaded
Load average: 5.83 4.12 3.11  # Nearly 3x CPU capacity (2 cores)
Swap: 1.4GB / 7.7GB (18%)     # Memory pressure
Memory: 3.9GB / 7.7GB (50%)   # High usage

# RUNAWAY PROCESSES DETECTED:
PID 815364: 27.0% CPU, 1083MB RAM  # zygote - CRITICAL
PID 813994: 13.0% CPU,  640MB RAM  # zygote - HIGH
PID 814088: 11.2% CPU,  551MB RAM  # utility - HIGH
```

## SOLUTION: Resource Guardian Extension

### Installation (IMMEDIATE)

```bash
cd vscode-resource-guardian
./INSTALL_AND_ACTIVATE.sh
# This script will:
# 1. Install dependencies
# 2. Compile TypeScript
# 3. Package extension
# 4. Install to VS Code
# 5. KILL runaway processes NOW
# 6. Prompt you to reload VS Code
```

### Key Improvements Over v1.0

```typescript
// IMPROVEMENT 1: Detect utility processes (/proc/self/exe)
// These can leak memory and CPU just like zygotes
if (cmd.includes('--type=zygote') || 
    cmd.includes('extensionHost') || 
    cmd.includes('node.mojom.NodeService') ||
    cmd.includes('/proc/self/exe')) {  // ← NEW
    // Track this process
}

// IMPROVEMENT 2: Calculate CPU efficiency (runtime vs CPU time)
// Detects processes consuming CPU continuously (runaway)
const cpuEfficiency = (proc.cputime / proc.runtime) * 100;
// If > 50%, process is runaway (consuming CPU half the time)

// IMPROVEMENT 3: Emergency cleanup when load > 5.0
if (loadAvg1min > 5.0) {
    // Force GC immediately
    await forceGarbageCollection();
    
    // Kill ALL processes exceeding thresholds
    for (const proc of metrics.processes) {
        if (proc.cpu > cpuThreshold * 1.5 || proc.memory > memoryThreshold * 1.5) {
            await killRunawayProcess(proc.pid, `Emergency cleanup`);
        }
    }
}

// IMPROVEMENT 4: More aggressive thresholds
// CPU: 15% → 10% (earlier detection)
// Memory: 500MB → 400MB (earlier detection)
// Monitor interval: 10s → 5s (faster response)

// IMPROVEMENT 5: Better activation
// "*" → "onStartupFinished" (less performance impact)
```

### Configuration (Recommended for Your System)

```json
{
  "resourceGuardian.monitorInterval": 5000,           // Check every 5 seconds
  "resourceGuardian.cpuThreshold": 10.0,              // Alert at 10% CPU
  "resourceGuardian.memoryThreshold": 400,            // Alert at 400MB
  "resourceGuardian.extensionHostMemoryThreshold": 400,
  "resourceGuardian.autoKillRunaway": false,          // Manual kill (safer)
  "resourceGuardian.autoGarbageCollection": true,     // Auto GC (recommended)
  "resourceGuardian.logToFile": true,                 // Log for analysis
  "resourceGuardian.alertOnSwap": true                // Alert on swap usage
}
```

### Commands Available

```typescript
// Show current resource usage
vscode.commands.executeCommand('resourceGuardian.showStatus');

// Kill all processes exceeding thresholds
vscode.commands.executeCommand('resourceGuardian.killRunawayProcesses');

// Force garbage collection NOW
vscode.commands.executeCommand('resourceGuardian.forceGarbageCollection');

// EMERGENCY: Kill everything and force GC
vscode.commands.executeCommand('resourceGuardian.emergencyCleanup');

// Restart extension host (clears memory leaks)
vscode.commands.executeCommand('resourceGuardian.restartExtensionHost');

// Generate detailed report
vscode.commands.executeCommand('resourceGuardian.generateReport');
```

### Memory Leak Detection Algorithm

```typescript
// Track last 60 memory samples (5 minutes at 5s interval)
const history: number[] = []; // Memory in MB

// Calculate linear regression slope
// slope = (n * Σ(xy) - Σx * Σy) / (n * Σ(x²) - (Σx)²)
const slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);

// If slope > 5 MB per sample (60 MB/min), flag as leak
if (slope > 5.0) {
    log(`MEMORY LEAK DETECTED: PID ${pid}`, 'CRITICAL');
    // Alert user with options:
    // - Restart Extension Host
    // - Force GC
    // - Kill Process
    // - Ignore
}
```

### Process Killing Strategy

```typescript
// STEP 1: Send SIGTERM (graceful shutdown)
await execAsync(`kill -15 ${pid}`);
log(`Sent SIGTERM to PID ${pid}`, 'INFO');

// STEP 2: Wait 2 seconds for graceful shutdown
await new Promise(resolve => setTimeout(resolve, 2000));

// STEP 3: Check if still alive
try {
    await execAsync(`kill -0 ${pid}`);
    // Still alive, send SIGKILL (force kill)
    await execAsync(`kill -9 ${pid}`);
    log(`Sent SIGKILL to PID ${pid}`, 'WARN');
} catch {
    // Process terminated gracefully
    log(`PID ${pid} terminated gracefully`, 'INFO');
}
```

### Garbage Collection Strategy

```typescript
// TRY 1: Use global.gc() if --expose-gc flag set
if (global.gc) {
    global.gc();
    log('Forced GC using global.gc()', 'INFO');
} else {
    // TRY 2: Create memory pressure to trigger GC
    // Allocate 100MB of arrays, then clear
    const arr: any[] = [];
    for (let i = 0; i < 1000000; i++) {
        arr.push(new Array(100));
    }
    arr.length = 0; // Clear to trigger GC
    log('Triggered GC via memory pressure', 'INFO');
}

// Wait 1 second for GC to complete
await new Promise(resolve => setTimeout(resolve, 1000));

// Log freed memory
const freedMB = (before.heapUsed - after.heapUsed) / (1024 * 1024);
log(`GC freed ${freedMB.toFixed(2)} MB`, 'INFO');
```

## Expected Results

### Before Resource Guardian
```
Load: 5.83 (nearly 3x capacity)
CPU: 47.8% consumed by VS Code
RAM: 2.6GB consumed by VS Code
Swap: 1.4GB used (memory pressure)
```

### After Resource Guardian
```
Load: <2.0 (normal for 2-core system)
CPU: <10% consumed by VS Code
RAM: <1GB consumed by VS Code
Swap: <500MB used (minimal pressure)
```

## Files Modified

```bash
vscode-resource-guardian/src/extension.ts      # 714 lines (was 589)
vscode-resource-guardian/package.json          # 106 lines (was 102)
vscode-resource-guardian/INSTALL_AND_ACTIVATE.sh  # 150 lines (NEW)
vscode-resource-guardian/PROMPT.md             # This file (NEW)
```

## Next Steps

1. **IMMEDIATE**: Run `./INSTALL_AND_ACTIVATE.sh`
2. **IMMEDIATE**: Reload VS Code (Ctrl+Shift+P → "Reload Window")
3. **5 minutes**: Check output panel (View → Output → "Resource Guardian")
4. **1 hour**: Run "Resource Guardian: Generate Resource Report"
5. **24 hours**: Review logs to identify leaking extensions
6. **Optional**: Enable `autoKillRunaway: true` after confirming accuracy

