# Logging Enforcement System

## Purpose

**Prevent the VLC black screen bug from ever happening again.**

### The Bug We're Preventing

**Symptom:** VLC launches successfully (exit code 0) but shows black screen  
**Root Cause:** Missing stdout capture and conditional logging  
**Impact:** Hours of debugging with no diagnostic information  

**What was wrong:**
```javascript
// ❌ BAD: Only captures stderr, stdout is lost forever
const proc = spawn("vlc", args, {
  stdio: ["ignore", "ignore", "pipe"]  // stdout ignored!
});

// ❌ BAD: Only logs stderr when exit code is non-zero
proc.on("exit", (code) => {
  if (code !== 0 && stderr) {
    console.error(stderr);  // Codec errors missed when code === 0!
  }
});
```

**Result:** VLC exits with code 0, but we have NO IDEA why the video is black.

---

## How It Works

### 1. Custom ESLint Rule

**File:** `.eslint/rules/enforce-comprehensive-logging.js`

**What it checks:**
- ✅ `spawn()` calls must capture BOTH stdout and stderr
- ✅ `spawn()` calls must log the command being executed
- ✅ `proc.stdout.on("data", ...)` handler must exist
- ✅ `proc.stderr.on("data", ...)` handler must exist
- ✅ `proc.on("exit", ...)` must log complete output (not just exit code)
- ✅ Exit handler must log output ALWAYS (not just when `code !== 0`)

**How it works:**
1. Scans AST (Abstract Syntax Tree) for `spawn()` calls
2. Checks `stdio` option: must be `["ignore", "pipe", "pipe"]`
3. Tracks variable name assigned to spawn result
4. Verifies `.stdout.on("data")` and `.stderr.on("data")` handlers exist
5. Verifies `.on("exit")` handler logs complete output
6. Reports violations with actionable error messages

### 2. Custom ESLint Plugin

**File:** `.eslint/plugins/logging-enforcement.js`

**What it does:**
- Bundles all custom logging rules into a single plugin
- Makes rules available as `logging-enforcement/*`
- Can be extended with more rules in the future

### 3. ESLint Configuration

**File:** `.eslintrc.js`

**What it does:**
- Loads the custom plugin
- Enables the `enforce-comprehensive-logging` rule as ERROR
- Configures standard ESLint rules
- Defines files to ignore (node_modules, dist, etc.)

---

## Usage

### Run the linter

```bash
# Check for violations (doesn't modify files)
npm run lint

# Auto-fix violations where possible
npm run lint:fix

# Check only logging violations
npm run lint:logging
```

### Example violations

**Violation 1: Missing stdout capture**
```javascript
// ❌ ERROR: spawn() must capture stdout
const proc = spawn("vlc", args, {
  stdio: ["ignore", "ignore", "pipe"]  // Only stderr captured
});
```

**Fix:**
```javascript
// ✅ CORRECT: Capture both stdout and stderr
const proc = spawn("vlc", args, {
  stdio: ["ignore", "pipe", "pipe"]  // Both streams captured
});
```

**Violation 2: Missing stdout handler**
```javascript
// ❌ ERROR: spawn() must have proc.stdout.on('data', ...) handler
const proc = spawn("vlc", args, { stdio: ["ignore", "pipe", "pipe"] });
// No stdout handler!
```

**Fix:**
```javascript
// ✅ CORRECT: Add stdout handler
const proc = spawn("vlc", args, { stdio: ["ignore", "pipe", "pipe"] });

let stdout = "";
proc.stdout.on("data", (data) => {
  stdout += data.toString();
  logBoth(id, `[stdout] ${data.toString().trim()}`);
});
```

**Violation 3: Conditional exit logging**
```javascript
// ❌ ERROR: Exit handler must log output ALWAYS, not just when code !== 0
proc.on("exit", (code) => {
  if (code !== 0 && stderr) {
    console.error(stderr);  // Misses codec errors when code === 0!
  }
});
```

**Fix:**
```javascript
// ✅ CORRECT: Log output regardless of exit code
proc.on("exit", (code) => {
  logBoth(id, `Exited with code ${code}`);
  if (stdout) logBoth(id, `Complete stdout:\n${stdout}`);
  if (stderr) logBoth(id, `Complete stderr:\n${stderr}`);
});
```

---

## Complete Example (Correct Code)

```javascript
/**
 * COMPREHENSIVE LOGGING PATTERN
 *
 * This is the CORRECT way to spawn a process with full logging
 */

// STEP 1: Log the command being executed
const fullCommand = `${playerCommand} ${playerArgs.join(" ")}`;
logBoth(id, `Executing: ${fullCommand}`);

// STEP 2: Spawn with BOTH stdout and stderr captured
const proc = spawn(playerCommand, playerArgs, {
  detached: true,
  stdio: ["ignore", "pipe", "pipe"]  // Both stdout and stderr
});

// STEP 3: Accumulate output for final summary
let stdout = "";
let stderr = "";

// STEP 4: Real-time stdout logging
proc.stdout.on("data", (data) => {
  const output = data.toString();
  stdout += output;
  logBoth(id, `[stdout] ${output.trim()}`);
});

// STEP 5: Real-time stderr logging
proc.stderr.on("data", (data) => {
  const output = data.toString();
  stderr += output;
  logBoth(id, `[stderr] ${output.trim()}`);
});

// STEP 6: Complete output summary on exit (ALWAYS, not just on error)
proc.on("exit", (code) => {
  logBoth(id, `Exited with code ${code}`);
  
  if (stdout && stdout.trim()) {
    logBoth(id, `Complete stdout:\n${stdout.trim()}`);
  } else {
    logBoth(id, `stdout was empty (no output)`);
  }
  
  if (stderr && stderr.trim()) {
    logBoth(id, `Complete stderr:\n${stderr.trim()}`);
  } else {
    logBoth(id, `stderr was empty (no errors)`);
  }
});
```

---

## Integration with CI/CD

### Pre-commit hook (recommended)

Add to `.git/hooks/pre-commit`:
```bash
#!/bin/bash
npm run lint
if [ $? -ne 0 ]; then
  echo "❌ Linting failed. Fix violations before committing."
  exit 1
fi
```

### GitHub Actions (recommended)

Add to `.github/workflows/lint.yml`:
```yaml
name: Lint
on: [push, pull_request]
jobs:
  lint:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-node@v3
      - run: npm install
      - run: npm run lint
```

---

## Future Enhancements

### Additional rules to consider

1. **enforce-logBoth-usage**: Ensure all logging uses `logBoth()` instead of `console.log()`
2. **enforce-error-logging**: Ensure all `try/catch` blocks log errors
3. **enforce-promise-error-handling**: Ensure all promises have `.catch()` handlers
4. **enforce-async-error-logging**: Ensure all `async` functions have try/catch

### Observability tools to integrate

1. **Structured logging**: Use JSON format for machine-readable logs
2. **Log aggregation**: Send logs to centralized system (e.g., Loki, Elasticsearch)
3. **Metrics**: Track spawn() success/failure rates
4. **Tracing**: Add correlation IDs to track requests across services

---

## References

- [ESLint Custom Rules Documentation](https://eslint.org/docs/latest/extend/custom-rules)
- [AST Explorer](https://astexplorer.net/) - Visualize JavaScript AST
- [ESLint Rule Tester](https://eslint.org/docs/latest/integrate/nodejs-api#ruletester) - Test custom rules

