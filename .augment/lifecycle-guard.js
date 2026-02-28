#!/usr/bin/env node
/**
 * LIFECYCLE GUARD MODULE — PERMANENT FIX FOR EXTENSION FAILURES
 * 
 * PURPOSE:
 *   Fix three interacting failure systems:
 *   1. _closingPromise one-way latch (Line 603)
 *   2. Async stream cleanup leak (Line 306)
 *   3. Webview re-initialization race
 * 
 * DESIGN:
 *   - Idempotent close() with automatic latch reset
 *   - Deterministic async generator cleanup
 *   - Webview singleton guard
 *   - Retry backoff ceiling
 *   - Full instrumentation
 */

const fs = require('fs');
const path = require('path');

// Logging configuration
const LOG_FILE = path.join(__dirname, '../.notes/lifecycle-guard.log');

function log(message) {
  const timestamp = new Date().toISOString();
  const pid = process.pid;
  const stack = new Error().stack.split('\n')[2]?.trim() || 'unknown';
  const entry = `[${timestamp}] [PID:${pid}] ${message} | ${stack}\n`;
  
  fs.appendFileSync(LOG_FILE, entry);
  console.error(entry.trim());
}

/**
 * PHASE 1: SAFE CLOSABLE PATTERN
 * 
 * Fixes the _closingPromise one-way latch by:
 *   - Making close() idempotent
 *   - Resetting latch in finally block
 *   - Preventing re-entry during shutdown
 */
class SafeClosable {
  constructor() {
    this._closingPromise = null;
    this._closed = false;
    this._closing = false;
    
    log('SafeClosable: initialized');
  }

  async close(force = false) {
    log(`SafeClosable.close: called with force=${force}, closed=${this._closed}, closing=${this._closing}`);
    
    // Already closed - idempotent
    if (this._closed) {
      log('SafeClosable.close: already closed, returning');
      return;
    }

    // Already closing - return existing promise
    if (this._closingPromise) {
      log('SafeClosable.close: already closing, returning existing promise');
      return this._closingPromise;
    }

    // Mark as closing
    this._closing = true;
    log('SafeClosable.close: starting shutdown');

    // Create closing promise with guaranteed cleanup
    this._closingPromise = (async () => {
      try {
        await this._performShutdown(force);
        this._closed = true;
        log('SafeClosable.close: shutdown complete, marked as closed');
      } catch (error) {
        log(`SafeClosable.close: shutdown error: ${error.message}`);
        throw error;
      } finally {
        // CRITICAL: Reset latch to allow re-initialization
        this._closing = false;
        this._closingPromise = null;
        log('SafeClosable.close: latch reset complete');
      }
    })();

    return this._closingPromise;
  }

  async _performShutdown(force) {
    log('SafeClosable._performShutdown: executing shutdown logic');
    // Override in subclass
  }

  isClosing() {
    return this._closing;
  }

  isClosed() {
    return this._closed;
  }
}

/**
 * PHASE 2: ASYNC GENERATOR CLEANUP WRAPPER
 * 
 * Fixes FD leak by ensuring streams are disposed in finally block
 */
async function* safeAsyncGenerator(streamFactory) {
  const stream = await streamFactory();
  log('safeAsyncGenerator: stream created');
  
  try {
    for await (const chunk of stream) {
      yield chunk;
    }
    log('safeAsyncGenerator: stream completed normally');
  } catch (error) {
    log(`safeAsyncGenerator: stream error: ${error.message}`);
    throw error;
  } finally {
    log('safeAsyncGenerator: cleaning up stream');
    
    // Try all cleanup methods
    if (stream && typeof stream.return === 'function') {
      try {
        await stream.return();
        log('safeAsyncGenerator: stream.return() called');
      } catch (e) {
        log(`safeAsyncGenerator: stream.return() failed: ${e.message}`);
      }
    }
    
    if (stream && typeof stream.destroy === 'function') {
      try {
        stream.destroy();
        log('safeAsyncGenerator: stream.destroy() called');
      } catch (e) {
        log(`safeAsyncGenerator: stream.destroy() failed: ${e.message}`);
      }
    }
    
    if (stream && stream.body && typeof stream.body.cancel === 'function') {
      try {
        await stream.body.cancel();
        log('safeAsyncGenerator: stream.body.cancel() called');
      } catch (e) {
        log(`safeAsyncGenerator: stream.body.cancel() failed: ${e.message}`);
      }
    }
    
    log('safeAsyncGenerator: cleanup complete');
  }
}

/**
 * PHASE 3: RETRY WITH BACKOFF CEILING
 * 
 * Prevents infinite retry loops
 */
async function retryWithBackoff(fn, maxRetries = 5, name = 'operation') {
  let attempt = 0;
  
  while (attempt < maxRetries) {
    try {
      log(`retryWithBackoff: ${name} attempt ${attempt + 1}/${maxRetries}`);
      return await fn();
    } catch (err) {
      attempt++;
      
      if (attempt >= maxRetries) {
        log(`retryWithBackoff: ${name} failed after ${maxRetries} attempts: ${err.message}`);
        throw err;
      }

      const delay = Math.min(1000 * Math.pow(2, attempt), 30000);
      log(`retryWithBackoff: ${name} failed, retrying in ${delay}ms`);
      await new Promise(r => setTimeout(r, delay));
    }
  }
}

/**
 * PHASE 4: WEBVIEW SINGLETON GUARD
 * 
 * Prevents webview recreation race
 */
class WebviewGuard {
  constructor() {
    this._webview = null;
    this._creating = false;
    log('WebviewGuard: initialized');
  }

  async createWebview(factory) {
    // Already exists
    if (this._webview) {
      log('WebviewGuard: webview already exists, returning existing');
      return this._webview;
    }

    // Already creating
    if (this._creating) {
      log('WebviewGuard: webview creation in progress, waiting');
      while (this._creating) {
        await new Promise(r => setTimeout(r, 100));
      }
      return this._webview;
    }

    this._creating = true;
    log('WebviewGuard: creating new webview');

    try {
      this._webview = await factory();
      
      // Register disposal handler
      if (this._webview && this._webview.onDidDispose) {
        this._webview.onDidDispose(() => {
          log('WebviewGuard: webview disposed');
          this._webview = null;
        });
      }
      
      log('WebviewGuard: webview created successfully');
      return this._webview;
    } finally {
      this._creating = false;
    }
  }
}

module.exports = {
  SafeClosable,
  safeAsyncGenerator,
  retryWithBackoff,
  WebviewGuard,
  log
};

