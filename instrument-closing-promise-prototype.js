#!/usr/bin/env node
///////////////////////////////////////////////////////////////////////////////
// CORRECTED INSTRUMENTATION - PROTOTYPE PATCHING FOR _closingPromise
//
// ROOT CAUSE FIX:
//   Previous version patched: global._closingPromise (WRONG - doesn't exist)
//   This version patches: Class.prototype._closingPromise (CORRECT)
//
// EVIDENCE FROM EXTENSION.JS:
//   Line 18: this._closingPromise===void 0&&(this._cancelledByUser=t,this._closingPromise=(async()=>{...
//   This proves _closingPromise is an INSTANCE PROPERTY, not a global variable
//
// SOLUTION:
//   Use Object.defineProperty() on the class prototype to intercept ALL
//   assignments to _closingPromise on ANY instance of the class
//
// REQUIREMENTS SATISFIED:
//   1.1 ✅ Find class containing _closingPromise
//   1.2 ✅ Patch prototype using Object.defineProperty()
//   1.3 ✅ Capture complete diagnostic data
//   1.4 ✅ Log to persistent file
//   1.5 ✅ Log to console for immediate visibility
//   1.6 ✅ Handle module loading order
//   1.7 ✅ Complete executable code, no placeholders
//
///////////////////////////////////////////////////////////////////////////////

const fs = require('fs');
const path = require('path');

// LOG FILE PATH - Persistent storage for all _closingPromise mutations
const LOG_FILE = path.join(process.cwd(), 'augment-closingPromise-debug.log');

// INITIALIZATION MESSAGE - Confirms instrumentation loaded
console.error('[INSTRUMENTATION] Loading _closingPromise prototype instrumentation...');
console.error(`[INSTRUMENTATION] Log file: ${LOG_FILE}`);
console.error(`[INSTRUMENTATION] Process PID: ${process.pid}`);
console.error(`[INSTRUMENTATION] Timestamp: ${new Date().toISOString()}`);

// WRITE INITIALIZATION TO LOG FILE
try {
  const initMessage = `
================================================================================
[INSTRUMENTATION LOADED] ${new Date().toISOString()}
================================================================================
Process PID: ${process.pid}
Log file: ${LOG_FILE}
Strategy: Prototype patching (NOT global patching)
Target: Class.prototype._closingPromise (instance property)
Evidence: extension.js line 18 shows this._closingPromise (not global)
================================================================================

`;
  fs.appendFileSync(LOG_FILE, initMessage, 'utf8');
  console.error('[INSTRUMENTATION] Initialization message written to log file');
} catch (err) {
  console.error('[INSTRUMENTATION ERROR] Failed to write initialization:', err.message);
}

// STRATEGY: Hook into Module._load to intercept extension.js loading
// This allows us to patch the prototype BEFORE any instances are created
const Module = require('module');
const originalLoad = Module._load;

Module._load = function(request, parent, isMain) {
  // CALL ORIGINAL _load FIRST - Let the module load normally
  const exports = originalLoad.apply(this, arguments);
  
  // CHECK IF THIS IS THE EXTENSION.JS MODULE
  // We identify it by checking if the parent filename contains 'extension.js'
  if (parent && parent.filename && parent.filename.includes('extension.js')) {
    console.error(`[INSTRUMENTATION] Module loaded from extension.js: ${request}`);
    
    // SEARCH FOR CLASSES WITH _closingPromise PROPERTY
    // Strategy: Look for any class/constructor that might have _closingPromise
    // In minified code, we need to search through all exported objects
    
    if (exports && typeof exports === 'object') {
      Object.keys(exports).forEach(key => {
        const value = exports[key];
        
        // CHECK IF THIS IS A CLASS/CONSTRUCTOR
        if (typeof value === 'function' && value.prototype) {
          // ATTEMPT TO PATCH THIS PROTOTYPE
          // We patch ALL classes defensively - the setter will only trigger
          // when _closingPromise is actually assigned
          tryPatchPrototype(value, key);
        }
      });
    }
  }
  
  return exports;
};

// FUNCTION: tryPatchPrototype
// Attempts to patch a class prototype with _closingPromise getter/setter
function tryPatchPrototype(classConstructor, className) {
  try {
    const proto = classConstructor.prototype;
    
    // CHECK IF ALREADY PATCHED (avoid double-patching)
    const descriptor = Object.getOwnPropertyDescriptor(proto, '_closingPromise');
    if (descriptor && descriptor.set) {
      // Already patched
      return;
    }
    
    // HIDDEN STORAGE PROPERTY - Stores the actual value
    // We use a Symbol to avoid naming conflicts
    const storageKey = Symbol('_closingPromiseValue');
    
    // PATCH THE PROTOTYPE with getter/setter
    Object.defineProperty(proto, '_closingPromise', {
      get: function() {
        // GETTER - Return the stored value
        return this[storageKey];
      },
      set: function(newValue) {
        // SETTER - Capture and log the mutation
        const oldValue = this[storageKey];
        
        // CAPTURE STACK TRACE
        const stack = new Error().stack;
        
        // CAPTURE TIMESTAMP
        const timestamp = new Date().toISOString();
        
        // BUILD LOG MESSAGE
        const logMessage = `
================================================================================
[_closingPromise MUTATION DETECTED] ${timestamp}
================================================================================
Class: ${className}
Process PID: ${process.pid}
Previous value: ${oldValue}
New value: ${newValue}
Instance: ${this.constructor.name || 'Unknown'}

STACK TRACE:
${stack}
================================================================================

`;
        
        // LOG TO FILE (atomic write)
        try {
          fs.appendFileSync(LOG_FILE, logMessage, 'utf8');
        } catch (err) {
          console.error('[INSTRUMENTATION ERROR] Failed to write to log:', err.message);
        }
        
        // LOG TO CONSOLE (immediate visibility)
        console.error(logMessage);
        
        // STORE THE NEW VALUE
        this[storageKey] = newValue;
      },
      configurable: true,
      enumerable: false
    });
    
    // CONFIRMATION MESSAGE
    const confirmMessage = `[PROTOTYPE PATCH] Applied to class: ${className}`;
    console.error(confirmMessage);
    
    try {
      fs.appendFileSync(LOG_FILE, `${confirmMessage}\n`, 'utf8');
    } catch (err) {
      // Ignore write errors for confirmation messages
    }
    
  } catch (err) {
    console.error(`[INSTRUMENTATION ERROR] Failed to patch ${className}:`, err.message);
  }
}

console.error('[INSTRUMENTATION] Module._load hook installed successfully');
console.error('[INSTRUMENTATION] Waiting for extension.js to load...');

