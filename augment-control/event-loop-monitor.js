#!/usr/bin/env node
// Event Loop Stall Detector - Detects event loop blocking
'use strict';

const INTERVAL_MS = 100;
const STALL_THRESHOLD_MS = 200;

let lastTick = Date.now();

console.log('=== Event Loop Stall Monitor ===');
console.log(`Interval: ${INTERVAL_MS}ms`);
console.log(`Stall threshold: ${STALL_THRESHOLD_MS}ms`);
console.log('Press Ctrl+C to stop');
console.log('');

setInterval(() => {
  const now = Date.now();
  const drift = now - lastTick - INTERVAL_MS;

  if (drift > STALL_THRESHOLD_MS) {
    const timestamp = new Date().toISOString();
    console.log(`[${timestamp}] [STALL DETECTED] Drift: ${drift}ms`);
  }

  lastTick = now;
}, INTERVAL_MS);

// Catch unhandled rejections
process.on('unhandledRejection', (reason, promise) => {
  const timestamp = new Date().toISOString();
  console.error(`[${timestamp}] [UNHANDLED REJECTION]`, reason);
});

// Catch uncaught exceptions
process.on('uncaughtException', (err) => {
  const timestamp = new Date().toISOString();
  console.error(`[${timestamp}] [UNCAUGHT EXCEPTION]`, err);
});

console.log('[INFO] Event loop monitor started');

