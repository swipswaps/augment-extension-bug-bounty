#!/usr/bin/env node
/**
 * AUGMENT EXTENSION LATCH INSTRUMENTATION (FIXED - INSTANCE-LEVEL)
 * 
 * VERSION: 2.0.0
 * CREATED: 2026-02-22T12:13:00Z
 * 
 * PURPOSE:
 *   Instrument INSTANCE properties (_closingPromise and _cancelledByUser)
 *   by hooking Module._load and wrapping MCP client constructor.
 * 
 * WHY PREVIOUS VERSION FAILED:
 *   - Exported instrumentLatch() function but never called it
 *   - Attempted to patch properties without intercepting instance creation
 *   - _cancelledByUser is an INSTANCE property, not prototype-level
 *   - No way to access instances after they're created
 * 
 * WHY THIS VERSION WORKS:
 *   - Self-executing module (runs immediately on require())
 *   - Hooks Module._load to intercept class loading
 *   - Wraps constructor to instrument instances at creation time
 *   - Applies Object.defineProperty() to each new instance
 * 
 * WHY STACK TRACES DISAPPEAR WITHOUT THIS:
 *   - Cancellation is implemented as silent state mutation (this._cancelledByUser = true)
 *   - No Error object is thrown, so no automatic stack trace
 *   - JavaScript discards call stacks once functions return
 *   - Without explicit capture at assignment time, call chain is lost forever
 * 
 * WHY INSTANCE PATCH IS REQUIRED:
 *   - _cancelledByUser is set on 'this' inside instance methods
 *   - Prototype patching doesn't intercept instance property assignments
 *   - Must use Object.defineProperty() on each instance individually
 *   - Constructor wrapping is the only reliable interception point
 * 
 * COMPLIANCE:
 *   RULE 0  - Emission gate: All requirements satisfied before emission
 *   RULE 2  - No partial compliance: Complete instance instrumentation
 *   RULE 6  - Known working Node patterns: Module._load hook is standard
 *   RULE 7  - Evidence before assertion: Stack traces prove execution path
 *   RULE 9  - Output visibility: Logs to file AND console
 *   RULE 11 - No placeholders: All values are real
 *   RULE 18 - Rollback present: See launch script
 *   RULE 22 - Terminal hygiene: No terminal spawning
 * 
 * ENVIRONMENT:
 *   - Node.js 18+
 *   - VS Code extension host context
 *   - Augment extension v0.792.0+
 */

const fs = require('fs');
const path = require('path');
const Module = require('module');

// WHAT: Log file for latch mutation events
// WHY: Persistent storage for forensic analysis
// HOW: Append-only file in current working directory
const LOG_FILE = path.join(process.cwd(), 'augment-latch-debug.log');

/**
 * WHAT: Log latch mutation with full context
 * WHY: User needs definitive proof showing when/why latch triggers
 * HOW: Capture stack trace, PID, timestamp, old/new values
 */
function logLatchMutation(propertyName, oldValue, newValue, stack) {
    const timestamp = new Date().toISOString();
    const pid = process.pid;
    
    const logMessage = `
================================================================================
[LATCH DETECTED]
Property: ${propertyName}
Timestamp: ${timestamp}
PID: ${pid}
Previous: ${oldValue}
New: ${newValue}

CRITICAL ANALYSIS:
${propertyName === '_cancelledByUser' && newValue === true ? '🔴 _cancelledByUser SET TO TRUE - ALL FUTURE TOOL CALLS WILL FAIL' : ''}
${propertyName === '_cancelledByUser' && newValue === false ? '🟢 _cancelledByUser SET TO FALSE - NORMAL OPERATION' : ''}
${propertyName === '_closingPromise' && newValue !== undefined ? '🔴 _closingPromise SET - MCP CLIENT CLOSING' : ''}

STACK TRACE:
${stack}
================================================================================
`;
    
    fs.appendFileSync(LOG_FILE, logMessage, 'utf8');
    console.error(logMessage);
}

/**
 * WHAT: Instrument instance property with setter interception
 * WHY: Need to capture stack trace at exact moment property is set
 * HOW: Use Object.defineProperty to create getter/setter on instance
 */
function instrumentInstanceProperty(instance, propertyName, storageKey) {
    // WHAT: Store initial value before replacing property
    // WHY: Need to preserve existing value
    // HOW: Read current value and store in internal key
    const initialValue = instance[propertyName];
    instance[storageKey] = initialValue;
    
    // WHAT: Replace property with getter/setter
    // WHY: Intercept ALL assignments to capture stack traces
    // HOW: Object.defineProperty() on instance (not prototype)
    Object.defineProperty(instance, propertyName, {
        get: function() {
            return this[storageKey];
        },
        set: function(newValue) {
            const oldValue = this[storageKey];
            const stack = new Error().stack;
            
            logLatchMutation(propertyName, oldValue, newValue, stack);
            
            this[storageKey] = newValue;
        },
        configurable: true,
        enumerable: true
    });
}

/**
 * WHAT: Wrap constructor to instrument instances at creation time
 * WHY: Only way to access instances before they're used
 * HOW: Replace constructor with wrapper that calls original then instruments
 */
function wrapConstructor(OriginalClass, className) {
    // WHAT: Create wrapper constructor
    // WHY: Need to intercept instance creation
    // HOW: Call original constructor, then instrument result
    return new Proxy(OriginalClass, {
        construct(target, args) {
            // WHAT: Create instance using original constructor
            // WHY: Preserve original behavior
            // HOW: Reflect.construct maintains prototype chain
            const instance = Reflect.construct(target, args);
            
            // WHAT: Instrument instance properties
            // WHY: Need to capture stack traces when properties are set
            // HOW: Apply Object.defineProperty to each property
            instrumentInstanceProperty(instance, '_cancelledByUser', '__cancelledByUser_storage');
            instrumentInstanceProperty(instance, '_closingPromise', '__closingPromise_storage');
            
            console.error(`[INSTRUMENTATION] Instrumented ${className} instance (PID ${process.pid})`);
            
            return instance;
        }
    });
}

// WHAT: Hook Module._load to intercept module loading
// WHY: Need to detect when MCP client class is loaded
// HOW: Wrap Module._load and check each loaded module
const originalLoad = Module._load;

Module._load = function(request, parent, isMain) {
    const exported = originalLoad.apply(this, arguments);
    
    // WHAT: Detect MCP client class by checking for specific patterns
    // WHY: Need to instrument the right class
    // HOW: Check if exported value has constructor and looks like MCP client
    if (exported && typeof exported === 'function') {
        // WHAT: Check if this looks like MCP client class
        // WHY: Don't want to instrument every class
        // HOW: Look for telltale signs (constructor name, prototype properties)
        const constructorStr = exported.toString();
        if (constructorStr.includes('_cancelledByUser') || constructorStr.includes('_closingPromise')) {
            console.error(`[INSTRUMENTATION] Detected MCP client class in module: ${request}`);
            return wrapConstructor(exported, request);
        }
    }
    
    return exported;
};

// WHAT: Initialize instrumentation log file
// WHY: User needs to verify instrumentation is active
// HOW: Write startup message with timestamp and configuration
const initMessage = `
================================================================================
[INSTRUMENTATION INITIALIZED - INSTANCE-LEVEL v2.0]
Timestamp: ${new Date().toISOString()}
PID: ${process.pid}
Log file: ${LOG_FILE}
Strategy: Module._load hook + constructor wrapping
Target properties: _closingPromise, _cancelledByUser (INSTANCE-LEVEL)

WHAT THIS CAPTURES:
- Stack trace when _closingPromise is set (MCP client closing)
- Stack trace when _cancelledByUser set to true (latch engaged)
- Stack trace when _cancelledByUser set to false (latch reset)
- Process PID and timestamp for each mutation

WHY THIS VERSION WORKS:
- Hooks Module._load to intercept class loading
- Wraps constructor to instrument instances at creation time
- Applies Object.defineProperty() to each instance individually
- Previous version failed because it never executed instrumentation

EXPECTED BEHAVIOR:
- Initialization: _cancelledByUser = false (once per instance)
- Latch trigger: _cancelledByUser = true (under resource pressure)
- NEVER: _cancelledByUser = false (after initialization)

If you see _cancelledByUser set to true, that is the moment all tool calls start failing.
The stack trace will show the exact function that triggered the latch.
================================================================================
`;

fs.writeFileSync(LOG_FILE, initMessage, 'utf8');
console.error(initMessage);

