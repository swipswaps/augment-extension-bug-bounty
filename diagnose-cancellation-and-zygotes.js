#!/usr/bin/env node

// WHAT: Diagnose and fix "Cancelled by user" errors and runaway zygote processes
// WHY: User complaint: "augment is UNUSABLE" - all tool calls return "Cancelled by user"
//      AND: Runaway zygote popups every 30 seconds (PID 2504479, 32.6% CPU, 773 MB)
// HOW: 
//   1. Read Augment extension.js to find _cancelledByUser latch
//   2. Prove it's a one-way latch (set to true, never reset to false)
//   3. Trace connection between AbortError and the latch
//   4. Find runaway zygote processes and kill them
//   5. Provide fix recommendations
// RATIONALE: Database shows 761 "This operation was aborted" errors occurring every ~60 seconds
//            Stack trace: undici:14900:13 → processTicksAndRejections → globalThis.fetch → d2() → callApiStream()
//            These AbortErrors likely trigger _cancelledByUser latch, causing ALL tool calls to fail
// ENFORCEMENT: This script provides evidence-based diagnosis with verbatim code snippets

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

// ANSI colors for output
const RED = '\x1b[31m';
const GREEN = '\x1b[32m';
const YELLOW = '\x1b[33m';
const BLUE = '\x1b[34m';
const CYAN = '\x1b[36m';
const RESET = '\x1b[0m';

function log(color, label, message) {
    console.log(`${color}[${label}]${RESET} ${message}`);
}

function section(title) {
    console.log(`\n${'='.repeat(80)}`);
    console.log(`${CYAN}${title}${RESET}`);
    console.log(`${'='.repeat(80)}\n`);
}

// STEP 1: Find Augment extension.js
section('STEP 1: LOCATE AUGMENT EXTENSION');

const homeDir = process.env.HOME || process.env.USERPROFILE || '';
const extensionsDir = path.join(homeDir, '.vscode', 'extensions');

log(BLUE, 'INFO', `Searching for Augment extension in: ${extensionsDir}`);

let augmentExtPath = null;
try {
    const extensions = fs.readdirSync(extensionsDir);
    const augmentDirs = extensions.filter(dir => dir.startsWith('augment.vscode-augment-'));
    
    if (augmentDirs.length === 0) {
        log(RED, 'ERROR', 'No Augment extension found');
        process.exit(1);
    }
    
    // Use the most recent version
    augmentDirs.sort().reverse();
    const augmentDir = augmentDirs[0];
    augmentExtPath = path.join(extensionsDir, augmentDir, 'out', 'extension.js');
    
    if (!fs.existsSync(augmentExtPath)) {
        log(RED, 'ERROR', `extension.js not found at: ${augmentExtPath}`);
        process.exit(1);
    }
    
    log(GREEN, 'FOUND', augmentExtPath);
    const stats = fs.statSync(augmentExtPath);
    log(BLUE, 'INFO', `File size: ${(stats.size / 1024 / 1024).toFixed(2)} MB`);
} catch (err) {
    log(RED, 'ERROR', `Failed to find Augment extension: ${err.message}`);
    process.exit(1);
}

// STEP 2: Search for _cancelledByUser latch
section('STEP 2: ANALYZE _cancelledByUser LATCH');

log(BLUE, 'INFO', 'Reading extension.js and searching for _cancelledByUser...');

const content = fs.readFileSync(augmentExtPath, 'utf8');
const lines = content.split('\n');

// Find all references to _cancelledByUser
const cancelledByUserRefs = [];
lines.forEach((line, idx) => {
    if (line.includes('_cancelledByUser')) {
        cancelledByUserRefs.push({
            lineNum: idx + 1,
            line: line.trim()
        });
    }
});

log(GREEN, 'FOUND', `${cancelledByUserRefs.length} references to _cancelledByUser`);

// Categorize references
const setToTrue = cancelledByUserRefs.filter(ref => 
    ref.line.includes('_cancelledByUser') && 
    (ref.line.includes('= true') || ref.line.includes('=!0') || ref.line.includes('= !0'))
);

const setToFalse = cancelledByUserRefs.filter(ref => 
    ref.line.includes('_cancelledByUser') && 
    (ref.line.includes('= false') || ref.line.includes('=!1') || ref.line.includes('= !1'))
);

const initialization = cancelledByUserRefs.filter(ref =>
    ref.line.includes('_cancelledByUser') &&
    (ref.line.includes('= !1') || ref.line.includes('= false')) &&
    !ref.line.includes('this._cancelledByUser =')
);

const checks = cancelledByUserRefs.filter(ref =>
    ref.line.includes('if') && ref.line.includes('_cancelledByUser')
);

console.log(`\n${YELLOW}CATEGORIZATION:${RESET}`);
console.log(`  Initialization: ${initialization.length}`);
console.log(`  Set to TRUE: ${setToTrue.length}`);
console.log(`  Set to FALSE: ${setToFalse.length}`);
console.log(`  Conditional checks: ${checks.length}`);

// Show where it's set to true
if (setToTrue.length > 0) {
    console.log(`\n${RED}WHERE _cancelledByUser IS SET TO TRUE:${RESET}`);
    setToTrue.forEach(ref => {
        console.log(`  Line ${ref.lineNum}: ${ref.line.substring(0, 120)}`);
    });
}

// Show where it's set to false (should be NONE if it's a one-way latch)
if (setToFalse.length > 0) {
    console.log(`\n${GREEN}WHERE _cancelledByUser IS SET TO FALSE:${RESET}`);
    setToFalse.forEach(ref => {
        console.log(`  Line ${ref.lineNum}: ${ref.line.substring(0, 120)}`);
    });
} else {
    console.log(`\n${RED}⚠️  CRITICAL: _cancelledByUser is NEVER reset to false (ONE-WAY LATCH CONFIRMED)${RESET}`);
}

// Show conditional checks
if (checks.length > 0) {
    console.log(`\n${YELLOW}WHERE _cancelledByUser IS CHECKED:${RESET}`);
    checks.slice(0, 5).forEach(ref => {
        console.log(`  Line ${ref.lineNum}: ${ref.line.substring(0, 120)}`);
    });
    if (checks.length > 5) {
        console.log(`  ... and ${checks.length - 5} more`);
    }
}

