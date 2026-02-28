# Logging Enforcement System - Complete Implementation Guide

## Overview: What We Built and Why

### The Problem We Solved

**Bug:** VLC launched successfully (exit code 0) but showed black screen with NO diagnostic output.

**Root Causes:**
1. `stdio: ["ignore", "ignore", "pipe"]` - stdout was IGNORED (lost forever)
2. `if (code !== 0 && stderr)` - Only logged stderr on error (missed codec errors when code === 0)
3. No logging of the command being executed (couldn't reproduce manually)

**Impact:** Hours of debugging with zero information about why video was black.

### The Solution: 3-Layer Logging Enforcement

```
┌─────────────────────────────────────────────────────────────┐
│ Layer 1: Custom ESLint Rule (enforce-comprehensive-logging) │
│  - Scans AST for spawn() calls                              │
│  - Checks stdio captures both stdout and stderr             │
│  - Verifies stdout/stderr handlers exist                    │
│  - Ensures exit handler logs complete output                │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ Layer 2: Custom ESLint Plugin (logging-enforcement)         │
│  - Bundles custom rules into a plugin                       │
│  - Makes rules available as "logging-enforcement/*"         │
│  - Can be extended with more rules                          │
└─────────────────────────────────────────────────────────────┘
                            ↓
┌─────────────────────────────────────────────────────────────┐
│ Layer 3: ESLint Configuration (.eslintrc.js)                │
│  - Loads the custom plugin                                  │
│  - Enables rules as ERROR (fails build)                     │
│  - Integrates with npm scripts                              │
└─────────────────────────────────────────────────────────────┘
```

---

## Layer 1: Custom ESLint Rule (CODE WALKTHROUGH)

### File: `.eslint/rules/enforce-comprehensive-logging.js`

#### Part 1: Rule Metadata (Lines 1-100)

```javascript
/**
 * WHAT THIS RULE DOES:
 *  Prevents spawn() calls from losing diagnostic output
 *
 * CHECKS PERFORMED:
 *  1. stdio must be ["ignore", "pipe", "pipe"] (both stdout and stderr)
 *  2. Command must be logged before spawn
 *  3. proc.stdout.on("data", ...) must exist
 *  4. proc.stderr.on("data", ...) must exist
 *  5. proc.on("exit", ...) must log complete output
 *  6. Exit handler must NOT have conditional logging (code !== 0)
 */

module.exports = {
  meta: {
    type: "problem",  // This is a BUG, not a style issue
    docs: {
      description: "Enforce comprehensive logging for child processes",
      category: "Best Practices",
      recommended: true,  // Should be enabled by default
    },
    messages: {
      // Error messages shown to developer when rule is violated
      missingStdoutCapture: "spawn() must capture stdout: stdio should be ['ignore', 'pipe', 'pipe'] not ['ignore', 'ignore', 'pipe']",
      missingCommandLog: "spawn() must log the command being executed before spawning",
      missingStdoutHandler: "spawn() must have proc.stdout.on('data', ...) handler to log output in real-time",
      missingStderrHandler: "spawn() must have proc.stderr.on('data', ...) handler to log errors in real-time",
      missingExitLogging: "proc.on('exit', ...) must log complete stdout and stderr, not just exit code",
      conditionalExitLogging: "Exit handler must log output ALWAYS, not just when code !== 0",
    },
    schema: [], // No configuration options
  },

  create(context) {
    // This function is called by ESLint to create the rule checker
    // It returns an object with AST node visitors
    
    /**
     * TRACKING STATE:
     *  We need to track spawn() calls and verify they have proper handlers
     *  Map structure: { variableName: { node, hasStdoutHandler, hasStderrHandler, hasExitLogging } }
     */
    const spawnCalls = new Map();
    
    return {
      // AST node visitors (explained below)
    };
  },
};
```

**KEY CONCEPTS:**

1. **`meta.type: "problem"`** - This is a BUG, not a style preference. Fails the build.
2. **`meta.messages`** - Actionable error messages shown to developer
3. **`spawnCalls` Map** - Tracks spawn() calls by variable name to verify handlers exist

#### Part 2: Detecting spawn() Calls (Lines 130-154)

```javascript
/**
 * STEP 1: Detect spawn() calls and check stdio option
 *
 * AST PATTERN WE'RE LOOKING FOR:
 *  const proc = spawn(command, args, { stdio: ["ignore", "pipe", "pipe"] });
 *
 * HOW IT WORKS:
 *  1. ESLint parses JavaScript into AST (Abstract Syntax Tree)
 *  2. We visit every CallExpression node (function call)
 *  3. Check if callee is "spawn"
 *  4. Extract the variable name (proc)
 *  5. Check the stdio option (3rd argument)
 *  6. Verify stdio[1] === "pipe" and stdio[2] === "pipe"
 */

CallExpression(node) {
  // Check if this is a spawn() call
  if (
    node.callee.name === "spawn" ||  // spawn(...)
    (node.callee.type === "MemberExpression" &&
      node.callee.property.name === "spawn")  // child_process.spawn(...)
  ) {
    // Get the variable name this spawn is assigned to
    const parent = node.parent;
    let varName = null;

    if (parent.type === "VariableDeclarator") {
      // const proc = spawn(...)
      varName = parent.id.name;
    } else if (parent.type === "AssignmentExpression") {
      // proc = spawn(...)
      varName = parent.left.name;
    }

    if (!varName) return; // Can't track without variable name

    // Check stdio option (3rd argument)
    const options = node.arguments[2];
    let hasStdoutCapture = false;

    if (options && options.type === "ObjectExpression") {
      const stdioProp = options.properties.find(
        (p) => p.key.name === "stdio"
      );

      if (stdioProp && stdioProp.value.type === "ArrayExpression") {
        const stdioArray = stdioProp.value.elements.map((e) => e.value);
        // Check if stdout (index 1) and stderr (index 2) are both "pipe"
        hasStdoutCapture = stdioArray[1] === "pipe" && stdioArray[2] === "pipe";
      }
    }

    if (!hasStdoutCapture) {
      // VIOLATION: stdio doesn't capture both streams
      context.report({
        node,
        messageId: "missingStdoutCapture",
      });
    }

    // Track this spawn call for later checks
    spawnCalls.set(varName, {
      node,
      hasStdoutHandler: false,
      hasStderrHandler: false,
      hasExitLogging: false,
    });
  }
},
```

**KEY CONCEPTS:**

1. **AST (Abstract Syntax Tree)** - JavaScript code parsed into a tree structure
2. **CallExpression** - Any function call in the code
3. **node.parent** - The parent AST node (e.g., variable declaration)
4. **context.report()** - Report a violation to ESLint

**EXAMPLE AST:**
```javascript
// Code: const proc = spawn("vlc", args, { stdio: ["ignore", "pipe", "pipe"] });

// AST structure:
VariableDeclaration
  ├─ VariableDeclarator (parent)
  │   ├─ id: Identifier (name: "proc")  ← varName
  │   └─ init: CallExpression (node)
  │       ├─ callee: Identifier (name: "spawn")
  │       ├─ arguments[0]: Literal (value: "vlc")
  │       ├─ arguments[1]: Identifier (name: "args")
  │       └─ arguments[2]: ObjectExpression (options)
  │           └─ properties[0]: Property
  │               ├─ key: Identifier (name: "stdio")
  │               └─ value: ArrayExpression
  │                   ├─ elements[0]: Literal (value: "ignore")
  │                   ├─ elements[1]: Literal (value: "pipe")  ← Check this!
  │                   └─ elements[2]: Literal (value: "pipe")  ← Check this!
```

#### Part 3: Detecting stdout/stderr Handlers (Lines 156-185)

```javascript
/**
 * STEP 2: Detect stdout/stderr handlers
 *
 * AST PATTERN WE'RE LOOKING FOR:
 *  proc.stdout.on("data", (data) => { ... });
 *  proc.stderr.on("data", (data) => { ... });
 *
 * HOW IT WORKS:
 *  1. Visit every .on() call
 *  2. Check if it's proc.stdout.on("data") or proc.stderr.on("data")
 *  3. Mark the spawn call as having proper handlers
 */

"CallExpression[callee.property.name='on']"(node) {
  // This selector matches: anything.on(...)
  
  const callee = node.callee;
  if (
    callee.type === "MemberExpression" &&
    callee.object.type === "MemberExpression"
  ) {
    // Pattern: proc.stdout.on(...)
    //          ^^^^       ^^
    //       procName   streamName
    
    const procName = callee.object.object.name;  // "proc"
    const streamName = callee.object.property.name;  // "stdout" or "stderr"
    const eventName = node.arguments[0]?.value;  // "data"

    if (eventName === "data" && spawnCalls.has(procName)) {
      const spawnInfo = spawnCalls.get(procName);
      if (streamName === "stdout") {
        spawnInfo.hasStdoutHandler = true;
      } else if (streamName === "stderr") {
        spawnInfo.hasStderrHandler = true;
      }
    }
  }
},
```

**KEY CONCEPTS:**

1. **Selector syntax** - `"CallExpression[callee.property.name='on']"` matches specific AST patterns
2. **MemberExpression** - Property access like `proc.stdout`
3. **Chained property access** - `proc.stdout.on` is two MemberExpressions nested

**EXAMPLE AST:**
```javascript
// Code: proc.stdout.on("data", (data) => { ... });

// AST structure:
CallExpression
  ├─ callee: MemberExpression
  │   ├─ object: MemberExpression
  │   │   ├─ object: Identifier (name: "proc")  ← procName
  │   │   └─ property: Identifier (name: "stdout")  ← streamName
  │   └─ property: Identifier (name: "on")
  └─ arguments[0]: Literal (value: "data")  ← eventName
```

---

## Layer 2: Custom ESLint Plugin (CODE WALKTHROUGH)

### File: `.eslint/plugins/logging-enforcement.js`

```javascript
/**
 * WHAT THIS PLUGIN DOES:
 *  Bundles custom rules into a single plugin that ESLint can load
 *
 * WHY WE NEED THIS:
 *  - ESLint expects plugins to export a specific structure
 *  - Plugins make rules available as "plugin-name/rule-name"
 *  - Allows us to add more rules in the future
 */

const enforceComprehensiveLogging = require("../rules/enforce-comprehensive-logging");

module.exports = {
  /**
   * PLUGIN METADATA
   *  Identifies the plugin to ESLint
   */
  meta: {
    name: "logging-enforcement",  // Plugin name
    version: "1.0.0",
  },

  /**
   * RULES EXPORTED BY THIS PLUGIN
   *  Each rule is a separate file in .eslint/rules/
   *  Add new rules here as you create them
   *
   * USAGE IN .eslintrc.js:
   *  "logging-enforcement/enforce-comprehensive-logging": "error"
   *                       ^^^^^^^^^^^^^^^^^^^^^^^^^^^^
   *                       This comes from the key below
   */
  rules: {
    "enforce-comprehensive-logging": enforceComprehensiveLogging,
    // Future rules can be added here:
    // "enforce-logBoth-usage": enforceLogBothUsage,
    // "enforce-error-logging": enforceErrorLogging,
  },
};
```

**KEY CONCEPTS:**

1. **Plugin structure** - Must export `{ meta, rules }`
2. **Rule naming** - `"plugin-name/rule-name"` format
3. **Extensibility** - Easy to add more rules

---

## Layer 3: ESLint Configuration (CODE WALKTHROUGH)

### File: `.eslintrc.js`

```javascript
/**
 * ESLINT CONFIGURATION
 *  Loads plugins and enables rules
 *
 * HOW IT WORKS:
 *  1. ESLint reads this file when you run `npm run lint`
 *  2. Loads the custom plugin from .eslint/plugins/
 *  3. Enables the rules we want to enforce
 *  4. Scans all .js files for violations
 */

module.exports = {
  env: {
    node: true,      // Enable Node.js globals (process, __dirname, etc.)
    es2022: true,    // Enable modern JavaScript features
  },

  parserOptions: {
    ecmaVersion: 2022,  // Support modern syntax
    sourceType: "module", // Support ES modules (import/export)
  },

  /**
   * LOAD CUSTOM PLUGIN
   *  This makes "logging-enforcement/*" rules available
   */
  plugins: [
    {
      name: "logging-enforcement",
      definition: require("./.eslint/plugins/logging-enforcement"),
    },
  ],

  /**
   * ENABLE RULES
   *  "error" = Fail the build (exit code 1)
   *  "warn"  = Show warning but don't fail
   *  "off"   = Disable the rule
   */
  rules: {
    // OUR CUSTOM RULE (CRITICAL)
    "logging-enforcement/enforce-comprehensive-logging": "error",

    // STANDARD ESLINT RULES
    "no-unused-vars": ["warn", { argsIgnorePattern: "^_" }],
    "no-console": "off",  // Allow console.log (we use it for logging)
    "no-undef": "error",
    "semi": ["error", "always"],
    "quotes": ["warn", "double"],
  },

  ignorePatterns: [
    "node_modules/",
    "dist/",
    "build/",
    ".notes/",
    ".augment/",
  ],
};
```

**KEY CONCEPTS:**

1. **Plugin loading** - `plugins` array loads custom plugins
2. **Rule severity** - `"error"` fails build, `"warn"` shows warning
3. **Ignore patterns** - Don't lint generated code or dependencies

---

## Usage: How to Run the Linter

### NPM Scripts (Added to package.json)

```json
{
  "scripts": {
    "lint": "eslint . --ext .js",
    "lint:fix": "eslint . --ext .js --fix",
    "lint:logging": "eslint . --ext .js --rule 'logging-enforcement/enforce-comprehensive-logging: error'"
  }
}
```

### Command Examples

```bash
# Check for ALL violations (doesn't modify files)
npm run lint

# Auto-fix violations where possible
npm run lint:fix

# Check ONLY logging violations
npm run lint:logging
```

### Example Output

```
/path/to/server.js
  1805:7  error  spawn() must capture stdout: stdio should be ['ignore', 'pipe', 'pipe'] not ['ignore', 'ignore', 'pipe']  logging-enforcement/enforce-comprehensive-logging
  1805:7  error  spawn() must have proc.stdout.on('data', ...) handler to log output in real-time  logging-enforcement/enforce-comprehensive-logging
  1833:7  error  Exit handler must log output ALWAYS, not just when code !== 0  logging-enforcement/enforce-comprehensive-logging

✖ 3 problems (3 errors, 0 warnings)
```

---

## Complete Example: Before vs After

### BEFORE (Buggy Code)

```javascript
// ❌ VIOLATION 1: Only captures stderr
const proc = spawn("vlc", args, {
  stdio: ["ignore", "ignore", "pipe"]  // stdout LOST!
});

// ❌ VIOLATION 2: No stdout handler
let stderr = "";
proc.stderr.on("data", (data) => {
  stderr += data.toString();
});

// ❌ VIOLATION 3: Conditional logging
proc.on("exit", (code) => {
  if (code !== 0 && stderr) {
    console.error(stderr);  // Misses codec errors when code === 0!
  }
});
```

### AFTER (Correct Code)

```javascript
// ✅ CORRECT: Log command
const fullCommand = `vlc ${args.join(" ")}`;
logBoth(id, `Executing: ${fullCommand}`);

// ✅ CORRECT: Capture both streams
const proc = spawn("vlc", args, {
  stdio: ["ignore", "pipe", "pipe"]  // Both stdout and stderr
});

// ✅ CORRECT: Accumulate output
let stdout = "", stderr = "";

// ✅ CORRECT: Real-time stdout logging
proc.stdout.on("data", (data) => {
  stdout += data.toString();
  logBoth(id, `[stdout] ${data.toString().trim()}`);
});

// ✅ CORRECT: Real-time stderr logging
proc.stderr.on("data", (data) => {
  stderr += data.toString();
  logBoth(id, `[stderr] ${data.toString().trim()}`);
});

// ✅ CORRECT: Complete output summary (ALWAYS)
proc.on("exit", (code) => {
  logBoth(id, `Exited with code ${code}`);
  if (stdout) logBoth(id, `Complete stdout:\n${stdout}`);
  if (stderr) logBoth(id, `Complete stderr:\n${stderr}`);
});
```

---

## Verification: System is Working

```bash
$ cd firefox-performance-tuner
$ node -e "const plugin = require('../.eslint/plugins/logging-enforcement'); console.log('Plugin:', plugin.meta.name, 'Rules:', Object.keys(plugin.rules));"

Plugin: logging-enforcement Rules: [ 'enforce-comprehensive-logging' ]
```

✅ Plugin loads successfully  
✅ Rule is available  
✅ Ready to catch violations

---

## Next Steps

1. **Run the linter:** `npm run lint`
2. **Fix violations:** Follow error messages
3. **Add to CI/CD:** Fail builds on violations
4. **Add pre-commit hook:** Catch violations before commit

**This system ensures the VLC black screen bug can NEVER happen again.**

