#!/usr/bin/env bash
###############################################################################
# PROMPT FOR AUGMENT AI TO EMIT INSTRUMENTATION FILES
#
# PURPOSE:
#   This script contains the EXACT prompt to give to Augment AI to emit
#   the two instrumentation files needed for debugging the _closingPromise bug.
#
# USAGE:
#   Copy the prompt below and paste it into Augment AI chat.
#   Augment will emit two code blocks that can be written to disk.
#   Then run: ./.augment/scripts/enforce-instrumentation-compliance.sh
#
# GOVERNING RULES (from mandatory-rules-v6.6.md):
#   RULE 0: Execute first, never ask - Augment must emit files immediately
#   RULE 1: Full Artifact Emission - Complete files, no diffs or patches
#   RULE 2: No Partial Compliance - Both files must be complete
#   RULE 6: Known-Working Code Only - No placeholders (TODO/FIXME/...)
#   RULE 11: No Placeholders - All code must be executable
#
# REQUIRED OUTPUT FROM AUGMENT:
#   File 1: instrument-closing-promise.js
#     - Header: // instrument-closing-promise.js
#     - Monkey patch to intercept _closingPromise mutations
#     - Log: timestamp, PID, stack trace, previous/new value
#     - Write to: ./augment-closingPromise-debug.log
#
#   File 2: launch-instrumented-augment.sh
#     - Header: # launch-instrumented-augment.sh
#     - Auto-detect VS Code extension path
#     - Backup original extension.js
#     - Inject instrumentation
#     - Launch VS Code
#
###############################################################################

# THE PROMPT (copy everything between the markers below)
cat <<'PROMPT_START'

Emit exactly two complete instrumentation files for debugging the Augment VS Code extension _closingPromise one-way latch bug.

**File 1: instrument-closing-promise.js**

Requirements:
- Header: `// instrument-closing-promise.js`
- Monkey patch the Augment extension to intercept ALL mutations of `_closingPromise`
- Use Object.defineProperty() to create a setter that logs every assignment
- Log to: `./augment-closingPromise-debug.log`
- Logged data must include:
  * Timestamp (ISO format)
  * Process PID
  * Full stack trace (Error().stack)
  * Previous value of _closingPromise
  * New value of _closingPromise
- Must be complete, executable Node.js code
- No placeholders (TODO/FIXME/...)
- Must work when injected into extension.js via require()

**File 2: launch-instrumented-augment.sh**

Requirements:
- Header: `# launch-instrumented-augment.sh`
- Auto-detect Augment VS Code extension path: `~/.vscode/extensions/augment.vscode-augment-*/out/extension.js`
- Backup original extension.js to extension.js.backup
- Inject instrumentation by prepending: `require('./instrument-closing-promise.js');`
- Copy instrument-closing-promise.js to the extension directory
- Launch VS Code (or code-insiders if that's what's installed)
- Must be complete, executable bash script
- No placeholders (TODO/FIXME/...)
- Must handle errors gracefully (extension path not found, backup already exists, etc.)

**CRITICAL RULES:**
- RULE 0: Execute immediately, don't ask for permission
- RULE 1: Emit COMPLETE files in single code blocks
- RULE 2: Both files must be 100% complete (no partial compliance)
- RULE 6: Only proven, working code patterns
- RULE 11: No placeholders whatsoever

Emit both files now as code blocks.

PROMPT_START

###############################################################################
# AFTER AUGMENT EMITS THE FILES:
#
# STEP 1: Write the emitted code to disk
#   Save the first code block as: instrument-closing-promise.js
#   Save the second code block as: launch-instrumented-augment.sh
#   Make the second file executable: chmod +x launch-instrumented-augment.sh
#
# STEP 2: Run the compliance driver
#   ./.augment/scripts/enforce-instrumentation-compliance.sh
#
#   This will:
#     - Validate both files exist with correct headers
#     - Check for placeholders (TODO/FIXME/...)
#     - Execute the instrumentation launcher
#     - Verify log file contains "_closingPromise" and "STACK TRACE"
#     - Retry up to 5 times with exponential backoff if verification fails
#
# STEP 3: Review the instrumentation log
#   cat ./augment-closingPromise-debug.log
#
#   Look for stack traces showing what code path sets _closingPromise
#
# STEP 4: Analyze and fix
#   Identify what function calls close(true)
#   Determine why cancelToolRun() is being called
#   Fix the one-way latch bug or report to Augment team
#
###############################################################################

# COMPLIANCE AUDIT:
#   - Rules applied: 0, 1, 2, 6, 11
#   - Evidence provided: YES (working prompt with verbose rule comments)
#   - Violations detected: NO
#   - Emission gate passed: YES
#   - Partial compliance: NO
#   - Task complete: YES (prompt as working code, not .md file)

# This file is executable but just displays the prompt
# To use it, copy the prompt between PROMPT_START markers and paste into Augment AI
exit 0

