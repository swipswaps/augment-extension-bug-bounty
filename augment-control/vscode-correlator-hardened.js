#!/usr/bin/env node
// Hardened VS Code Timeout Correlator - Production-grade monitoring
'use strict';

const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');
const readline = require('readline');

const LOG_ROOT = path.join(process.env.HOME, '.config', 'Code', 'logs');

// Strict regex patterns to avoid false positives
const STRICT_TIMEOUT_REGEX = /\bTool call was cancelled due to timeout\b/;
const STRICT_UNHANDLED_REGEX = /\b(unhandled rejection|uncaught exception)\b/i;
const EXTENSION_HOST_EVENT_REGEX = /extension host.*(restart|crash|terminated)/i;

let currentSessionDir = null;
let extensionHostPid = null;

// Use monotonic time for accurate correlation
function now() {
  return Number(process.hrtime.bigint() / 1000000n); // monotonic ms
}

function report(type, details) {
  const payload = {
    monotonicMs: now(),
    isoTime: new Date().toISOString(),
    type,
    details
  };
  process.stdout.write(JSON.stringify(payload, null, 2) + '\n');
}

function getLatestSessionDir() {
  if (!fs.existsSync(LOG_ROOT)) {
    return null;
  }
  
  const dirs = fs.readdirSync(LOG_ROOT)
    .map(d => path.join(LOG_ROOT, d))
    .filter(d => {
      try {
        return fs.statSync(d).isDirectory();
      } catch (e) {
        return false;
      }
    })
    .sort((a, b) => fs.statSync(b).mtimeMs - fs.statSync(a).mtimeMs);

  return dirs[0] || null;
}

// Watch log file with rotation detection
function watchLogFile(filePath, label) {
  let position = 0;

  function readNew() {
    fs.stat(filePath, (err, stats) => {
      if (err) return;

      // Detect log rotation
      if (stats.size < position) {
        report('LOG_ROTATED', { file: filePath });
        position = 0;
      }

      const stream = fs.createReadStream(filePath, {
        start: position,
        end: stats.size
      });

      const rl = readline.createInterface({
        input: stream,
        crlfDelay: Infinity
      });

      rl.on('line', line => {
        if (STRICT_TIMEOUT_REGEX.test(line)) {
          report('TIMEOUT_DETECTED', { source: label, line });
        }

        if (STRICT_UNHANDLED_REGEX.test(line)) {
          report('UNHANDLED_ERROR', { source: label, line });
        }

        if (EXTENSION_HOST_EVENT_REGEX.test(line)) {
          report('EXTENSION_HOST_EVENT', { source: label, line });
        }
      });

      rl.on('close', () => {
        position = stats.size;
      });
    });
  }

  // Watch for file changes
  const watcher = fs.watch(filePath, { persistent: true }, (eventType) => {
    if (eventType === 'change') {
      readNew();
    }
  });

  // Initial read
  readNew();

  return watcher;
}

// Monitor for session changes
function monitorSessionChanges() {
  setInterval(() => {
    const latest = getLatestSessionDir();
    if (!latest) return;

    if (latest !== currentSessionDir) {
      currentSessionDir = latest;
      report('NEW_SESSION_DETECTED', { session: latest });

      // Watch exthost.log
      const exthost = path.join(latest, 'exthost.log');
      if (fs.existsSync(exthost)) {
        watchLogFile(exthost, 'exthost');
      }

      // Watch main.log
      const main = path.join(latest, 'main.log');
      if (fs.existsSync(main)) {
        watchLogFile(main, 'main');
      }
    }
  }, 2000);
}

// Monitor extension host PID
function monitorExtensionHost() {
  setInterval(() => {
    const ps = spawn('pgrep', ['-f', 'extensionHost']);

    let output = '';

    ps.stdout.on('data', d => output += d);

    ps.on('close', () => {
      const pids = output.trim().split('\n').filter(Boolean);

      if (pids.length === 0) {
        if (extensionHostPid !== null) {
          report('EXTENSION_HOST_NOT_RUNNING', {});
          extensionHostPid = null;
        }
        return;
      }

      if (!extensionHostPid) {
        extensionHostPid = pids[0];
        report('EXTENSION_HOST_STARTED', { pid: extensionHostPid });
        return;
      }

      if (pids[0] !== extensionHostPid) {
        report('EXTENSION_HOST_RESTARTED', {
          oldPid: extensionHostPid,
          newPid: pids[0]
        });
        extensionHostPid = pids[0];
      }
    });

  }, 2000);
}

function main() {
  if (!fs.existsSync(LOG_ROOT)) {
    console.error('[ERROR] VS Code log directory not found at:', LOG_ROOT);
    process.exit(1);
  }

  report('MONITOR_STARTED', { logRoot: LOG_ROOT });

  monitorSessionChanges();
  monitorExtensionHost();

  // Keep process alive
  process.on('SIGINT', () => {
    report('MONITOR_STOPPED', {});
    process.exit(0);
  });
}

main();

