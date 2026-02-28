/**
 * ESLINT CONFIGURATION FOR FIREFOX PERFORMANCE TUNER
 *
 * PURPOSE:
 *  Enforce code quality and logging best practices
 *
 * CUSTOM RULES:
 *  - logging-enforcement/enforce-comprehensive-logging
 *    Prevents the VLC black screen bug from happening again
 *    Ensures all spawn() calls capture and log stdout/stderr
 *
 * HOW TO RUN:
 *  npm run lint              # Check for violations
 *  npm run lint:fix          # Auto-fix violations (where possible)
 *
 * WHAT GETS CHECKED:
 *  - All .js files in firefox-performance-tuner/
 *  - Excludes: node_modules, dist, build
 *
 * EXAMPLE VIOLATIONS:
 *
 *  ❌ spawn() without stdout capture
 *  ❌ spawn() without logging command
 *  ❌ spawn() without stdout/stderr handlers
 *  ❌ exit handler without logging complete output
 *  ❌ exit handler with conditional logging (code !== 0)
 *
 * EXAMPLE CORRECT CODE:
 *
 *  const fullCommand = `${cmd} ${args.join(" ")}`;
 *  logBoth(id, `Executing: ${fullCommand}`);
 *
 *  const proc = spawn(cmd, args, {
 *    stdio: ["ignore", "pipe", "pipe"]  // Both stdout and stderr
 *  });
 *
 *  let stdout = "", stderr = "";
 *
 *  proc.stdout.on("data", (data) => {
 *    stdout += data.toString();
 *    logBoth(id, `[stdout] ${data.toString().trim()}`);
 *  });
 *
 *  proc.stderr.on("data", (data) => {
 *    stderr += data.toString();
 *    logBoth(id, `[stderr] ${data.toString().trim()}`);
 *  });
 *
 *  proc.on("exit", (code) => {
 *    logBoth(id, `Exited with code ${code}`);
 *    if (stdout) logBoth(id, `Complete stdout:\n${stdout}`);
 *    if (stderr) logBoth(id, `Complete stderr:\n${stderr}`);
 *  });
 */

module.exports = {
  /**
   * ENVIRONMENT CONFIGURATION
   *
   * Tells ESLint what global variables are available
   */
  env: {
    node: true,      // Node.js globals (process, __dirname, etc.)
    es2022: true,    // Modern JavaScript features
  },

  /**
   * PARSER OPTIONS
   *
   * Tells ESLint what JavaScript syntax to support
   */
  parserOptions: {
    ecmaVersion: 2022,  // Support modern syntax
    sourceType: "module", // Support ES modules (import/export)
  },

  /**
   * CUSTOM PLUGINS
   *
   * Load our custom logging enforcement plugin
   */
  plugins: [
    // Load the custom plugin from .eslint/plugins/
    // This makes the "logging-enforcement/*" rules available
    {
      name: "logging-enforcement",
      definition: require("./.eslint/plugins/logging-enforcement"),
    },
  ],

  /**
   * RULES CONFIGURATION
   *
   * "error" = Fail the build (exit code 1)
   * "warn"  = Show warning but don't fail
   * "off"   = Disable the rule
   */
  rules: {
    /**
     * CUSTOM LOGGING RULES (CRITICAL)
     *
     * These prevent the VLC black screen bug from happening again
     */
    "logging-enforcement/enforce-comprehensive-logging": "error",

    /**
     * STANDARD ESLINT RULES (RECOMMENDED)
     *
     * These catch common JavaScript errors
     */
    "no-unused-vars": ["warn", { argsIgnorePattern: "^_" }],  // Warn on unused variables
    "no-console": "off",  // Allow console.log (we use it for logging)
    "no-undef": "error",  // Error on undefined variables
    "semi": ["error", "always"],  // Require semicolons
    "quotes": ["warn", "double"],  // Prefer double quotes
  },

  /**
   * FILES TO IGNORE
   *
   * Don't lint these directories
   */
  ignorePatterns: [
    "node_modules/",
    "dist/",
    "build/",
    ".notes/",
    ".augment/",
  ],
};

