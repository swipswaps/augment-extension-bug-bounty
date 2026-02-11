#!/usr/bin/env node
/**
 * COMPLETE FIX - Apply all three fixes to resolve timeout issue
 * 
 * This script applies:
 * 1. Webview fix (already applied) - Catch timeout errors
 * 2. Extension host fix - Read output BEFORE killing process
 * 3. Webview ideal fix - Wait for output before throwing
 * 
 * Usage: node apply-complete-fix.js
 */

const fs = require('fs');
const path = require('path');

const EXTENSION_DIR = path.join(process.env.HOME, '.vscode/extensions/augment.vscode-augment-0.754.3');
const EXTENSION_JS = path.join(EXTENSION_DIR, 'out/extension.js');
const WEBVIEW_JS = path.join(EXTENSION_DIR, 'common-webviews/assets/extension-client-context-CN64fWtK.js');

console.log('=== COMPLETE FIX APPLICATION ===\n');

// Backup files
console.log('Step 1: Creating backups...');
const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
fs.copyFileSync(EXTENSION_JS, `${EXTENSION_JS}.backup-${timestamp}`);
fs.copyFileSync(WEBVIEW_JS, `${WEBVIEW_JS}.backup-${timestamp}`);
console.log(`✓ Backups created with timestamp: ${timestamp}\n`);

// Fix 1: Extension Host - Read output BEFORE killing
console.log('Step 2: Applying Extension Host fix (read output before kill)...');
let extensionCode = fs.readFileSync(EXTENSION_JS, 'utf8');

const oldKillCode = 'this._isLongRunningTerminal(n.terminal) ? (this._logger.debug("Sending Ctrl+C to interrupt current command in long-running terminal"), n.terminal.sendText("", !1)) : n.terminal.dispose(), n.state = "killed", n.exitCode = -1;\\n            let o = await this.hybridReadOutput(r);';

const newKillCode = 'let o = await this.hybridReadOutput(r);\\n            n.output = o?.output ?? "";\\n            this._logger.debug(`Captured ${n.output.length} bytes of output before killing process`);\\n            this._isLongRunningTerminal(n.terminal) ? (this._logger.debug("Sending Ctrl+C after capturing output"), n.terminal.sendText("", !1)) : n.terminal.dispose(), n.state = "killed", n.exitCode = -1;';

if (extensionCode.includes(oldKillCode)) {
    extensionCode = extensionCode.replace(oldKillCode, newKillCode);
    fs.writeFileSync(EXTENSION_JS, extensionCode);
    console.log('✓ Extension host fix applied (line 259682)\n');
} else {
    console.log('⚠ Extension host code not found - may already be fixed or version mismatch\n');
}

// Fix 2: Webview - Wait for output before throwing
console.log('Step 3: Applying Webview ideal fix (wait for output)...');
let webviewCode = fs.readFileSync(WEBVIEW_JS, 'utf8');

const oldTimeoutCode = 'if (g) {\\n                const m = yield* O();\\n                throw yield* w([m, m.cancelToolRun], n, o), new Error("Tool call was cancelled due to timeout")\\n            }';

const newTimeoutCode = `if (g) {
                const m = yield* O();
                yield* w([m, m.cancelToolRun], n, o);
                yield* je(500);
                const toolState = yield* Ln.effect(n, o);
                if (toolState.result && toolState.result.text) {
                    return;
                }
                yield* E(Qs(n, o, {
                    isError: !1,
                    text: \`Tool call timed out after \${p} seconds. Process was terminated. Output may have been captured before termination. Check terminal for partial output.\`
                }));
                return;
            }`;

if (webviewCode.includes(oldTimeoutCode)) {
    webviewCode = webviewCode.replace(oldTimeoutCode, newTimeoutCode);
    fs.writeFileSync(WEBVIEW_JS, webviewCode);
    console.log('✓ Webview ideal fix applied (line 44333)\n');
} else {
    console.log('⚠ Webview timeout code not found - checking if catch block fix is sufficient\n');
}

// Verify fixes
console.log('Step 4: Verifying fixes...');
const extensionFixed = fs.readFileSync(EXTENSION_JS, 'utf8');
const webviewFixed = fs.readFileSync(WEBVIEW_JS, 'utf8');

let fixCount = 0;

if (extensionFixed.includes('Captured') && extensionFixed.includes('before killing')) {
    console.log('✓ Extension host fix verified');
    fixCount++;
}

if (webviewFixed.includes('RULE 9 BLOCKING FIX')) {
    console.log('✓ Webview catch block fix verified');
    fixCount++;
}

if (webviewFixed.includes('Output may have been captured before termination')) {
    console.log('✓ Webview ideal fix verified');
    fixCount++;
}

console.log(`\\n=== SUMMARY ===`);
console.log(`Fixes applied: ${fixCount}/3`);
console.log(`\\nBackup files:`);
console.log(`- ${EXTENSION_JS}.backup-${timestamp}`);
console.log(`- ${WEBVIEW_JS}.backup-${timestamp}`);
console.log(`\\n⚠ RESTART VS CODE for changes to take effect`);
console.log(`\\nTest with: sleep 15`);
console.log(`Expected: Output captured before Ctrl+C is sent`);

