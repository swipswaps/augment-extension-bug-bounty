// ============================================================================
// Firefox Performance-Oriented user.js
// Target: Fedora Linux, XFCE, X11, Mesa, Radeon GPU, Firefox 147+
// Philosophy: Throughput + Stability (NOT privacy hardening)
// ============================================================================
//
// IMPORTANT:
// - Read at Firefox startup only
// - prefs.js will be regenerated
// - Restart Firefox after changes
//
// Version: 2.0
// Updated: 2026-02-06
// Optimized for: X11 + Mesa + xfwm4 compositor (GPU threading contention fix)
//
// ============================================================================

// ---------------------------------------------------------------------------
// GRAPHICS / RENDERING
// ---------------------------------------------------------------------------

// Avoid early GL race on Mesa
user_pref("gfx.gl.early-init", false);

// Allow Firefox to manage WebRender intelligently
user_pref("gfx.webrender.all", true);
user_pref("gfx.webrender.compositor", true);

// Do not block startup on GPU
user_pref("gfx.webrender.wait-for-gpu", false);

// CRITICAL: Disable GPU thread on X11+Mesa to avoid contention
// (X11 compositor + Mesa GL threading + Firefox GPU thread = 2.6s delays)
user_pref("gfx.webrender.enable-gpu-thread", false);

// Allow acceleration without forcing unsafe paths
user_pref("layers.acceleration.force-enabled", true);

// CRITICAL: Disable GL multithreading to avoid contention with Mesa
// (Mesa has internal threading; Firefox threading creates conflicts)
user_pref("gfx.gl.multithreaded", false);

// ---------------------------------------------------------------------------
// MEDIA / VAAPI
// ---------------------------------------------------------------------------

// Enable VAAPI but KEEP software fallback
user_pref("media.ffmpeg.vaapi.enabled", true);
user_pref("media.ffmpeg.vaapi.x11.enabled", true);
user_pref("media.ffmpeg.vaapi-drm-display.enabled", true);

// Keep fallback codecs for smooth recovery
user_pref("media.ffvpx.enabled", true);
user_pref("media.rdd-vpx.enabled", true);

// ---------------------------------------------------------------------------
// PROCESS MODEL / IPC
// ---------------------------------------------------------------------------

// CRITICAL: Reduce process count to minimize GPU/CPU contention
// (8+ processes caused WaitFlushedEvent delays; 4 is optimal for X11+Mesa)
user_pref("dom.ipc.processCount", 4);
user_pref("dom.ipc.processCount.web", 4);

// Keep minimal warm processes (balance between latency and contention)
user_pref("dom.ipc.keepProcessesAlive.web", 1);

// Allow speculative process prelaunch (faster navigation)
user_pref("dom.ipc.processPrelaunch.enabled", true);

// ---------------------------------------------------------------------------
// MEMORY / GC
// ---------------------------------------------------------------------------

// Background timer sanity
user_pref("dom.min_background_timeout_value", 1000);
user_pref("dom.timeout.background_throttling_max_budget", 5000);

// Default GC behavior is already tuned; do not over-constrain
// (Removing artificial GC pressure improves smoothness)

// ---------------------------------------------------------------------------
// CACHE
// ---------------------------------------------------------------------------

user_pref("browser.cache.disk.enable", true);
user_pref("browser.cache.disk.capacity", 262144);
user_pref("browser.cache.disk.smart_size.enabled", true);

// ---------------------------------------------------------------------------
// SESSIONSTORE
// ---------------------------------------------------------------------------

// Reasonable write interval
user_pref("browser.sessionstore.interval", 30000);

// ---------------------------------------------------------------------------
// TELEMETRY
// ---------------------------------------------------------------------------

// Leave Fedora defaults (already minimal)
user_pref("toolkit.telemetry.enabled", false);
user_pref("toolkit.telemetry.unified", false);

// ---------------------------------------------------------------------------
// NETWORK
// ---------------------------------------------------------------------------

// Restore speculative optimizations (performance-critical)
// CRITICAL: Force enable network prefetching (overrides policies)
user_pref("network.prefetch-next", true);
user_pref("network.dns.disablePrefetch", false);
user_pref("network.dns.disablePrefetchFromHTTPS", false);
user_pref("network.predictor.enabled", true);
user_pref("network.http.speculative-parallel-limit", 6);

// ============================================================================
// END OF FILE
// ============================================================================
