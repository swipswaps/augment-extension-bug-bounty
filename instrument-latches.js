#!/usr/bin/env node
/**
 * AUGMENT EXTENSION LATCH INSTRUMENTATION
 * 
 * VERSION: 1.0.0
 * CREATED: 2026-02-21T21:30:00Z
 * 
 * PURPOSE:
 *   Instrument BOTH latch variables (_closingPromise and _cancelledByUser)
 *   to capture full step-by-step stack traces at the EXACT MOMENT either latch flips.
 * 
 * WHY STACK TRACES DISAPPEAR WITHOUT THIS:
 *   - Cancellation is implemented as silent state mutation (this._cancelledByUser = true)
 *   - No Error object is thrown, so no automatic stack trace is generated
 *   - The early return prevents downstream logging or diagnostic output
 *   - JavaScript discards call stacks once functions return
 *   - Without explicit capture at assignment time, the call chain is lost forever
 * 
 * WHY SETTER CAPTURE IS REQUIRED:
 *   - Object.defineProperty() intercepts ALL assignments to the property
 *   - new Error().stack captures the call chain at the exact moment of assignment
 *   - This happens BEFORE the runtime unwinds and discards the stack
 *   - The setter preserves original semantics while adding instrumentation
 * 
 * WHY CANCELLATION PATH IS SILENT OTHERWISE:
 *   - Extension treats cancellation as "normal control flow" not exceptional condition
 *   - No exception is thrown (no throw new Error())
 *   - No stack trace is printed (no console.error())
 *   - No debug log is triggered (no logger.debug())
 *   - It simply returns a string: "Cancelled by user."
 *   - This design flaw makes debugging impossible without instrumentation
 * 
 * COMPLIANCE:
 *   RULE 0  - Emission gate: All requirements satisfied before emission
 *   RULE 2  - No partial compliance: Both latches instrumented, not just one
 *   RULE 6  - Known working Node patterns: Object.defineProperty() is standard
 *   RULE 11 - No placeholders: All values are real, no TODOs or fake data
 *   RULE 18 - Rollback present: See launch-instrumented-extension.sh
 *   RULE 22 - Terminal hygiene: No terminal spawning in this file
 * 
 * ENVIRONMENT:
 *   - Node.js 18+
 *   - VS Code extension host context
 *   - Augment extension v0.754.3+
 */

const fs = require('fs');
const path = require('path');

// WHAT: Log file for latch mutation events
// WHY: Persistent storage for forensic analysis
// HOW: Append-only file in current working directory
const LOG_FILE = path.join(process.cwd(), 'augment-latch-debug.log');

/**
 * WHAT: Log latch mutation with full context
 * WHY: User needs definitive proof showing when/why latch triggers
 * HOW: Capture stack trace, PID, timestamp, old/new values
 * 
 * @param {string} latchName - Name of the latch property (_closingPromise or _cancelledByUser)
 * @param {*} oldValue - Previous value before assignment
 * @param {*} newValue - New value being assigned
 * @param {string} stack - Stack trace from new Error().stack
 */
function logLatchMutation(latchName, oldValue, newValue, stack) {
    const timestamp = new Date().toISOString();
    const pid = process.pid;
    
    // WHAT: Format log message with deterministic structure
    // WHY: Stable, repeatable output for parsing and analysis
    // HOW: Fixed format with labeled fields
    const logMessage = `
================================================================================
[LATCH DETECTED]
Latch: ${latchName}
Timestamp: ${timestamp}
PID: ${pid}
Previous: ${oldValue}
New: ${newValue}

CRITICAL ANALYSIS:
${latchName === '_cancelledByUser' && newValue === true ? '🔴 _cancelledByUser SET TO TRUE - ALL FUTURE TOOL CALLS WILL FAIL' : ''}
${latchName === '_cancelledByUser' && newValue === false ? '🟢 _cancelledByUser SET TO FALSE - NORMAL OPERATION' : ''}
${latchName === '_closingPromise' && newValue !== undefined ? '🔴 _closingPromise SET - MCP CLIENT CLOSING' : ''}

STACK TRACE:
${stack}
================================================================================
`;
    
    // WHAT: Write to log file (persistent storage)
    // WHY: Forensic analysis requires persistent logs
    // HOW: Append to file, create if doesn't exist
    fs.appendFileSync(LOG_FILE, logMessage, 'utf8');
    
    // WHAT: Print to console immediately
    // WHY: Real-time visibility during debugging
    // HOW: console.error() writes to stderr (visible in extension host output)
    console.error(logMessage);
}

/**
 * WHAT: Instrument a latch property with setter interception
 * WHY: Need to capture stack trace at exact moment latch is set
 * HOW: Use Object.defineProperty to create getter/setter that logs before assignment
 * 
 * @param {Object} target - Object to instrument (e.g., McpHost instance)
 * @param {string} propertyName - Name of property to instrument
 * @param {string} storageKey - Internal storage key for actual value
 */
function instrumentLatch(target, propertyName, storageKey) {
    // WHAT: Define property with custom getter/setter
    // WHY: Intercept ALL assignments to capture stack traces
    // HOW: Object.defineProperty() replaces property with accessor
    Object.defineProperty(target, propertyName, {
        get: function() {
            // WHAT: Return stored value
            // WHY: Preserve original getter semantics
            // HOW: Read from internal storage key
            return this[storageKey];
        },
        set: function(newValue) {
            // WHAT: Capture stack trace BEFORE assignment
            // WHY: Call stack will be discarded after function returns
            // HOW: new Error().stack captures current call chain
            const oldValue = this[storageKey];
            const stack = new Error().stack;
            
            // WHAT: Log mutation with full context
            // WHY: User needs to see when latch is set and never reset
            // HOW: Call logLatchMutation with all diagnostic data
            logLatchMutation(propertyName, oldValue, newValue, stack);
            
            // WHAT: Store new value
            // WHY: Preserve original setter semantics
            // HOW: Write to internal storage key
            this[storageKey] = newValue;
        },
        configurable: true,
        enumerable: true
    });
}

// WHAT: Initialize instrumentation log file
// WHY: User needs to verify instrumentation is active
// HOW: Write startup message with timestamp and configuration
const initMessage = `
================================================================================
[INSTRUMENTATION INITIALIZED]
Timestamp: ${new Date().toISOString()}
PID: ${process.pid}
Log file: ${LOG_FILE}
Target properties: _closingPromise, _cancelledByUser

WHAT THIS CAPTURES:
- Stack trace when _closingPromise is set (MCP client closing)
- Stack trace when _cancelledByUser set to true (latch engaged)
- Stack trace when _cancelledByUser set to false (latch reset - should only happen at init)
- Process PID and timestamp for each mutation

EXPECTED BEHAVIOR:
- Initialization: _cancelledByUser = false (once)
- Latch trigger: _cancelledByUser = true (under resource pressure)
- NEVER: _cancelledByUser = false (after initialization)

If you see _cancelledByUser set to true, that is the moment all tool calls start failing.
The stack trace will show the exact function that triggered the latch.
================================================================================
`;

fs.writeFileSync(LOG_FILE, initMessage, 'utf8');
console.error(initMessage);

// WHAT: Export instrumentation function for use by extension
// WHY: Extension must call this to activate instrumentation
// HOW: Export function that instruments target object
module.exports = { instrumentLatch, LOG_FILE };

