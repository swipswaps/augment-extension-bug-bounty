/**
 * programmatic-compile.js
 * 
 * PRF-Compliant TypeScript compilation and compliance verifier
 * 
 * This script:
 * 1. Loads and parses tsconfig.json
 * 2. Compiles all TS sources in hidden-terminal-watchdog
 * 3. Captures all diagnostics
 * 4. Scans emitted JS files for forbidden APIs (exec, execSync, spawnSync)
 * 5. Writes step-by-step log output to a timestamped logfile
 */

const ts = require('typescript');
const path = require('path');
const fs = require('fs');

// Step 0: Define logfile path with timestamp
const LOGFILE = `.notes/programmatic-compile-${Date.now()}.log`;
function log(msg) { 
    console.log(msg); 
    fs.appendFileSync(LOGFILE, msg + '\n');
}

log('START: programmatic-compile');

// Step 1: Locate tsconfig.json
const projectRoot = path.resolve('hidden-terminal-watchdog');
const configPath = ts.findConfigFile(projectRoot, ts.sys.fileExists, 'tsconfig.json');

if (!configPath) {
    log('ERROR: tsconfig.json not found at project root');
    process.exit(1);
}
log(`tsconfig.json found at: ${configPath}`);

// Step 2: Read and parse tsconfig.json
const { config, error } = ts.readConfigFile(configPath, ts.sys.readFile);
if (error) {
    log(`ERROR: Failed to read tsconfig.json: ${JSON.stringify(error)}`);
    process.exit(1);
}

// Step 3: Parse JSON config to get fileNames and compiler options
const parsed = ts.parseJsonConfigFileContent(config, ts.sys, path.dirname(configPath));
log(`TS files to compile: ${parsed.fileNames.join(', ')}`);

// Step 4: Create the program and emit files
const program = ts.createProgram(parsed.fileNames, parsed.options);
log('Compiling TypeScript files...');
const emitResult = program.emit();

// Step 5: Collect diagnostics
const allDiagnostics = ts.getPreEmitDiagnostics(program).concat(emitResult.diagnostics);
if (allDiagnostics.length > 0) {
    log(`Diagnostics detected (${allDiagnostics.length}):`);
    allDiagnostics.forEach(diagnostic => {
        if (diagnostic.file) {
            const { line, character } = diagnostic.file.getLineAndCharacterOfPosition(diagnostic.start);
            const message = ts.flattenDiagnosticMessageText(diagnostic.messageText, '\n');
            log(`${diagnostic.file.fileName} (${line + 1},${character + 1}): ${message}`);
        } else {
            log(ts.flattenDiagnosticMessageText(diagnostic.messageText, '\n'));
        }
    });
    process.exit(1); // Fail compilation if any diagnostic
}
log('Compilation successful.');

// Step 6: Scan emitted JS files for forbidden APIs
log('Scanning emitted JS files for forbidden APIs...');
const outDir = parsed.options.outDir || path.join(projectRoot, 'out');

function scanDir(dir) {
    const entries = fs.readdirSync(dir);
    for (const entry of entries) {
        const fullPath = path.join(dir, entry);
        const stat = fs.statSync(fullPath);
        if (stat.isDirectory()) {
            scanDir(fullPath);
        } else if (entry.endsWith('.js')) {
            const content = fs.readFileSync(fullPath, 'utf8');
            if (/exec\(|execSync\(|spawnSync\(/.test(content)) {
                log(`FORBIDDEN API DETECTED: ${fullPath}`);
                process.exit(1);
            }
        }
    }
}

scanDir(outDir);
log('No forbidden APIs detected.');
log('Compliance verification passed.');

log('END: programmatic-compile');
process.exit(0);

