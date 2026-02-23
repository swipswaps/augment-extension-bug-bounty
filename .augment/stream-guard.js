#!/usr/bin/env node
/**
 * STREAM GUARD - Runtime Stream Disposal Wrapper
 * 
 * PURPOSE:
 *   Ensure async iterators are properly disposed on abort/error
 * 
 * ROOT CAUSE:
 *   getRemoteAgentOverviewsStream() missing cleanup in async generator
 *   Line 64:59334 - AbortError every ~60s without stream disposal
 * 
 * USAGE:
 *   const { wrapAsyncIterator } = require('./.augment/stream-guard.js');
 *   
 *   async function* myStream() {
 *     const wrapped = wrapAsyncIterator(originalStream);
 *     try {
 *       for await (const chunk of wrapped) {
 *         yield chunk;
 *       }
 *     } finally {
 *       await wrapped.return();
 *     }
 *   }
 */

const fs = require("fs");
const path = require("path");

const LOGFILE = path.join(process.cwd(), ".notes", "stream-guard.log");

function log(msg) {
  const timestamp = new Date().toISOString();
  const line = `[${timestamp}] ${msg}\n`;
  try {
    fs.appendFileSync(LOGFILE, line);
  } catch {}
}

/**
 * Wrap an async iterator to ensure proper cleanup
 * 
 * @param {AsyncIterable} iterable - The async iterable to wrap
 * @param {Object} options - Options
 * @param {AbortSignal} options.signal - Optional abort signal
 * @param {Function} options.onAbort - Optional abort handler
 * @returns {AsyncIterator} Wrapped iterator with guaranteed cleanup
 */
function wrapAsyncIterator(iterable, options = {}) {
  const { signal, onAbort } = options;
  
  if (!iterable || typeof iterable[Symbol.asyncIterator] !== 'function') {
    throw new Error('wrapAsyncIterator: argument must be an async iterable');
  }
  
  const iterator = iterable[Symbol.asyncIterator]();
  let cleaned = false;
  let aborted = false;
  
  // Handle abort signal
  if (signal) {
    signal.addEventListener('abort', () => {
      log('STREAM_GUARD: Abort signal received');
      aborted = true;
      if (onAbort) {
        try {
          onAbort();
        } catch (err) {
          log(`STREAM_GUARD: onAbort error: ${err.message}`);
        }
      }
    });
  }
  
  async function cleanup() {
    if (cleaned) {
      log('STREAM_GUARD: Already cleaned');
      return;
    }
    
    cleaned = true;
    log('STREAM_GUARD: Starting cleanup');
    
    // Try iterator.return() first (proper async iterator protocol)
    if (iterator.return && typeof iterator.return === 'function') {
      try {
        log('STREAM_GUARD: Calling iterator.return()');
        await iterator.return();
        log('STREAM_GUARD: iterator.return() succeeded');
      } catch (err) {
        log(`STREAM_GUARD: iterator.return() error: ${err.message}`);
      }
    }
    
    // Try destroy() if available (Node.js streams)
    if (iterator.destroy && typeof iterator.destroy === 'function') {
      try {
        log('STREAM_GUARD: Calling iterator.destroy()');
        iterator.destroy();
        log('STREAM_GUARD: iterator.destroy() succeeded');
      } catch (err) {
        log(`STREAM_GUARD: iterator.destroy() error: ${err.message}`);
      }
    }
    
    // Try body.cancel() if available (fetch Response.body)
    if (iterable.body && typeof iterable.body.cancel === 'function') {
      try {
        log('STREAM_GUARD: Calling body.cancel()');
        await iterable.body.cancel();
        log('STREAM_GUARD: body.cancel() succeeded');
      } catch (err) {
        log(`STREAM_GUARD: body.cancel() error: ${err.message}`);
      }
    }
    
    log('STREAM_GUARD: Cleanup complete');
  }
  
  return {
    async next() {
      if (aborted) {
        log('STREAM_GUARD: next() called after abort - returning done');
        await cleanup();
        return { done: true, value: undefined };
      }
      
      try {
        const result = await iterator.next();
        if (result.done) {
          log('STREAM_GUARD: Iterator completed normally');
          await cleanup();
        }
        return result;
      } catch (err) {
        log(`STREAM_GUARD: next() error: ${err.message}`);
        await cleanup();
        throw err;
      }
    },
    
    async return(value) {
      log('STREAM_GUARD: return() called explicitly');
      await cleanup();
      return { done: true, value };
    },
    
    async throw(err) {
      log(`STREAM_GUARD: throw() called with: ${err.message}`);
      await cleanup();
      if (iterator.throw && typeof iterator.throw === 'function') {
        return iterator.throw(err);
      }
      throw err;
    },
    
    [Symbol.asyncIterator]() {
      return this;
    }
  };
}

/**
 * Create a safe async generator wrapper
 * 
 * @param {AsyncGeneratorFunction} generatorFn - The async generator function
 * @param {Object} options - Options
 * @returns {AsyncGeneratorFunction} Wrapped generator with automatic cleanup
 */
function safeAsyncGenerator(generatorFn, options = {}) {
  return async function* (...args) {
    const generator = generatorFn(...args);
    const wrapped = wrapAsyncIterator(generator, options);
    
    try {
      for await (const value of wrapped) {
        yield value;
      }
    } finally {
      await wrapped.return();
    }
  };
}

module.exports = {
  wrapAsyncIterator,
  safeAsyncGenerator
};

log('STREAM_GUARD module loaded');

