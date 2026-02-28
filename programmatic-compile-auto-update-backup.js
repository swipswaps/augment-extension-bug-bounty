/**
 * programmatic-compile-auto-update-backup.js
 *
 * PRF-Compliant TypeScript compilation with auto-updates and immutable backups
 *
 * Steps:
 * 1. Ensure .notes and .backup directories exist
 * 2. Create timestamped log file
 * 3. Backup each TS file before overwriting
 * 4. Read specification file and overwrite TS files
 * 5. Log every backup and modification step
 * 6. Compile programmatically using TypeScript Compiler API
 * 7. Scan emitted JS for forbidden APIs
 * 8. Exit on errors
 */

const path = require('path');
const fs = require('fs');
const ts = require(path.resolve('hidden-terminal-watchdog/node_modules/typescript'));

// ---------- Step 0: Setup directories ----------
const notesDir = path.resolve('.notes');
if (!fs.existsSync(notesDir)) fs.mkdirSync(notesDir, { recursive: true });

const backupDir = path.join(notesDir, '.backup', `${Date.now()}`);
fs.mkdirSync(backupDir, { recursive: true });

const LOGFILE = path.join(notesDir, `programmatic-compile-auto-backup-${Date.now()}.log`);
function log(msg) {
    console.log(msg);
    fs.appendFileSync(LOGFILE, msg + '\n');
}

log('START: programmatic-compile-auto-update-backup');

// ---------- Step 1: Read spec file ----------
const specFilePath = path.resolve('.notes/69935426-075c-8329-b732-ceb8a5e0b600_0055.txt');
if (!fs.existsSync(specFilePath)) {
    log(`ERROR: Spec file not found: ${specFilePath}`);
    process.exit(1);
}
log(`Spec file found: ${specFilePath}`);
const specContent = fs.readFileSync(specFilePath, 'utf8');

// ---------- Step 2: Define TS files map ----------
const tsFilesMap = {
    'ExecBanEnforcer.ts': path.resolve('hidden-terminal-watchdog/src/core/ExecBanEnforcer.ts'),
    'FullComplianceRun.ts': path.resolve('hidden-terminal-watchdog/src/commands/FullComplianceRun.ts'),
    'extension.ts': path.resolve('hidden-terminal-watchdog/src/extension.ts'),
};

// ---------- Step 3: Backup and overwrite ----------
for (const [key, tsPath] of Object.entries(tsFilesMap)) {
    if (!fs.existsSync(tsPath)) {
        log(`WARNING: TS file not found, skipping backup: ${tsPath}`);
        continue;
    }

    // Backup original
    const backupPath = path.join(backupDir, key);
    fs.copyFileSync(tsPath, backupPath);
    log(`Backed up ${tsPath} → ${backupPath}`);

    // Extract code from spec
    // Strategy: Find the file path line, then extract everything from the next non-empty line
    // until we hit a line starting with a digit followed by emoji (section marker)
    const relPath = tsPath.replace(path.resolve('.') + path.sep, '').replace(/\\/g, '/');

    // Find the line with the file path
    const lines = specContent.split('\n');
    let startIndex = -1;
    for (let i = 0; i < lines.length; i++) {
        if (lines[i].trim() === relPath) {
            startIndex = i;
            break;
        }
    }

    if (startIndex === -1) {
        log(`WARNING: Path ${relPath} not found in spec, skipping overwrite`);
        continue;
    }

    // Skip blank lines after the path
    let codeStartIndex = startIndex + 1;
    while (codeStartIndex < lines.length && lines[codeStartIndex].trim() === '') {
        codeStartIndex++;
    }

    // Find the end (next section marker or end of file)
    let codeEndIndex = codeStartIndex;
    while (codeEndIndex < lines.length) {
        // Check if line starts with digit + emoji (section marker like "2️⃣")
        if (/^[0-9]/.test(lines[codeEndIndex])) {
            break;
        }
        codeEndIndex++;
    }

    // Extract the code
    const code = lines.slice(codeStartIndex, codeEndIndex).join('\n').trim();
    log(`DEBUG: Extracted ${code.length} characters for ${key}, first 100 chars: ${code.substring(0, 100)}`);
    fs.writeFileSync(tsPath, code, 'utf8');
    log(`Overwritten ${tsPath} from spec`);
}

// ---------- Step 4: Programmatic TypeScript compilation ----------
log('Starting programmatic compilation...');
const projectRoot = path.resolve('hidden-terminal-watchdog');
const configPath = ts.findConfigFile(projectRoot, ts.sys.fileExists, 'tsconfig.json');
if (!configPath) {
    log('ERROR: tsconfig.json not found');
    process.exit(1);
}

const { config, error } = ts.readConfigFile(configPath, ts.sys.readFile);
if (error) {
    log(`ERROR reading tsconfig.json: ${JSON.stringify(error)}`);
    process.exit(1);
}

const parsed = ts.parseJsonConfigFileContent(config, ts.sys, path.dirname(configPath));
const program = ts.createProgram(parsed.fileNames, parsed.options);
const emitResult = program.emit();

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
    process.exit(1);
}
log('Compilation successful.');

// ---------- Step 5: Scan emitted JS for forbidden APIs ----------
log('Scanning emitted JS files for forbidden APIs...');
const outDir = parsed.options.outDir || path.join(projectRoot, 'out');

function scanDir(dir) {
    const entries = fs.readdirSync(dir);
    for (const entry of entries) {
        const fullPath = path.join(dir, entry);
        const stat = fs.statSync(fullPath);
        if (stat.isDirectory()) scanDir(fullPath);
        else if (entry.endsWith('.js')) {
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
log('PRF Compliance verification passed.');
log('END: programmatic-compile-auto-update-backup');
process.exit(0);

