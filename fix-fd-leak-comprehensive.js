/**
 * fix-fd-leak-comprehensive.js
 *
 * WHAT: Comprehensive fix for FD leak that persists after VS Code reload
 * WHY: Window reload did NOT fix the issue - FD count INCREASED from 53,976 to 178,439
 * HOW: Document findings, provide actionable fixes, create monitoring script
 *
 * FINDINGS FROM VERIFICATION:
 * - FD count: 178,439 (WORSE after reload)
 * - VS Code: 52,563 FDs (PRIMARY LEAK SOURCE)
 * - Firefox: 50,568 FDs (SECONDARY LEAK SOURCE)
 * - Swap: 1.4GB (INCREASED from 1.3GB)
 * - Load: 2.94 (IMPROVED from 4.98, but still elevated)
 *
 * ROOT CAUSE:
 * - VS Code reload did NOT close file descriptors
 * - Multiple VS Code processes (14 total)
 * - Runaway process PID 2069717: 25% CPU, 1.4GB RAM
 * - Extension Host + Language Servers + Zygotes all contributing
 *
 * RECOMMENDED FIX:
 * - COMPLETE VS Code restart (not just window reload)
 * - Kill all VS Code processes
 * - Restart VS Code fresh
 * - Monitor FD count after restart
 */

const fs = require("fs");
const path = require("path");
const { execSync } = require("child_process");

// ---------------- LOGGING SETUP ----------------

const LOGDIR = ".notes";
const logFile = path.join(LOGDIR, `fix-fd-leak-${Date.now()}.log`);

function log(msg) {
    console.log(msg);
    fs.appendFileSync(logFile, msg + "\n");
}

log("STEP 1: Documenting FD leak findings");

// ---------------- DOCUMENT CURRENT STATE ----------------

log("\n=== CURRENT STATE (POST-RELOAD) ===");
log("FD count: 178,439 (threshold: 50,000)");
log("VS Code FDs: 52,563");
log("Firefox FDs: 50,568");
log("Swap usage: 1.4GB");
log("Load average: 2.94");
log("");
log("COMPARISON TO PRE-RELOAD:");
log("  FD count: 53,976 → 178,439 (INCREASED 3.3x)");
log("  Swap: 1.3GB → 1.4GB (INCREASED)");
log("  Load: 4.98 → 2.94 (IMPROVED)");

// ---------------- ANALYZE VS CODE PROCESSES ----------------

log("\n=== VS CODE PROCESS ANALYSIS ===");

try {
    const vscodeProcs = execSync("ps aux | grep '/usr/share/code/code' | grep -v grep | wc -l", { encoding: "utf8" }).trim();
    log(`Total VS Code processes: ${vscodeProcs}`);
    
    const procDetails = execSync("ps aux | grep '/usr/share/code/code' | grep -v grep | awk '{print $2, $3, $4, $6, $11}'", { encoding: "utf8" });
    log("\nProcess details (PID, CPU%, MEM%, RSS, CMD):");
    log(procDetails);
} catch (err) {
    log(`ERROR: Cannot analyze VS Code processes: ${err.message}`);
}

// ---------------- ANALYZE FD TYPES ----------------

log("\n=== FD TYPE BREAKDOWN ===");
log("WHAT: Categorize file descriptors by type");
log("WHY: Identify which FD types are leaking");
log("HOW: Use lsof to count FD types");

try {
    const fdTypes = execSync("timeout 10 lsof 2>/dev/null | awk '{print $5}' | sort | uniq -c | sort -rn | head -10", { encoding: "utf8" });
    log("Top FD types:");
    log(fdTypes);
} catch (err) {
    log(`ERROR: Cannot analyze FD types: ${err.message}`);
}

// ---------------- RECOMMENDED ACTIONS ----------------

log("\n=== RECOMMENDED ACTIONS ===");
log("");
log("ACTION 1: COMPLETE VS Code restart (NOT just window reload)");
log("  WHY: Window reload did NOT close file descriptors");
log("  HOW:");
log("    1. Close all VS Code windows");
log("    2. Kill all VS Code processes: pkill -9 code");
log("    3. Wait 5 seconds");
log("    4. Restart VS Code");
log("    5. Re-run verification script");
log("");
log("ACTION 2: Check Augment extension settings");
log("  WHY: Chat input completion was identified as root cause");
log("  HOW:");
log("    cat ~/.augment/settings.json | grep enableChatInputCompletions");
log("  EXPECTED: \"augment.completions.enableChatInputCompletions\": false");
log("");
log("ACTION 3: Monitor FD count after restart");
log("  WHY: Verify restart actually fixes the leak");
log("  HOW:");
log("    watch -n 5 'lsof 2>/dev/null | wc -l'");
log("  EXPECTED: FD count < 10,000 and stable");
log("");
log("ACTION 4: If FD leak persists after restart");
log("  WHY: Issue may be system-level, not just VS Code");
log("  HOW:");
log("    1. Check Firefox FD count (currently 50,568)");
log("    2. Restart Firefox if needed");
log("    3. Check for other runaway processes");
log("    4. Consider system reboot as last resort");

// ---------------- CREATE MONITORING SCRIPT ----------------

log("\n=== CREATING MONITORING SCRIPT ===");

const monitorScript = `#!/bin/bash
# monitor-fd-leak.sh
# WHAT: Monitor file descriptor count every 5 seconds
# WHY: Track FD leak in real-time
# HOW: Loop lsof count, log to file

LOGFILE=".notes/fd-monitor-$(date +%Y%m%d-%H%M%S).log"

echo "Monitoring FD count (Ctrl+C to stop)..."
echo "Log file: $LOGFILE"
echo ""

while true; do
    TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
    FD_COUNT=$(lsof 2>/dev/null | wc -l)
    echo "$TIMESTAMP - FD count: $FD_COUNT" | tee -a "$LOGFILE"
    sleep 5
done
`;

const monitorScriptPath = "monitor-fd-leak.sh";
fs.writeFileSync(monitorScriptPath, monitorScript, { mode: 0o755 });
log(`Created monitoring script: ${monitorScriptPath}`);

log(`\nFull report written to: ${logFile}`);

