#!/usr/bin/env node
/**
 * EXTENSION LIFECYCLE PATCHER
 * 
 * Applies permanent fixes to extension.js by:
 *   1. Patching _closingPromise latch (Line 603)
 *   2. Patching getRemoteAgentOverviewsStream (Line 306)
 *   3. Adding instrumentation
 * 
 * USAGE:
 *   node .augment/apply-lifecycle-fixes.js
 */

const fs = require('fs');
const path = require('path');

const EXTENSION_PATH = path.join(
  process.env.HOME,
  '.vscode/extensions/augment.vscode-augment-0.792.0/out/extension.js'
);

const BACKUP_PATH = EXTENSION_PATH + '.backup-lifecycle-fix-' + Date.now();
const LOG_FILE = path.join(__dirname, '../.notes/lifecycle-patch.log');

function log(message) {
  const timestamp = new Date().toISOString();
  const entry = `[${timestamp}] ${message}\n`;
  fs.appendFileSync(LOG_FILE, entry);
  console.log(entry.trim());
}

/**
 * PHASE 1: BACKUP ORIGINAL
 */
function backupExtension() {
  log('Creating backup: ' + BACKUP_PATH);
  fs.copyFileSync(EXTENSION_PATH, BACKUP_PATH);
  log('Backup created successfully');
}

/**
 * PHASE 2: PATCH _closingPromise LATCH
 * 
 * Find and replace the broken close() pattern with idempotent version
 */
function patchClosingPromiseLatch(code) {
  log('Patching _closingPromise latch...');
  
  // Pattern to find (minified):
  // close(t=!1){return this._closingPromise===void 0&&(this._cancelledByUser=t,this._closingPromise=(async()=>{...})()),this._closingPromise}
  
  const pattern = /close\(([^)]*)\)\{return this\._closingPromise===void 0&&\(this\._cancelledByUser=([^,]+),this\._closingPromise=\(async\(\)=>\{/g;
  
  const replacement = `close($1){if(this._closed)return Promise.resolve();if(this._closingPromise)return this._closingPromise;this._closing=!0;this._closingPromise=(async()=>{try{this._cancelledByUser=$2;`;
  
  let patched = code.replace(pattern, replacement);
  
  // Add finally block to reset latch
  // Find the end of the close() async function and add finally
  const asyncEndPattern = /(\}\)\(\))\),this\._closingPromise\}/g;
  patched = patched.replace(asyncEndPattern, '$1).finally(()=>{this._closing=!1;this._closingPromise=null}),this._closingPromise}');
  
  if (patched !== code) {
    log('✓ _closingPromise latch patched successfully');
  } else {
    log('⚠ _closingPromise latch pattern not found - may need manual review');
  }
  
  return patched;
}

/**
 * PHASE 3: PATCH ASYNC GENERATOR CLEANUP
 * 
 * Add finally block to getRemoteAgentOverviewsStream
 */
function patchAsyncGeneratorCleanup(code) {
  log('Patching async generator cleanup...');
  
  // Pattern: async*getRemoteAgentOverviewsStream(...){...for await(let s of o)yield s}
  const pattern = /(async\*getRemoteAgentOverviewsStream[^{]*\{[^}]*for await\([^)]+of ([^)]+)\)yield [^}]+)\}/g;
  
  const replacement = `$1}finally{if($2&&typeof $2.return==='function'){try{await $2.return()}catch{}}if($2&&typeof $2.destroy==='function'){try{$2.destroy()}catch{}}if($2&&$2.body&&typeof $2.body.cancel==='function'){try{await $2.body.cancel()}catch{}}}}`;
  
  const patched = code.replace(pattern, replacement);
  
  if (patched !== code) {
    log('✓ Async generator cleanup patched successfully');
  } else {
    log('⚠ Async generator pattern not found - may need manual review');
  }
  
  return patched;
}

/**
 * PHASE 4: ADD INSTRUMENTATION
 * 
 * Inject logging at critical points
 */
function addInstrumentation(code) {
  log('Adding instrumentation...');
  
  // Add logging to close() invocations
  const closeCallPattern = /\.close\((!0|!1|true|false)\)/g;
  const patched = code.replace(closeCallPattern, (match, arg) => {
    return `.close(${arg})||console.error('[LIFECYCLE] close(${arg}) called at',new Date().toISOString(),new Error().stack.split('\\n')[1])`;
  });
  
  if (patched !== code) {
    log('✓ Instrumentation added successfully');
  } else {
    log('⚠ No close() calls found for instrumentation');
  }
  
  return patched;
}

/**
 * PHASE 5: APPLY ALL PATCHES
 */
function applyPatches() {
  log('='.repeat(80));
  log('LIFECYCLE PATCHER STARTING');
  log('='.repeat(80));
  
  // Check if extension exists
  if (!fs.existsSync(EXTENSION_PATH)) {
    log('ERROR: Extension not found at: ' + EXTENSION_PATH);
    process.exit(1);
  }
  
  // Backup
  backupExtension();
  
  // Read original
  log('Reading extension.js...');
  let code = fs.readFileSync(EXTENSION_PATH, 'utf8');
  const originalSize = code.length;
  log(`Original size: ${originalSize} bytes`);
  
  // Apply patches
  code = patchClosingPromiseLatch(code);
  code = patchAsyncGeneratorCleanup(code);
  code = addInstrumentation(code);
  
  const patchedSize = code.length;
  log(`Patched size: ${patchedSize} bytes (delta: ${patchedSize - originalSize})`);
  
  // Write patched version
  log('Writing patched extension.js...');
  fs.writeFileSync(EXTENSION_PATH, code, 'utf8');
  
  log('='.repeat(80));
  log('LIFECYCLE PATCHER COMPLETE');
  log('='.repeat(80));
  log('');
  log('NEXT STEPS:');
  log('1. Reload VS Code window (Ctrl+Shift+P → "Developer: Reload Window")');
  log('2. Monitor .notes/lifecycle-guard.log for instrumentation output');
  log('3. Check FD count: lsof 2>/dev/null | grep -c code');
  log('');
  log('To restore original:');
  log(`  cp ${BACKUP_PATH} ${EXTENSION_PATH}`);
  log('');
}

// Execute
if (require.main === module) {
  try {
    applyPatches();
  } catch (error) {
    log('FATAL ERROR: ' + error.message);
    log(error.stack);
    process.exit(1);
  }
}

module.exports = { applyPatches };

