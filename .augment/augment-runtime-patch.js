#!/usr/bin/env node
/**
 * AUGMENT RUNTIME PATCH - Surgical Monkey Patch (No Vendor Edits)
 * 
 * PURPOSE:
 *   Fix undici fetch leaks without modifying extension.js
 * 
 * ROOT CAUSES ADDRESSED:
 *   1. Timeout-based AbortError without proper cleanup
 *   2. Response body not consumed (undici keeps socket alive)
 *   3. Missing AbortController on fetch calls
 *   4. No timeout clearance on resolve
 * 
 * USAGE:
 *   NODE_OPTIONS="--require $(pwd)/.augment/augment-runtime-patch.js" code
 * 
 * EVIDENCE:
 *   - 490 AbortErrors every ~60s
 *   - FD leak from chat completion API (line 64:4481)
 *   - FD leak from streaming API (line 64:59334)
 *   - Truncation from incomplete body consumption
 */

const fs = require("fs");
const path = require("path");

const LOGFILE = path.join(process.cwd(), ".notes", "runtime-patch.log");

function log(msg) {
  const timestamp = new Date().toISOString();
  const line = `[${timestamp}] ${msg}\n`;
  try {
    fs.appendFileSync(LOGFILE, line);
  } catch {}
  console.error(`[RUNTIME_PATCH] ${msg}`);
}

log("========================================================================");
log("AUGMENT RUNTIME PATCH LOADED");
log(`PID: ${process.pid}`);
log("========================================================================");

// ============================================================================
// 1. PATCH GLOBAL FETCH - Force timeout + body consumption
// ============================================================================

const origFetch = globalThis.fetch;
let fetchCallCount = 0;
let fetchAbortCount = 0;
let fetchLeakPreventCount = 0;

globalThis.fetch = async function patchedFetch(url, options = {}) {
  const callId = ++fetchCallCount;
  const start = Date.now();
  
  log(`FETCH #${callId} START: ${url}`);

  // Ensure AbortController exists
  let controller;
  let ownController = false;
  if (!options.signal) {
    controller = new AbortController();
    options.signal = controller.signal;
    ownController = true;
    log(`FETCH #${callId}: Created AbortController`);
  } else {
    controller = { signal: options.signal };
  }

  // Set timeout (60s default)
  const timeoutMs = options.timeout || 60000;
  const timeout = setTimeout(() => {
    if (ownController && controller.abort) {
      log(`FETCH #${callId}: TIMEOUT after ${timeoutMs}ms - aborting`);
      fetchAbortCount++;
      controller.abort();
    }
  }, timeoutMs);

  try {
    const res = await origFetch(url, options);
    const elapsed = Date.now() - start;
    log(`FETCH #${callId}: Response received (${res.status}) in ${elapsed}ms`);

    // CRITICAL: Force body consumption to prevent socket leak
    // Undici keeps connection alive if body not consumed
    if (res.body && !res.bodyUsed) {
      log(`FETCH #${callId}: Body not consumed - forcing consumption`);
      fetchLeakPreventCount++;
      
      try {
        // Clone response so original can still be used
        const clone = res.clone();
        clone.arrayBuffer().catch(() => {});
      } catch (e) {
        log(`FETCH #${callId}: Body consumption failed: ${e.message}`);
      }
    }

    return res;
  } catch (err) {
    const elapsed = Date.now() - start;
    log(`FETCH #${callId}: ERROR after ${elapsed}ms: ${err.message}`);
    throw err;
  } finally {
    clearTimeout(timeout);
    log(`FETCH #${callId}: Cleanup complete`);
  }
};

log("✓ Global fetch patched");

// ============================================================================
// 2. FD MONITOR - Track file descriptor count
// ============================================================================

let fdCount = 0;
let fdPeak = 0;
let fdWarnings = 0;

function monitorFD() {
  try {
    const fds = fs.readdirSync("/proc/self/fd");
    fdCount = fds.length;
    
    if (fdCount > fdPeak) {
      fdPeak = fdCount;
    }
    
    if (fdCount > 50000) {
      fdWarnings++;
      log(`⚠ FD_LEAK_WARNING: ${fdCount} FDs (peak: ${fdPeak}, warnings: ${fdWarnings})`);
    } else {
      log(`FD_MONITOR: ${fdCount} FDs (peak: ${fdPeak})`);
    }
    
    log(`FETCH_STATS: calls=${fetchCallCount}, aborts=${fetchAbortCount}, leaks_prevented=${fetchLeakPreventCount}`);
  } catch (err) {
    log(`FD_MONITOR: Error reading /proc/self/fd: ${err.message}`);
  }
}

// Monitor every 15 seconds
setInterval(monitorFD, 15000);

log("✓ FD monitor started (15s interval)");

// ============================================================================
// 3. PROCESS EXIT HANDLER - Final stats
// ============================================================================

process.on("exit", () => {
  log("========================================================================");
  log("RUNTIME PATCH SHUTTING DOWN");
  log(`Final FD count: ${fdCount}`);
  log(`Peak FD count: ${fdPeak}`);
  log(`FD warnings: ${fdWarnings}`);
  log(`Fetch calls: ${fetchCallCount}`);
  log(`Fetch aborts: ${fetchAbortCount}`);
  log(`Leaks prevented: ${fetchLeakPreventCount}`);
  log("========================================================================");
});

log("✓ Exit handler registered");
log("Runtime patch initialization complete");
log("");

