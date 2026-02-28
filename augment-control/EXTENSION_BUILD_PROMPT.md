# MANDATORY VS CODE EXTENSION BUILD PROMPT - COMPLIANCE ENFORCED

## EXECUTION PROTOCOL (ZERO EVASION TOLERANCE)

This prompt ENFORCES compliance by requiring ACTUAL CODE execution with VERIFIABLE OUTPUT.

### RULE 0: TEST IMMEDIATELY - NO EXCEPTIONS

Before ANY response, you MUST execute these commands and show output:

**TEST 1: Compilation**
```bash
cd hidden-terminal-watchdog && npm run compile 2>&1 && echo "---COMPILE-SUCCESS---" && ls -la out/extension.js
```

**TEST 2: TypeScript Validation**
```bash
cd hidden-terminal-watchdog && npx tsc --noEmit 2>&1 && echo "---TYPESCRIPT-VALID---"
```

**TEST 3: Syntax Check (JavaScript AST parse)**
```bash
cd hidden-terminal-watchdog && node -e "
const fs = require('fs');
const code = fs.readFileSync('./out/extension.js', 'utf8');
try {
  new Function(code);
  console.log('✓ JavaScript syntax valid');
  console.log('✓ File size:', code.length, 'bytes');
  console.log('✓ Contains activate:', code.includes('function activate'));
  console.log('✓ Contains deactivate:', code.includes('function deactivate'));
  console.log('---SYNTAX-VALID---');
} catch (e) {
  console.error('FAIL: Syntax error:', e.message);
  process.exit(1);
}
" 2>&1
```

**TEST 4: Package.json Validation**
```bash
cd hidden-terminal-watchdog && node -e "
const pkg = require('./package.json');
console.log('✓ Name:', pkg.name);
console.log('✓ Main:', pkg.main);
console.log('✓ Commands:', pkg.contributes?.commands?.length || 0);
if (pkg.main !== './out/extension.js') { console.error('FAIL: Wrong main path'); process.exit(1); }
if (!pkg.contributes?.commands) { console.error('FAIL: No commands'); process.exit(1); }
console.log('---PACKAGE-VALID---');
" 2>&1
```

**FORBIDDEN**: Responding without running ALL 4 tests and showing output.

### RULE 1: NO PACKAGING - DEVELOPMENT MODE ONLY
- DO NOT attempt to run `vsce package`
- DO NOT create `.vsix` files
- DO NOT troubleshoot packaging issues
- ONLY use F5 debugging (Extension Development Host)
- The extension MUST work in development mode FIRST

### RULE 2: EXACT FILE STRUCTURE (NON-NEGOTIABLE)
```
hidden-terminal-watchdog/
├── package.json          (MUST have "main": "./out/extension.js")
├── tsconfig.json         (MUST have "outDir": "out")
├── src/
│   └── extension.ts      (ACTUAL IMPLEMENTATION CODE)
└── out/
    └── extension.js      (COMPILED OUTPUT)
```

### RULE 3: ACTUAL CODE REQUIREMENTS

#### extension.ts MUST CONTAIN:

1. **Process Detection Function** (MANDATORY):
```typescript
function detectHiddenTerminals(): Promise<ProcessInfo[]> {
    return new Promise((resolve) => {
        const cmd = `pgrep -u ${os.userInfo().username} -f "code.*--ms-enable-electron-run-as-node|extensionHost"`;
        exec(cmd, (err, stdout) => {
            if (err) { resolve([]); return; }
            const pids = stdout.trim().split('\n').filter(Boolean).map(p => parseInt(p, 10));
            // Get command lines for each PID
            const promises = pids.map(pid => getProcessInfo(pid));
            Promise.all(promises).then(resolve);
        });
    });
}
```

2. **Process Killing Function** (MANDATORY):
```typescript
function killProcess(pid: number): Promise<boolean> {
    return new Promise((resolve) => {
        exec(`kill -TERM ${pid}`, (err) => {
            if (err) { resolve(false); return; }
            setTimeout(() => {
                exec(`kill -0 ${pid} 2>/dev/null`, (checkErr) => {
                    if (checkErr) { resolve(true); return; }
                    exec(`kill -KILL ${pid}`, () => resolve(true));
                });
            }, 2000);
        });
    });
}
```

3. **Logging to File AND Terminal** (MANDATORY):
```typescript
const logFile = path.join(os.homedir(), '.hidden-terminal-watchdog.log');
function log(message: string) {
    const timestamp = new Date().toISOString();
    const logLine = `[${timestamp}] ${message}\n`;
    
    // Write to file
    fs.appendFileSync(logFile, logLine);
    
    // Write to VS Code output channel
    outputChannel.appendLine(message);
    
    // Write to console (visible in Extension Development Host)
    console.log(message);
}
```

4. **Monitoring Loop** (MANDATORY):
```typescript
let monitorInterval: NodeJS.Timeout;

function startMonitoring() {
    const interval = vscode.workspace.getConfiguration('watchdog').get<number>('monitorInterval', 5000);
    
    monitorInterval = setInterval(async () => {
        const processes = await detectHiddenTerminals();
        log(`[MONITOR] Found ${processes.length} hidden terminals`);
        
        if (processes.length > 0) {
            log(`[DETAILS] PIDs: ${processes.map(p => p.pid).join(', ')}`);
            processes.forEach(p => log(`  - PID ${p.pid}: ${p.command}`));
        }
        
        const maxTerminals = vscode.workspace.getConfiguration('watchdog').get<number>('maxTerminals', 20);
        if (processes.length >= maxTerminals) {
            log(`[WARNING] Threshold exceeded: ${processes.length} >= ${maxTerminals}`);
            vscode.window.showWarningMessage(`Hidden Terminal Watchdog: ${processes.length} hidden terminals detected!`);
        }
    }, interval);
}
```

### RULE 4: TESTING PROTOCOL (MANDATORY EXECUTION)

1. **Compile TypeScript**:
   ```bash
   cd hidden-terminal-watchdog
   npm install
   npm run compile
   ```

2. **Verify Compilation**:
   ```bash
   ls -la out/extension.js  # MUST exist
   ```

3. **Launch Extension Development Host**:
   - Open VS Code in the `hidden-terminal-watchdog` directory
   - Press F5
   - A new VS Code window opens (Extension Development Host)
   - Open Command Palette (Ctrl+Shift+P)
   - Run: "Hidden Terminal Watchdog: Show Status"
   - Check Output panel for logs

4. **Verify Logging**:
   ```bash
   tail -f ~/.hidden-terminal-watchdog.log
   ```

### RULE 5: SUCCESS CRITERIA (BINARY PASS/FAIL)

✅ PASS if:
- `npm run compile` succeeds
- `out/extension.js` exists
- F5 launches Extension Development Host
- Command "Hidden Terminal Watchdog: Show Status" appears in Command Palette
- Running the command shows output in Output panel
- Log file `~/.hidden-terminal-watchdog.log` is created and updated
- Console shows log messages

❌ FAIL if:
- Any compilation errors
- Extension doesn't activate
- Commands don't appear
- No output in Output panel
- No log file created

### RULE 6: FORBIDDEN ACTIONS

- ❌ DO NOT run `vsce package`
- ❌ DO NOT create `.vsix` files
- ❌ DO NOT troubleshoot packaging
- ❌ DO NOT ask "should I do X?"
- ❌ DO NOT explain what you COULD do
- ❌ DO NOT research alternatives
- ❌ DO NOT suggest using bash scripts instead

### RULE 7: EXECUTION ORDER (STRICT SEQUENCE)

1. Create `src/extension.ts` with ALL functions above
2. Run `npm run compile`
3. Verify `out/extension.js` exists
4. Test with F5
5. Report results with evidence (screenshots, log output, terminal output)

## DELIVERABLE

The ONLY acceptable deliverable is:
- Working extension code in `src/extension.ts`
- Successful compilation to `out/extension.js`
- Evidence of F5 testing showing the extension works

NO EXCUSES. NO ALTERNATIVES. NO DISCUSSIONS. EXECUTE.

