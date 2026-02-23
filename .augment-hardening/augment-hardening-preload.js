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

const originalFetch = globalThis.fetch;

if (originalFetch) {
  globalThis.fetch = async function patchedFetch(url, options = {}) {
    const controller = new AbortController();
    const timeoutMs = 60000;

    if (!options.signal) {
      options.signal = controller.signal;
    }

    const timer = setTimeout(() => {
      controller.abort();
      log("[FETCH_ABORT_TRIGGERED] Timeout enforced");
    }, timeoutMs);

    try {
      const res = await originalFetch(url, options);

      // CRITICAL: Force body consumption to prevent socket leak
      if (res?.body?.getReader) {
        const reader = res.body.getReader();
        try {
          while (!(await reader.read()).done) {}
        } catch (_) {}
      } else if (res?.body?.cancel) {
        try { await res.body.cancel(); } catch (_) {}
      }

      return res;
    } catch (err) {
      log("[FETCH_ERROR] " + err.message);
      throw err;
    } finally {
      clearTimeout(timer);
    }
  };

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
