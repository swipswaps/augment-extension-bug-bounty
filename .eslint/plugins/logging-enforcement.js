/**
 * CUSTOM ESLINT PLUGIN: logging-enforcement
 *
 * PURPOSE:
 *  Bundle all custom logging rules into a single plugin
 *
 * WHY THIS EXISTS:
 *  - We had a critical bug: VLC black screen with no diagnostic output
 *  - Root cause: Missing stdout capture, conditional logging
 *  - This plugin prevents it from happening again
 *
 * HOW TO USE:
 *  1. Install this plugin in .eslintrc.js
 *  2. Enable the rules you want
 *  3. Run: npm run lint (or eslint .)
 *  4. Fix violations before committing
 *
 * RULES PROVIDED:
 *  - enforce-comprehensive-logging: Ensures spawn() calls capture and log all output
 *
 * EXAMPLE .eslintrc.js:
 *
 *  module.exports = {
 *    plugins: [
 *      require("./.eslint/plugins/logging-enforcement")
 *    ],
 *    rules: {
 *      "logging-enforcement/enforce-comprehensive-logging": "error"
 *    }
 *  };
 */

const enforceComprehensiveLogging = require("../rules/enforce-comprehensive-logging");

module.exports = {
  /**
   * PLUGIN METADATA
   *
   * This identifies the plugin to ESLint
   */
  meta: {
    name: "logging-enforcement",
    version: "1.0.0",
  },

  /**
   * RULES EXPORTED BY THIS PLUGIN
   *
   * Each rule is a separate file in .eslint/rules/
   * Add new rules here as you create them
   */
  rules: {
    "enforce-comprehensive-logging": enforceComprehensiveLogging,
  },
};

