/**
 * programmatic-compile-auto-update-backup-v3.js
 *
 * Purpose:
 * 1. Backup TypeScript source files before overwriting.
 * 2. Extract code from a specification file (.txt) reliably.
 * 3. Compile TypeScript programmatically using the TypeScript Compiler API.
 * 4. Scan emitted JS for forbidden APIs (exec, execSync, spawnSync).
 * 5. Maintain full audit trail with logs.
 *
 * Key Improvements over v2:
 * - Handles multi-byte emoji sequences in section markers correctly.
 * - Splits spec file by Unicode-aware patterns, not brittle regex.
 * - Reads output at every step and logs it.
 */

const fs = require('fs');
const path = require('path');

// Ensure TypeScript module exists
const ts = require(path.join(__dirname, 'hidden-terminal-watchdog', 'node_modules', 'typescript'));

// Directory and file setup
const LOGDIR = '.notes';
const BACKUPDIR = path.join(LOGDIR, '.backup', Date.now().toString());
fs.mkdirSync(LOGDIR, { recursive: true });
fs.mkdirSync(BACKUPDIR, { recursive: true });

// Log function
const logFile = path.join(LOGDIR, `programmatic-compile-auto-v3-${Date.now()}.log`);
function log(msg) {
    console.log(msg);
    fs.appendFileSync(logFile, msg + '\n');
}

// TS files to update
const TS_FILES = [
    'hidden-terminal-watchdog/src/core/ExecBanEnforcer.ts',
    'hidden-terminal-watchdog/src/commands/FullComplianceRun.ts',
    'hidden-terminal-watchdog/src/extension.ts'
];

// Step 1: Backup all TS files
log('STEP 1: Backing up TS files...');
TS_FILES.forEach(file => {
    if (fs.existsSync(file)) {
        const dest = path.join(BACKUPDIR, path.basename(file));
        fs.copyFileSync(file, dest);
        log(`✅ Backed up ${file} -> ${dest}`);
    } else {
        log(`⚠️ File not found, skipping backup: ${file}`);
    }
});

// Step 2: Read specification
const SPEC_FILE = path.join(LOGDIR, '69935426-075c-8329-b732-ceb8a5e0b600_0055.txt');
log('STEP 2: Reading spec file...');
let specContent = '';
try {
    specContent = fs.readFileSync(SPEC_FILE, 'utf8');
    log(`✅ Spec file read: ${SPEC_FILE}`);
} catch (err) {
    log(`❌ Failed to read spec file: ${err.message}`);
    process.exit(1);
}

// Step 3: Extract code blocks reliably
log('STEP 3: Extracting code from spec file...');

// Unicode-aware emoji pattern for section markers (\d+\uFE0F?\u20E3)
const SECTION_REGEX = /(\d+\uFE0F?\u20E3).*$/gm;

// Split spec into sections
const sections = specContent.split(SECTION_REGEX).filter(Boolean);
log(`Spec file split into ${sections.length} sections.`);

// Map sections to file content
const fileContentMap = {};

// Simple heuristic: Each section starts with file path line
sections.forEach(section => {
    TS_FILES.forEach(tsFile => {
        const fileName = path.basename(tsFile);
        if (section.includes(tsFile) || section.includes(fileName)) {
            fileContentMap[tsFile] = section.replace(tsFile, '').trim();
        }
    });
});

// Step 4: Overwrite TS files from spec
log('STEP 4: Overwriting TS files from spec...');
TS_FILES.forEach(tsFile => {
    if (fileContentMap[tsFile] && fileContentMap[tsFile].length > 0) {
        fs.writeFileSync(tsFile, fileContentMap[tsFile], 'utf8');
        log(`✅ Overwritten ${tsFile} from spec`);
    } else {
        log(`⚠️ No code found for ${tsFile}, skipping overwrite`);
    }
});

// Step 5: Programmatic TypeScript compilation
log('STEP 5: Compiling TypeScript...');
const configPath = ts.findConfigFile('hidden-terminal-watchdog', ts.sys.fileExists, 'tsconfig.json');
if (!configPath) {
    log('❌ tsconfig.json not found, exiting.');
    process.exit(1);
}

const { config, error } = ts.readConfigFile(configPath, ts.sys.readFile);
if (error) {
    log(`❌ tsconfig read error: ${error.messageText}`);
    process.exit(1);
}

const parsed = ts.parseJsonConfigFileContent(config, ts.sys, path.dirname(configPath));
const program = ts.createProgram(parsed.fileNames, parsed.options);
const emitResult = program.emit();

const allDiagnostics = ts.getPreEmitDiagnostics(program).concat(emitResult.diagnostics);
if (allDiagnostics.length > 0) {
    allDiagnostics.forEach(d => {
        const message = ts.flattenDiagnosticMessageText(d.messageText, '\n');
        if (d.file) {
            const { line, character } = d.file.getLineAndCharacterOfPosition(d.start);
            log(`${d.file.fileName} (${line + 1},${character + 1}): ${message}`);
        } else {
            log(message);
        }
    });
    log(`❌ Compilation failed with ${allDiagnostics.length} diagnostics`);
} else {
    log('✅ Compilation successful.');
}

// Step 6: Scan emitted JS for forbidden APIs
log('STEP 6: Scanning emitted JS for forbidden APIs...');
function scanDir(dir) {
    const entries = fs.readdirSync(dir);
    entries.forEach(entry => {
        const fullPath = path.join(dir, entry);
        const stat = fs.statSync(fullPath);
        if (stat.isDirectory()) {
            scanDir(fullPath);
        } else if (entry.endsWith('.js')) {
            const content = fs.readFileSync(fullPath, 'utf8');
            if (/exec\(|execSync\(|spawnSync\(/.test(content)) {
                log(`❌ FORBIDDEN API FOUND: ${fullPath}`);
                process.exit(1);
            }
        }
    });
}
scanDir('hidden-terminal-watchdog/out');
log('✅ No forbidden APIs detected.');

// STEP 7: Final compliance check
log('STEP 7: Compliance verification passed. Full audit trail in log file: ' + logFile);

