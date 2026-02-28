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
const ts = require(path.resolve('hidden-terminal-watchdog/node_modules/typescript'));

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

// ---------- Backup & Overwrite ----------
for (const [key, relPath] of Object.entries(tsFilesMap)) {
  const fullPath = path.resolve(relPath);
  if (!fs.existsSync(fullPath)) {
    log(`WARNING: TS file not found, skipping backup: ${fullPath}`);
    continue;
  }

  // Backup original
  const backupPath = path.join(backupDir, key);
  fs.copyFileSync(fullPath, backupPath);
  log(`Backed up ${fullPath} → ${backupPath}`);

  // Find code in sections
  let found = false;
  for (const section of sections) {
    if (section.includes(relPath)) {
      const lines = section.split('\n');
      const startIdx = lines.findIndex(l => l.trim() === relPath) + 1;
      const codeLines = lines.slice(startIdx).filter(l => l.trim() !== '');
      const code = codeLines.join('\n').trim();
      if (code.length > 0) {
        fs.writeFileSync(fullPath, code, 'utf8');
        log(`Overwritten ${fullPath} from spec`);
        found = true;
        break;
      }
    }
  }

  if (!found) {
    log(`WARNING: No code found for ${key}, skipping overwrite`);
  }
}

// ---------- Programmatic TypeScript compilation ----------
const tsModulePath = path.resolve('hidden-terminal-watchdog/node_modules/typescript');
if (!fs.existsSync(tsModulePath)) {
  log('ERROR: Cannot find TypeScript module in hidden-terminal-watchdog/node_modules');
  process.exit(1);
}
const ts = require(tsModulePath);
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

// ---------- Scan emitted JS ----------
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
log('END: programmatic-compile-auto-update-backup-v2');
process.exit(0);

