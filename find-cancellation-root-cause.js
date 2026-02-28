#!/usr/bin/env node
/**
 * FIND CANCELLATION ROOT CAUSE
 * 
 * PURPOSE:
 * - Prove whether AbortError causes _cancelledByUser latch to be set
 * - Find the exact code path from AbortError to "Cancelled by user" tool errors
 * - Determine if this is why Augment is unusable
 * 
 * WHAT: Read Augment extension.js and trace the cancellation logic
 * WHY: User complaint: "augment is UNUSABLE" - all tool calls return "Cancelled by user"
 * HOW: 
 *   1. Find _cancelledByUser variable in extension.js
 *   2. Find where it's set to true
 *   3. Find where it's checked (should be in tool call handler)
 *   4. Verify it's never reset to false (one-way latch)
 *   5. Trace connection to AbortError
 * 
 * EVIDENCE FROM LOGS:
 * - 739 "This operation was aborted" errors in database
 * - AbortError thrown from undici every 60 seconds
 * - Call chain: d2@64:59334 → callApiStream@250:8939 → getRemoteAgentOverviewsStream
 * - Diagnostic context says: "_cancelledByUser one-way latch at L603"
 */

const fs = require('fs');
const path = require('path');

// WHAT: Find the Augment extension.js file
// WHY: Need to read the actual code to prove the latch behavior
// HOW: Search ~/.vscode/extensions for augment.vscode-augment-*/out/extension.js
function findAugmentExtension() {
    const extensionsDir = path.join(process.env.HOME, '.vscode', 'extensions');
    const dirs = fs.readdirSync(extensionsDir);
    
    for (const dir of dirs) {
        if (dir.startsWith('augment.vscode-augment-')) {
            const extPath = path.join(extensionsDir, dir, 'out', 'extension.js');
            if (fs.existsSync(extPath)) {
                return extPath;
            }
        }
    }
    throw new Error('Augment extension.js not found');
}

// WHAT: Extract lines around a specific line number
// WHY: Need context around L603 where _cancelledByUser is allegedly located
// HOW: Read file, split by newlines, extract range
function extractLines(filePath, lineNum, contextBefore = 20, contextAfter = 20) {
    const content = fs.readFileSync(filePath, 'utf8');
    const lines = content.split('\n');
    const start = Math.max(0, lineNum - contextBefore - 1);
    const end = Math.min(lines.length, lineNum + contextAfter);
    
    return lines.slice(start, end).map((line, idx) => {
        const actualLineNum = start + idx + 1;
        const marker = actualLineNum === lineNum ? '>>> ' : '    ';
        return `${marker}${actualLineNum}: ${line}`;
    }).join('\n');
}

// WHAT: Search for all occurrences of a pattern in the file
// WHY: Need to find ALL places where _cancelledByUser is referenced
// HOW: Read file, use regex to find matches with line numbers
function searchPattern(filePath, pattern) {
    const content = fs.readFileSync(filePath, 'utf8');
    const lines = content.split('\n');
    const results = [];
    
    for (let i = 0; i < lines.length; i++) {
        if (lines[i].match(pattern)) {
            results.push({
                line: i + 1,
                content: lines[i].trim()
            });
        }
    }
    
    return results;
}

// MAIN EXECUTION
console.log('=== FINDING CANCELLATION ROOT CAUSE ===\n');

try {
    const extPath = findAugmentExtension();
    console.log(`Found Augment extension: ${extPath}\n`);
    
    // STEP 1: Check line 603 for _cancelledByUser
    console.log('=== STEP 1: Checking L603 for _cancelledByUser ===');
    console.log(extractLines(extPath, 603, 10, 10));
    console.log('\n');
    
    // STEP 2: Find ALL references to _cancelledByUser
    console.log('=== STEP 2: Finding ALL _cancelledByUser references ===');
    const cancelRefs = searchPattern(extPath, /_cancelledByUser/);
    console.log(`Found ${cancelRefs.length} references:\n`);
    cancelRefs.forEach(ref => {
        console.log(`  L${ref.line}: ${ref.content}`);
    });
    console.log('\n');
    
    // STEP 3: Find where it's set to true
    console.log('=== STEP 3: Finding where _cancelledByUser is set to true ===');
    const setTrue = searchPattern(extPath, /_cancelledByUser\s*=\s*(!0|true)/);
    console.log(`Found ${setTrue.length} locations:\n`);
    setTrue.forEach(ref => {
        console.log(`  L${ref.line}: ${ref.content}`);
        console.log(extractLines(extPath, ref.line, 5, 5));
        console.log('\n');
    });
    
    // STEP 4: Find where it's set to false (should be NONE if it's a one-way latch)
    console.log('=== STEP 4: Finding where _cancelledByUser is set to false ===');
    const setFalse = searchPattern(extPath, /_cancelledByUser\s*=\s*(!1|false)/);
    console.log(`Found ${setFalse.length} locations:\n`);
    if (setFalse.length === 0) {
        console.log('  ✅ CONFIRMED: _cancelledByUser is NEVER reset to false (one-way latch)\n');
    } else {
        setFalse.forEach(ref => {
            console.log(`  L${ref.line}: ${ref.content}`);
        });
    }
    
    // STEP 5: Find "Cancelled by user" error message
    console.log('=== STEP 5: Finding "Cancelled by user" error message ===');
    const cancelMsg = searchPattern(extPath, /Cancelled by user/);
    console.log(`Found ${cancelMsg.length} locations:\n`);
    cancelMsg.forEach(ref => {
        console.log(`  L${ref.line}: ${ref.content}`);
        console.log(extractLines(extPath, ref.line, 10, 5));
        console.log('\n');
    });
    
    console.log('=== ANALYSIS COMPLETE ===');
    
} catch (err) {
    console.error('ERROR:', err.message);
    process.exit(1);
}

