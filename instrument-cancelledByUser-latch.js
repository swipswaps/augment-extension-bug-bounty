#!/usr/bin/env node

/**
 * WHAT: Instrument _cancelledByUser latch to capture stack traces when set
 * WHY: User identified _cancelledByUser as the root cause of empty <output> sections
 * HOW: Patch McpHost class prototype to intercept _cancelledByUser property assignments
 * 
 * ROOT CAUSE (from user analysis):
 * - _cancelledByUser is a one-way latch (never resets to false)
 * - When set to true, extension short-circuits and returns "Cancelled by user."
 * - Tool <output> is never surfaced, even though command succeeded
 * - Triggered by spurious cancel-tool-run message under terminal resource pressure
 * 
 * EVIDENCE:
 * - Line 235772: _cancelledByUser = !1 (initialization only)
 * - Line 235861: close(true) sets _cancelledByUser = true
 * - Line 235911: callTool() returns "Cancelled by user." when flag is true
 * - Line ~270918: cancel-tool-run message handler triggers close(true)
 * 
 * INSTRUMENTATION CAPTURES:
 * - Stack trace when _cancelledByUser set to true
 * - Stack trace when _cancelledByUser set to false (should only happen at init)
 * - Call site (function name, file, line, column)
 * - Process PID
 * - Terminal count (from lsof)
 * - File descriptor count (from lsof)
 * - Timestamp
 */

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const LOG_FILE = path.join(process.cwd(), 'augment-cancelledByUser-debug.log');

// WHAT: Get terminal count for correlation with latch trigger
// WHY: User's RULE 22 forensic finding shows terminal accumulation causes MCP instability
// HOW: Count VS Code terminal processes using lsof
function getTerminalCount() {
    try {
        const output = execSync('lsof -c code 2>/dev/null | grep -c "pts/" || echo 0', { encoding: 'utf8' });
        return parseInt(output.trim(), 10);
    } catch (err) {
        return -1;
    }
}

// WHAT: Get file descriptor count for correlation with latch trigger
// WHY: User's analysis shows FD leak (53,976 FDs) correlates with zygote runaway
// HOW: Count all FDs for VS Code processes using lsof
function getFdCount() {
    try {
        const output = execSync('lsof -c code 2>/dev/null | wc -l', { encoding: 'utf8' });
        return parseInt(output.trim(), 10);
    } catch (err) {
        return -1;
    }
}

// WHAT: Log _cancelledByUser mutation with full context
// WHY: User needs definitive proof for Augment team showing when/why latch triggers
// HOW: Capture stack trace, PID, terminal count, FD count, old/new values
function logMutation(oldValue, newValue, stack, className) {
    const timestamp = new Date().toISOString();
    const terminalCount = getTerminalCount();
    const fdCount = getFdCount();
    
    const logMessage = `
================================================================================
[_cancelledByUser LATCH MUTATION DETECTED] ${timestamp}
Class: ${className}
Process PID: ${process.pid}
Old value: ${oldValue}
New value: ${newValue}
Terminal count: ${terminalCount}
File descriptor count: ${fdCount}

CRITICAL ANALYSIS:
${newValue === true ? '🔴 LATCH SET TO TRUE - ALL FUTURE TOOL CALLS WILL FAIL' : '🟢 LATCH SET TO FALSE - NORMAL OPERATION'}
${terminalCount > 100 ? `⚠️  TERMINAL ACCUMULATION DETECTED (${terminalCount} terminals)` : ''}
${fdCount > 50000 ? `⚠️  FILE DESCRIPTOR LEAK DETECTED (${fdCount} FDs)` : ''}

STACK TRACE:
${stack}
================================================================================
`;
    
    fs.appendFileSync(LOG_FILE, logMessage, 'utf8');
    console.error(logMessage);
}

// WHAT: Patch class prototype to intercept _cancelledByUser property
// WHY: Need to capture stack trace at exact moment latch is set
// HOW: Use Object.defineProperty to create setter that logs before assignment
function patchClass(classConstructor, className) {
    const storageKey = `__cancelledByUser_${className}`;
    
    Object.defineProperty(classConstructor.prototype, '_cancelledByUser', {
        get: function() {
            return this[storageKey];
        },
        set: function(newValue) {
            const oldValue = this[storageKey];
            const stack = new Error().stack;
            
            // WHAT: Log mutation with full context
            // WHY: User needs to see when latch is set and never reset
            // HOW: Call logMutation with all diagnostic data
            logMutation(oldValue, newValue, stack, className);
            
            this[storageKey] = newValue;
        },
        configurable: true,
        enumerable: true
    });
}

// WHAT: Hook Module._load to patch classes before instantiation
// WHY: Must patch prototype before instances are created
// HOW: Intercept module loading, patch McpHost and related classes
const Module = require('module');
const originalLoad = Module._load;

let patchCount = 0;

Module._load = function(request, parent, isMain) {
    const exports = originalLoad.apply(this, arguments);
    
    // WHAT: Patch all classes that might have _cancelledByUser property
    // WHY: Extension.js is minified, class names may vary
    // HOW: Patch any class with prototype (defensive approach)
    if (exports && typeof exports === 'object') {
        Object.keys(exports).forEach(key => {
            const value = exports[key];
            if (typeof value === 'function' && value.prototype) {
                try {
                    patchClass(value, key);
                    patchCount++;
                } catch (err) {
                    // Ignore patching failures
                }
            }
        });
    }
    
    return exports;
};

// WHAT: Log instrumentation initialization
// WHY: User needs to verify instrumentation is active
// HOW: Write startup message to log file
const initMessage = `
================================================================================
[INSTRUMENTATION INITIALIZED] ${new Date().toISOString()}
Process PID: ${process.pid}
Log file: ${LOG_FILE}
Target property: _cancelledByUser
Strategy: Prototype patching via Module._load hook

WHAT THIS CAPTURES:
- Stack trace when _cancelledByUser set to true (latch engaged)
- Stack trace when _cancelledByUser set to false (latch reset - should never happen)
- Terminal count at mutation moment
- File descriptor count at mutation moment
- Process PID
- Timestamp

EXPECTED BEHAVIOR:
- Initialization: _cancelledByUser = false (once)
- Latch trigger: _cancelledByUser = true (under resource pressure)
- NEVER: _cancelledByUser = false (after initialization)

If you see _cancelledByUser set to true, that is the moment all tool calls start failing.
================================================================================
`;

fs.writeFileSync(LOG_FILE, initMessage, 'utf8');
console.error(initMessage);

console.error(`[INSTRUMENTATION] Patched ${patchCount} classes for _cancelledByUser monitoring`);

