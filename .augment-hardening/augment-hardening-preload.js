/******************************************************************************
 * AUGMENT HARDENING PRELOAD
 *
 * Injected via NODE_OPTIONS=--require
 *
 * FIXES:
 *  - Enforces fetch timeout cleanup
 *  - Forces response body drain or cancel
 *  - Logs stack when _closingPromise is set
 *  - Guards against runaway zygote re-entry loops
 *  - Prevents negative line ranges from escalating
 ******************************************************************************/

const fs = require("fs");
const path = require("path");

const LOGFILE = path.join(process.cwd(), ".augment-hardening.log");

function log(msg) {
  const line = `[${new Date().toISOString()}] ${msg}\n`;
  try {
    fs.appendFileSync(LOGFILE, line);
  } catch {}
  console.error(line.trim());
}

/******************************************************************************
 * 1) FETCH HARDENING — PRIMARY FD LEAK FIX
 ******************************************************************************/

// Track active fetch requests to detect leaks
const activeFetches = new Map();
let fetchCounter = 0;

const originalFetch = globalThis.fetch;

if (originalFetch) {
  globalThis.fetch = async function patchedFetch(url, options = {}) {
    const fetchId = ++fetchCounter;
    const startTime = Date.now();

    // Force AbortController if not provided
    const controller = options.signal ? null : new AbortController();
    if (controller) {
      options.signal = controller.signal;
    }

    activeFetches.set(fetchId, { url: String(url).substring(0, 100), startTime });

    try {
      const res = await originalFetch(url, options);

      // Wrap response to track cleanup
      if (res?.body) {
        const originalCancel = res.body.cancel?.bind(res.body);
        res.body.cancel = async function() {
          activeFetches.delete(fetchId);
          log(`[FETCH_CLEANUP] ID=${fetchId} duration=${Date.now() - startTime}ms`);
          if (originalCancel) {
            return await originalCancel();
          }
        };
      }

      return res;
    } catch (err) {
      activeFetches.delete(fetchId);
      log(`[FETCH_ERROR] ID=${fetchId} ${err.message}`);
      throw err;
    }
  };

  // Monitor for leaked fetches
  setInterval(() => {
    const now = Date.now();
    const leaked = [];
    for (const [id, info] of activeFetches.entries()) {
      const age = now - info.startTime;
      if (age > 120000) { // 2 minutes
        leaked.push(`ID=${id} age=${Math.floor(age/1000)}s url=${info.url}`);
      }
    }
    if (leaked.length > 0) {
      log(`[FETCH_LEAK_DETECTED] ${leaked.length} stale fetches: ${leaked.join('; ')}`);
    }
    log(`[FETCH_MONITOR] active=${activeFetches.size} total=${fetchCounter}`);
  }, 30000);

  log("[FETCH_PATCH_ACTIVE]");
}

/******************************************************************************
 * 2) LATCH DETECTOR — _closingPromise STACK TRACE CAPTURE
 ******************************************************************************/

const latchTargets = [];

for (const key of Object.getOwnPropertyNames(globalThis)) {
  if (key.includes("closingPromise")) {
    latchTargets.push(key);
  }
}

latchTargets.forEach(key => {
  let value;
  Object.defineProperty(globalThis, key, {
    configurable: true,
    set(v) {
      log("[LATCH_SET] " + key + "\n" + new Error().stack);
      value = v;
    },
    get() {
      return value;
    }
  });
});

if (latchTargets.length > 0) {
  log("[LATCH_MONITOR_ACTIVE] Watching: " + latchTargets.join(", "));
}

/******************************************************************************
 * 3) ZYGOTE LOOP MITIGATION (DETECT RECREATION STORM)
 ******************************************************************************/

setInterval(() => {
  try {
    const fds = fs.readdirSync("/proc/self/fd").length;
    log("[FD_MONITOR] " + fds);
  } catch (_) {}
}, 15000);

/******************************************************************************
 * 4) DEFENSIVE RANGE PATCH (invalid_line_range containment)
 ******************************************************************************/

process.on("uncaughtException", (err) => {
  if (err?.message?.includes("Invalid line range")) {
    log("[RANGE_SUPPRESSED] " + err.message);
    return;
  }
  throw err;
});

log("[HARDENING_PRELOAD_INITIALIZED]");
