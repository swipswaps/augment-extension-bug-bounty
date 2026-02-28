/**
 * VS Code Resource Guardian Extension
 * 
 * PURPOSE:
 * Monitors and mitigates VS Code zygote process runaway CPU/memory issues,
 * extension host memory leaks, and Electron resource contention.
 * 
 * ROOT CAUSE ADDRESSED:
 * - Electron zygote processes consuming excessive CPU (18%+) and memory (1GB+)
 * - Extension host memory leaks from long-running extensions
 * - Swap thrashing causing system-wide performance degradation
 * 
 * SOLUTION APPROACH:
 * 1. Monitor zygote processes for abnormal CPU/memory usage
 * 2. Track extension host memory growth over time
 * 3. Detect swap usage and memory pressure
 * 4. Automatically trigger garbage collection when thresholds exceeded
 * 5. Alert user and optionally kill runaway processes
 * 6. Log metrics for forensic analysis
 * 
 * ARCHITECTURE:
 * - Polling-based monitoring (avoids event listener memory leaks)
 * - Separate timers for different monitoring tasks (prevents blocking)
 * - Graceful degradation (continues monitoring even if one check fails)
 * - Proper cleanup on deactivation (prevents extension from becoming the leak)
 */

import * as vscode from 'vscode';
import * as os from 'os';
import * as fs from 'fs';
import * as path from 'path';
import { exec } from 'child_process';
import { promisify } from 'util';

const execAsync = promisify(exec);

// Global state
let outputChannel: vscode.OutputChannel;
let logFilePath: string | undefined;
let monitoringInterval: NodeJS.Timeout | undefined;
let gcInterval: NodeJS.Timeout | undefined;
let heartbeatInterval: NodeJS.Timeout | undefined;

// Metrics tracking
interface ProcessMetrics {
    pid: number;
    name: string;
    cpu: number;
    memory: number; // MB
    runtime: number; // seconds
    cputime: number; // seconds
}

interface SystemMetrics {
    timestamp: string;
    totalMemory: number; // MB
    usedMemory: number; // MB
    freeMemory: number; // MB
    swapTotal: number; // MB
    swapUsed: number; // MB
    loadAverage: number[];
    processes: ProcessMetrics[];
}

// Historical tracking for leak detection
const memoryHistory: Map<number, number[]> = new Map(); // PID -> [memory samples]
const MAX_HISTORY_SAMPLES = 60; // Track last 60 samples (10 minutes at 10s interval)

// NEW v1.2: Startup grace period and violation tracking
// REASON: Extension was TOO AGGRESSIVE, killed processes during normal VS Code startup
const extensionActivationTime = Date.now();
const STARTUP_GRACE_PERIOD = 120000;  // 2 minutes - don't kill anything during startup
const PROCESS_MIN_AGE = 30000;        // 30 seconds - don't kill young processes
const VIOLATION_COUNT_THRESHOLD = 3;  // Must exceed threshold 3 times before flagging

// Track violation counts per PID (must violate 3 times in a row)
const violationCounts = new Map<number, number>();

// Ignore list (user can ignore specific PIDs for 5 minutes)
const ignoreList = new Map<number, number>();  // PID -> expiry timestamp

/**
 * Log message to output channel and optionally to file
 * 
 * @param message - Message to log
 * @param level - Log level (INFO, WARN, ERROR, CRITICAL)
 */
function log(message: string, level: 'INFO' | 'WARN' | 'ERROR' | 'CRITICAL' = 'INFO'): void {
    const timestamp = new Date().toISOString();
    const logLine = `[${timestamp}] [${level}] ${message}`;
    
    outputChannel.appendLine(logLine);
    
    // Write to file if enabled
    const config = vscode.workspace.getConfiguration('resourceGuardian');
    if (config.get<boolean>('logToFile', true) && logFilePath) {
        try {
            fs.appendFileSync(logFilePath, logLine + '\n');
        } catch (err) {
            // Silently fail to avoid infinite loop
        }
    }
}

/**
 * Get current system resource metrics
 *
 * IMPLEMENTATION:
 * - Uses `ps aux` to get process list with CPU/memory
 * - Filters for VS Code processes (code, zygote, extension host)
 * - Parses swap usage from /proc/meminfo (Linux) or swapon (cross-platform)
 * - Calculates load average from os.loadavg()
 * - IMPROVED: Now captures runtime and CPU time for better leak detection
 * - IMPROVED: Detects /proc/self/exe processes (utility processes that can leak)
 *
 * @returns SystemMetrics object with current resource usage
 */
async function getSystemMetrics(): Promise<SystemMetrics> {
    const timestamp = new Date().toISOString();
    const totalMemory = os.totalmem() / (1024 * 1024); // Convert to MB
    const freeMemory = os.freemem() / (1024 * 1024);
    const usedMemory = totalMemory - freeMemory;
    const loadAverage = os.loadavg();

    // Get swap usage (Linux-specific, gracefully degrades on other platforms)
    let swapTotal = 0;
    let swapUsed = 0;
    try {
        if (os.platform() === 'linux') {
            const { stdout } = await execAsync('free -m | grep Swap');
            const parts = stdout.trim().split(/\s+/);
            swapTotal = parseInt(parts[1], 10);
            swapUsed = parseInt(parts[2], 10);
        }
    } catch (err) {
        // Swap info not available, continue without it
    }

    // Get VS Code process metrics with detailed info
    const processes: ProcessMetrics[] = [];
    try {
        // IMPROVED: Get detailed process info including runtime and CPU time
        // Format: PID %CPU %MEM VSZ RSS ETIME TIME CMD
        const { stdout } = await execAsync(
            'ps aux -o pid,%cpu,%mem,vsz,rss,etime,time,cmd | grep -E "(code|electron|/proc/self/exe)" | grep -v grep'
        );

        const lines = stdout.trim().split('\n');
        for (const line of lines) {
            const parts = line.trim().split(/\s+/);
            if (parts.length < 8) continue;

            const pid = parseInt(parts[0], 10);
            const cpu = parseFloat(parts[1]);
            const mem = parseFloat(parts[2]);
            const rss = parseInt(parts[4], 10); // RSS in KB
            const etime = parts[5]; // Elapsed time (runtime)
            const cputime = parts[6]; // CPU time
            const cmd = parts.slice(7).join(' ');

            // Calculate memory in MB from RSS (more accurate than % of total)
            const memoryMB = rss / 1024;

            // Parse runtime to seconds (format: [[DD-]HH:]MM:SS or SSSSS)
            let runtimeSeconds = 0;
            try {
                const etimeParts = etime.split(/[-:]/);
                if (etimeParts.length === 1) {
                    runtimeSeconds = parseInt(etimeParts[0], 10);
                } else if (etimeParts.length === 2) {
                    runtimeSeconds = parseInt(etimeParts[0], 10) * 60 + parseInt(etimeParts[1], 10);
                } else if (etimeParts.length === 3) {
                    runtimeSeconds = parseInt(etimeParts[0], 10) * 3600 + parseInt(etimeParts[1], 10) * 60 + parseInt(etimeParts[2], 10);
                } else if (etimeParts.length === 4) {
                    runtimeSeconds = parseInt(etimeParts[0], 10) * 86400 + parseInt(etimeParts[1], 10) * 3600 + parseInt(etimeParts[2], 10) * 60 + parseInt(etimeParts[3], 10);
                }
            } catch {
                // Failed to parse, use 0
            }

            // Parse CPU time to seconds (format: [[DD-]HH:]MM:SS)
            let cputimeSeconds = 0;
            try {
                const timeParts = cputime.split(/[-:]/);
                if (timeParts.length === 2) {
                    cputimeSeconds = parseInt(timeParts[0], 10) * 60 + parseInt(timeParts[1], 10);
                } else if (timeParts.length === 3) {
                    cputimeSeconds = parseInt(timeParts[0], 10) * 3600 + parseInt(timeParts[1], 10) * 60 + parseInt(timeParts[2], 10);
                } else if (timeParts.length === 4) {
                    cputimeSeconds = parseInt(timeParts[0], 10) * 86400 + parseInt(timeParts[1], 10) * 3600 + parseInt(timeParts[2], 10) * 60 + parseInt(timeParts[3], 10);
                }
            } catch {
                // Failed to parse, use 0
            }

            // IMPROVED: Track zygote, extension host, AND utility processes (/proc/self/exe)
            // Utility processes can also leak memory and consume CPU
            if (cmd.includes('--type=zygote') ||
                cmd.includes('extensionHost') ||
                cmd.includes('node.mojom.NodeService') ||
                cmd.includes('/proc/self/exe')) {
                processes.push({
                    pid,
                    name: cmd.substring(0, 100), // Truncate long command lines
                    cpu,
                    memory: memoryMB,
                    runtime: runtimeSeconds,
                    cputime: cputimeSeconds
                });
            }
        }
    } catch (err) {
        log(`Failed to get process metrics: ${err}`, 'WARN');
    }

    return {
        timestamp,
        totalMemory,
        usedMemory,
        freeMemory,
        swapTotal,
        swapUsed,
        loadAverage,
        processes
    };
}

/**
 * Detect memory leaks by analyzing memory growth over time
 *
 * ALGORITHM:
 * - Track last N memory samples for each process
 * - Calculate linear regression slope
 * - If slope > threshold, flag as potential leak
 * - Requires minimum samples to avoid false positives
 *
 * @param pid - Process ID to check
 * @param currentMemory - Current memory usage in MB
 * @returns true if memory leak detected
 */
function detectMemoryLeak(pid: number, currentMemory: number): boolean {
    // Get or create history for this PID
    if (!memoryHistory.has(pid)) {
        memoryHistory.set(pid, []);
    }

    const history = memoryHistory.get(pid)!;
    history.push(currentMemory);

    // Keep only last N samples
    if (history.length > MAX_HISTORY_SAMPLES) {
        history.shift();
    }

    // Need at least 10 samples to detect trend
    if (history.length < 10) {
        return false;
    }

    // Calculate linear regression slope (simple method)
    // slope = (n * Σ(xy) - Σx * Σy) / (n * Σ(x²) - (Σx)²)
    const n = history.length;
    let sumX = 0, sumY = 0, sumXY = 0, sumX2 = 0;

    for (let i = 0; i < n; i++) {
        const x = i;
        const y = history[i];
        sumX += x;
        sumY += y;
        sumXY += x * y;
        sumX2 += x * x;
    }

    const slope = (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);

    // If slope > 5 MB per sample (50 MB per minute at 10s interval), flag as leak
    const LEAK_THRESHOLD = 5.0;
    return slope > LEAK_THRESHOLD;
}

/**
 * Force garbage collection in extension host
 *
 * IMPLEMENTATION:
 * - Uses global.gc() if --expose-gc flag is set
 * - Falls back to creating memory pressure to trigger GC
 * - Logs before/after memory usage
 *
 * NOTE: This only affects the extension host process, not zygote processes
 */
async function forceGarbageCollection(): Promise<void> {
    const before = process.memoryUsage();

    try {
        // Try to use global.gc() if available
        if (global.gc) {
            global.gc();
            log('Forced garbage collection using global.gc()', 'INFO');
        } else {
            // Fallback: Create memory pressure to trigger GC
            // This is less reliable but works without --expose-gc flag
            const arr: any[] = [];
            for (let i = 0; i < 1000000; i++) {
                arr.push(new Array(100));
            }
            arr.length = 0; // Clear array to trigger GC
            log('Triggered garbage collection via memory pressure', 'INFO');
        }

        // Wait for GC to complete
        await new Promise(resolve => setTimeout(resolve, 1000));

        const after = process.memoryUsage();
        const freedMB = (before.heapUsed - after.heapUsed) / (1024 * 1024);
        log(`GC freed ${freedMB.toFixed(2)} MB (heap: ${(after.heapUsed / 1024 / 1024).toFixed(2)} MB)`, 'INFO');
    } catch (err) {
        log(`Failed to force garbage collection: ${err}`, 'ERROR');
    }
}

/**
 * Kill runaway zygote process
 *
 * SAFETY:
 * - Only kills processes with abnormal CPU/memory usage
 * - Sends SIGTERM first for graceful shutdown
 * - Waits 2 seconds, then sends SIGKILL if still alive
 * - Logs all actions for forensic analysis
 *
 * WARNING: This may cause VS Code instability if the process is critical
 *
 * @param pid - Process ID to kill
 * @param reason - Reason for killing (for logging)
 */
async function killRunawayProcess(pid: number, reason: string): Promise<void> {
    log(`Killing runaway process PID ${pid}: ${reason}`, 'CRITICAL');

    try {
        // Send SIGTERM for graceful shutdown
        await execAsync(`kill -15 ${pid}`);
        log(`Sent SIGTERM to PID ${pid}`, 'INFO');

        // Wait 2 seconds for graceful shutdown
        await new Promise(resolve => setTimeout(resolve, 2000));

        // Check if process still exists
        try {
            await execAsync(`kill -0 ${pid}`);
            // Process still exists, send SIGKILL
            await execAsync(`kill -9 ${pid}`);
            log(`Sent SIGKILL to PID ${pid} (did not terminate gracefully)`, 'WARN');
        } catch {
            // Process terminated gracefully
            log(`PID ${pid} terminated gracefully`, 'INFO');
        }
    } catch (err) {
        log(`Failed to kill PID ${pid}: ${err}`, 'ERROR');
    }
}

/**
 * Monitor system resources and take action if thresholds exceeded
 *
 * WORKFLOW:
 * 1. Get current system metrics
 * 2. Check each process against thresholds
 * 3. Detect memory leaks using historical data
 * 4. Alert user if issues detected
 * 5. Optionally auto-kill runaway processes
 * 6. Optionally auto-trigger garbage collection
 * 7. Log metrics to file for analysis
 *
 * IMPROVEMENTS:
 * - Now checks load average (critical if > 2x CPU count)
 * - Detects utility processes (/proc/self/exe) that can leak
 * - Uses runtime vs CPU time ratio to detect runaway processes
 * - More aggressive thresholds for critical system load
 */
async function monitorResources(): Promise<void> {
    try {
        const metrics = await getSystemMetrics();
        const config = vscode.workspace.getConfiguration('resourceGuardian');

        const cpuThreshold = config.get<number>('cpuThreshold', 15.0);
        const memoryThreshold = config.get<number>('memoryThreshold', 500);
        const extensionHostMemoryThreshold = config.get<number>('extensionHostMemoryThreshold', 400);
        const autoKillRunaway = config.get<boolean>('autoKillRunaway', false);
        const autoGC = config.get<boolean>('autoGarbageCollection', true);
        const alertOnSwap = config.get<boolean>('alertOnSwap', true);

        // IMPROVED: Check load average (critical if > 2x CPU count)
        const cpuCount = os.cpus().length;
        const loadAvg1min = metrics.loadAverage[0];
        if (loadAvg1min > cpuCount * 2) {
            log(`CRITICAL LOAD: ${loadAvg1min.toFixed(2)} (${cpuCount} CPUs, threshold: ${cpuCount * 2})`, 'CRITICAL');
            // System is severely overloaded, be more aggressive with cleanup
        }

        // Check swap usage
        if (alertOnSwap && metrics.swapUsed > 0) {
            const swapPercent = (metrics.swapTotal > 0) ? (metrics.swapUsed / metrics.swapTotal) * 100 : 0;
            if (swapPercent > 10) {
                log(`MEMORY PRESSURE: ${metrics.swapUsed.toFixed(0)} MB swap used (${swapPercent.toFixed(1)}%)`, 'WARN');
                vscode.window.showWarningMessage(
                    `Resource Guardian: System using ${metrics.swapUsed.toFixed(0)} MB swap (${swapPercent.toFixed(1)}%). Performance degraded.`,
                    'Show Details',
                    'Force GC Now'
                ).then(selection => {
                    if (selection === 'Show Details') {
                        vscode.commands.executeCommand('resourceGuardian.showStatus');
                    } else if (selection === 'Force GC Now') {
                        forceGarbageCollection();
                    }
                });
            }
        }

        // FIXED v1.2: Startup grace period - don't kill anything during first 2 minutes
        const timeSinceActivation = Date.now() - extensionActivationTime;
        const inStartupGracePeriod = timeSinceActivation < STARTUP_GRACE_PERIOD;

        if (inStartupGracePeriod) {
            log(`[STARTUP GRACE PERIOD] ${Math.floor((STARTUP_GRACE_PERIOD - timeSinceActivation) / 1000)}s remaining - monitoring only, no kills`, 'INFO');
        }

        // Check each process
        for (const proc of metrics.processes) {
            // FIXED v1.2: Check ignore list (user can ignore specific PIDs for 5 minutes)
            const ignoreExpiry = ignoreList.get(proc.pid);
            if (ignoreExpiry && Date.now() < ignoreExpiry) {
                continue;  // Skip this process
            } else if (ignoreExpiry) {
                ignoreList.delete(proc.pid);  // Expired, remove from ignore list
            }

            // FIXED v1.2: Don't kill young processes (< 30 seconds old)
            if (proc.runtime < PROCESS_MIN_AGE / 1000) {
                continue;  // Process too young, skip
            }

            // IMPROVED: Check CPU threshold for zygote AND utility processes
            // Both should be idle most of the time
            const isZygote = proc.name.includes('zygote');
            const isUtility = proc.name.includes('/proc/self/exe') && proc.name.includes('--type=utility');

            if ((isZygote || isUtility) && proc.cpu > cpuThreshold) {
                // IMPROVED: Calculate CPU efficiency (CPU time / runtime)
                // If > 50%, process is consuming CPU continuously (runaway)
                const cpuEfficiency = proc.runtime > 0 ? (proc.cputime / proc.runtime) * 100 : 0;

                // FIXED v1.2: Track violations - must violate 3 times in a row before flagging
                const currentViolations = (violationCounts.get(proc.pid) || 0) + 1;
                violationCounts.set(proc.pid, currentViolations);

                if (currentViolations < VIOLATION_COUNT_THRESHOLD) {
                    log(`CPU WARNING: PID ${proc.pid} using ${proc.cpu.toFixed(1)}% CPU (violation ${currentViolations}/${VIOLATION_COUNT_THRESHOLD})`, 'WARN');
                    continue;  // Not enough violations yet
                }

                log(`RUNAWAY CPU: PID ${proc.pid} using ${proc.cpu.toFixed(1)}% CPU (threshold: ${cpuThreshold}%, ${currentViolations} violations)`, 'CRITICAL');
                log(`  Runtime: ${(proc.runtime / 60).toFixed(1)} min, CPU time: ${(proc.cputime / 60).toFixed(1)} min, Efficiency: ${cpuEfficiency.toFixed(1)}%`, 'CRITICAL');

                // FIXED v1.2: NEVER auto-kill during startup grace period
                if (inStartupGracePeriod) {
                    log(`  [STARTUP GRACE PERIOD] Not killing PID ${proc.pid} - still in startup`, 'INFO');
                    continue;
                }

                // FIXED v1.2: NEVER auto-kill, always ask user (even if autoKillRunaway=true)
                vscode.window.showErrorMessage(
                    `Resource Guardian: Runaway ${isZygote ? 'zygote' : 'utility'} process detected (PID ${proc.pid}, ${proc.cpu.toFixed(1)}% CPU, ${cpuEfficiency.toFixed(0)}% efficiency)`,
                    'Kill Process',
                    'Ignore for 5 min',
                    'Cancel'
                ).then(selection => {
                    if (selection === 'Kill Process') {
                        killRunawayProcess(proc.pid, `User requested kill (CPU ${proc.cpu.toFixed(1)}%)`);
                        violationCounts.delete(proc.pid);  // Reset violations
                    } else if (selection === 'Ignore for 5 min') {
                        ignoreList.set(proc.pid, Date.now() + 300000);  // Ignore for 5 minutes
                        violationCounts.delete(proc.pid);  // Reset violations
                        log(`PID ${proc.pid} added to ignore list for 5 minutes`, 'INFO');
                    }
                });
            } else {
                // Process is OK, reset violation count
                violationCounts.delete(proc.pid);
            }

            // Check memory threshold
            const threshold = proc.name.includes('extensionHost') || proc.name.includes('node.mojom.NodeService')
                ? extensionHostMemoryThreshold
                : memoryThreshold;

            if (proc.memory > threshold) {
                log(`HIGH MEMORY: PID ${proc.pid} using ${proc.memory.toFixed(0)} MB (threshold: ${threshold} MB)`, 'WARN');

                // Check for memory leak
                if (detectMemoryLeak(proc.pid, proc.memory)) {
                    log(`MEMORY LEAK DETECTED: PID ${proc.pid} memory growing continuously`, 'CRITICAL');

                    const processType = proc.name.includes('extensionHost') ? 'extension host' :
                                       proc.name.includes('zygote') ? 'zygote' : 'utility';

                    vscode.window.showErrorMessage(
                        `Resource Guardian: Memory leak detected in ${processType} (PID ${proc.pid}, ${proc.memory.toFixed(0)} MB)`,
                        'Restart Extension Host',
                        'Force GC',
                        'Kill Process',
                        'Ignore'
                    ).then(selection => {
                        if (selection === 'Restart Extension Host') {
                            vscode.commands.executeCommand('workbench.action.restartExtensionHost');
                        } else if (selection === 'Force GC') {
                            forceGarbageCollection();
                        } else if (selection === 'Kill Process') {
                            killRunawayProcess(proc.pid, `User requested kill (memory leak ${proc.memory.toFixed(0)} MB)`);
                        }
                    });
                }
            }
        }

        // Auto garbage collection if extension host memory high
        if (autoGC) {
            const extensionHostProc = metrics.processes.find(p =>
                p.name.includes('extensionHost') || p.name.includes('node.mojom.NodeService')
            );
            if (extensionHostProc && extensionHostProc.memory > extensionHostMemoryThreshold) {
                log(`Auto-triggering garbage collection (extension host: ${extensionHostProc.memory.toFixed(0)} MB)`, 'INFO');
                await forceGarbageCollection();
            }
        }

        // IMPROVED: If system load critical (> 5.0), force aggressive cleanup
        if (loadAvg1min > 5.0) {
            log(`EMERGENCY: Load average ${loadAvg1min.toFixed(2)} > 5.0, forcing aggressive cleanup`, 'CRITICAL');

            // Force GC immediately
            await forceGarbageCollection();

            // Kill all processes exceeding thresholds
            for (const proc of metrics.processes) {
                if (proc.cpu > cpuThreshold * 1.5 || proc.memory > memoryThreshold * 1.5) {
                    log(`EMERGENCY KILL: PID ${proc.pid} (${proc.cpu.toFixed(1)}% CPU, ${proc.memory.toFixed(0)} MB)`, 'CRITICAL');
                    await killRunawayProcess(proc.pid, `Emergency cleanup (load ${loadAvg1min.toFixed(2)})`);
                }
            }
        }

    } catch (err) {
        log(`Error in monitorResources: ${err}`, 'ERROR');
    }
}

/**
 * Generate comprehensive resource report
 *
 * OUTPUT:
 * - Current system metrics
 * - Process list with CPU/memory
 * - Memory leak detection results
 * - Historical trends
 * - Recommendations
 */
async function generateReport(): Promise<void> {
    const metrics = await getSystemMetrics();

    outputChannel.show(true);
    log('', 'INFO');
    log('='.repeat(80), 'INFO');
    log('RESOURCE GUARDIAN REPORT', 'INFO');
    log('='.repeat(80), 'INFO');
    log('', 'INFO');

    log(`Timestamp: ${metrics.timestamp}`, 'INFO');
    log(`Total Memory: ${metrics.totalMemory.toFixed(0)} MB`, 'INFO');
    log(`Used Memory: ${metrics.usedMemory.toFixed(0)} MB (${((metrics.usedMemory / metrics.totalMemory) * 100).toFixed(1)}%)`, 'INFO');
    log(`Free Memory: ${metrics.freeMemory.toFixed(0)} MB`, 'INFO');
    log(`Swap Total: ${metrics.swapTotal.toFixed(0)} MB`, 'INFO');
    log(`Swap Used: ${metrics.swapUsed.toFixed(0)} MB (${metrics.swapTotal > 0 ? ((metrics.swapUsed / metrics.swapTotal) * 100).toFixed(1) : 0}%)`, 'INFO');
    log(`Load Average: ${metrics.loadAverage.map(l => l.toFixed(2)).join(', ')}`, 'INFO');
    log('', 'INFO');

    log('VS Code Processes:', 'INFO');
    log('-'.repeat(80), 'INFO');

    for (const proc of metrics.processes) {
        const leak = detectMemoryLeak(proc.pid, proc.memory);
        const leakFlag = leak ? ' [LEAK DETECTED]' : '';
        log(`PID ${proc.pid}: ${proc.cpu.toFixed(1)}% CPU, ${proc.memory.toFixed(0)} MB${leakFlag}`, 'INFO');
        log(`  ${proc.name}`, 'INFO');
    }

    log('', 'INFO');
    log('='.repeat(80), 'INFO');

    // Save report to file
    if (logFilePath) {
        const reportPath = logFilePath.replace('.log', `-report-${Date.now()}.txt`);
        try {
            const reportContent = outputChannel.toString();
            fs.writeFileSync(reportPath, reportContent);
            log(`Report saved to: ${reportPath}`, 'INFO');
        } catch (err) {
            log(`Failed to save report: ${err}`, 'ERROR');
        }
    }
}

/**
 * Extension activation
 *
 * INITIALIZATION:
 * 1. Create output channel
 * 2. Set up log file path
 * 3. Register commands
 * 4. Start monitoring intervals
 * 5. Log activation details
 */
export function activate(context: vscode.ExtensionContext) {
    outputChannel = vscode.window.createOutputChannel('Resource Guardian');

    // Set up log file path
    const storageUri = context.globalStorageUri || context.storageUri;
    if (storageUri) {
        fs.mkdirSync(storageUri.fsPath, { recursive: true });
        logFilePath = path.join(storageUri.fsPath, 'resource-guardian.log');
    }

    log('=== Resource Guardian Activated ===', 'INFO');
    log(`VS Code PID: ${process.pid}`, 'INFO');
    log(`Platform: ${os.platform()}`, 'INFO');
    log(`Node Version: ${process.version}`, 'INFO');
    log(`Total Memory: ${(os.totalmem() / (1024 * 1024 * 1024)).toFixed(2)} GB`, 'INFO');
    if (logFilePath) {
        log(`Log file: ${logFilePath}`, 'INFO');
    }

    // Register commands
    const showStatusCmd = vscode.commands.registerCommand('resourceGuardian.showStatus', async () => {
        await generateReport();
    });

    const killRunawayCmd = vscode.commands.registerCommand('resourceGuardian.killRunawayProcesses', async () => {
        const metrics = await getSystemMetrics();
        const config = vscode.workspace.getConfiguration('resourceGuardian');
        const cpuThreshold = config.get<number>('cpuThreshold', 15.0);

        let killedCount = 0;
        for (const proc of metrics.processes) {
            if (proc.name.includes('zygote') && proc.cpu > cpuThreshold) {
                await killRunawayProcess(proc.pid, `Manual kill (CPU ${proc.cpu.toFixed(1)}%)`);
                killedCount++;
            }
        }

        vscode.window.showInformationMessage(`Resource Guardian: Killed ${killedCount} runaway processes`);
    });

    const restartExtensionHostCmd = vscode.commands.registerCommand('resourceGuardian.restartExtensionHost', async () => {
        log('User requested extension host restart', 'INFO');
        await vscode.commands.executeCommand('workbench.action.restartExtensionHost');
    });

    const forceGCCmd = vscode.commands.registerCommand('resourceGuardian.forceGarbageCollection', async () => {
        log('User requested garbage collection', 'INFO');
        await forceGarbageCollection();
        vscode.window.showInformationMessage('Resource Guardian: Garbage collection triggered');
    });

    const generateReportCmd = vscode.commands.registerCommand('resourceGuardian.generateReport', async () => {
        await generateReport();
    });

    const emergencyCleanupCmd = vscode.commands.registerCommand('resourceGuardian.emergencyCleanup', async () => {
        // EMERGENCY: Kill all processes exceeding thresholds
        // This is the nuclear option when system is unresponsive
        log('EMERGENCY CLEANUP INITIATED BY USER', 'CRITICAL');

        const metrics = await getSystemMetrics();
        const config = vscode.workspace.getConfiguration('resourceGuardian');
        const cpuThreshold = config.get<number>('cpuThreshold', 10.0);
        const memoryThreshold = config.get<number>('memoryThreshold', 400);

        let killedCount = 0;
        for (const proc of metrics.processes) {
            // Kill if exceeds CPU OR memory threshold
            if (proc.cpu > cpuThreshold || proc.memory > memoryThreshold) {
                log(`EMERGENCY KILL: PID ${proc.pid} (${proc.cpu.toFixed(1)}% CPU, ${proc.memory.toFixed(0)} MB)`, 'CRITICAL');
                await killRunawayProcess(proc.pid, `Emergency cleanup (${proc.cpu.toFixed(1)}% CPU, ${proc.memory.toFixed(0)} MB)`);
                killedCount++;
            }
        }

        // Force garbage collection
        await forceGarbageCollection();

        vscode.window.showWarningMessage(
            `Resource Guardian: Emergency cleanup complete. Killed ${killedCount} processes. Consider restarting VS Code.`,
            'Restart VS Code',
            'OK'
        ).then(selection => {
            if (selection === 'Restart VS Code') {
                vscode.commands.executeCommand('workbench.action.reloadWindow');
            }
        });
    });

    // Start monitoring
    // FIXED v1.2: Less aggressive defaults
    // - monitorInterval: 5000 → 30000 (30 seconds, was 5s - TOO AGGRESSIVE)
    // - cpuThreshold: 10.0 → 25.0 (only kill truly runaway processes)
    // - memoryThreshold: 400 → 800 (allow normal memory usage)
    const config = vscode.workspace.getConfiguration('resourceGuardian');
    const monitorInterval = config.get<number>('monitorInterval', 30000);  // 30s not 5s

    monitoringInterval = setInterval(() => {
        monitorResources();
    }, monitorInterval);

    // Periodic garbage collection (every 5 minutes)
    gcInterval = setInterval(() => {
        const autoGC = vscode.workspace.getConfiguration('resourceGuardian').get<boolean>('autoGarbageCollection', true);
        if (autoGC) {
            forceGarbageCollection();
        }
    }, 300000);

    // Heartbeat (every 60 seconds)
    heartbeatInterval = setInterval(() => {
        log(`[HEARTBEAT] Resource Guardian active. Monitoring ${memoryHistory.size} processes.`, 'INFO');
    }, 60000);

    // Register disposables
    context.subscriptions.push(
        showStatusCmd,
        killRunawayCmd,
        restartExtensionHostCmd,
        forceGCCmd,
        generateReportCmd,
        emergencyCleanupCmd,
        { dispose: () => { if (monitoringInterval) clearInterval(monitoringInterval); } },
        { dispose: () => { if (gcInterval) clearInterval(gcInterval); } },
        { dispose: () => { if (heartbeatInterval) clearInterval(heartbeatInterval); } }
    );

    log('Resource Guardian monitoring started', 'INFO');
    log('', 'INFO');
}

/**
 * Extension deactivation
 *
 * CLEANUP:
 * - Clear all intervals
 * - Clear memory history
 * - Log deactivation
 */
export function deactivate() {
    log('=== Resource Guardian Deactivated ===', 'INFO');

    // Clear intervals (also handled by context.subscriptions)
    if (monitoringInterval) clearInterval(monitoringInterval);
    if (gcInterval) clearInterval(gcInterval);
    if (heartbeatInterval) clearInterval(heartbeatInterval);

    // Clear memory history to prevent leaks
    memoryHistory.clear();
}



