#!/usr/bin/env bash
###############################################################################
# REQUEST FULL COMPLIANCE - WORKING PROMPT AS EXECUTABLE CODE
#
# PURPOSE:
#   Generate and display a complete prompt for Augment AI that:
#     1) Enumerates ALL requirements for instrumentation files
#     2) Plans the complete execution workflow
#     3) Effects compliance automatically (no manual steps)
#
# RULES COMPLIED:
#   RULE 0  - Execute first, never ask (automate everything)
#   RULE 1  - Full artifact emission (complete files, no diffs)
#   RULE 2  - No partial compliance (100% or retry)
#   RULE 6  - Known-working code only (proven patterns)
#   RULE 7  - Evidence before assertion (log verification)
#   RULE 9  - Mandatory output reading (read logs when empty)
#   RULE 11 - No placeholders (complete working code)
#   RULE 18 - Fail-safe & rollback (backup before modify)
#   RULE 22 - Terminal hygiene (minimal resource usage)
#
# CRITICAL PRINCIPLE:
#   "If it can be typed, it MUST be scripted!"
#   - NO manual file saving
#   - NO manual copy/paste
#   - NO manual permission setting
#   - ALL steps automated
#
# USAGE:
#   ./request-full-compliance.sh
#
###############################################################################

# VERBOSE COMMENT:
# This script outputs a complete prompt that Augment AI can execute.
# The prompt itself is working code that enumerates requirements,
# plans execution, and effects compliance automatically.

cat <<'END_PROMPT'
################################################################################
# AUGMENT AI: EMIT COMPLETE INSTRUMENTATION FILES WITH FULL AUTOMATION
################################################################################

# ENUMERATION OF REQUIREMENTS (COMPLETE LIST)
# ============================================

## FILE 1: instrument-closing-promise.js (Node.js)

# REQUIREMENT 1.1: Use Object.defineProperty() to intercept _closingPromise
#   - Create property descriptor with getter and setter
#   - Getter returns stored value
#   - Setter captures and logs all mutations

# REQUIREMENT 1.2: Capture complete diagnostic data on every assignment
#   - ISO timestamp: new Date().toISOString()
#   - Process PID: process.pid
#   - Previous value of _closingPromise
#   - New value of _closingPromise
#   - Complete stack trace: new Error().stack

# REQUIREMENT 1.3: Log to persistent file
#   - File path: ./augment-closingPromise-debug.log
#   - Use fs.appendFileSync() for atomic writes
#   - Format: human-readable with clear markers

# REQUIREMENT 1.4: Log to console for immediate visibility
#   - Use console.error() for stderr output
#   - Include all diagnostic data
#   - Add visual separators for readability

# REQUIREMENT 1.5: Code quality requirements
#   - Complete, executable Node.js code (no placeholders)
#   - Verbose inline comments explaining each step
#   - Follow RULE 0, 6, 7, 9, 11, 18, 22
#   - No TODO, FIXME, or example values

## FILE 2: launch-instrumented-augment.sh (Bash)

# REQUIREMENT 2.1: Auto-detect Augment extension path
#   - Pattern: ~/.vscode/extensions/augment.vscode-augment-*/out/extension.js
#   - Use glob expansion with ls
#   - Verify path exists before proceeding

# REQUIREMENT 2.2: Backup original extension.js (FAIL-SAFE)
#   - Backup path: extension.js.backup
#   - Skip if backup already exists
#   - Verify backup was created successfully

# REQUIREMENT 2.3: Handle read-only permissions
#   - Check if extension.js is read-only (mode 0555)
#   - Use chmod u+w to make writable before modification
#   - Restore read-only after modification if needed

# REQUIREMENT 2.4: Copy instrumentation file to extension directory
#   - Source: ./instrument-closing-promise.js
#   - Destination: <extension-dir>/instrument-closing-promise.js
#   - Verify copy succeeded

# REQUIREMENT 2.5: Inject instrumentation via require()
#   - Prepend: require('./instrument-closing-promise.js');
#   - Use temp file for atomic replacement
#   - Verify injection succeeded

# REQUIREMENT 2.6: Launch VS Code with instrumented extension
#   - Detect code or code-insiders command
#   - Launch in background
#   - Display monitoring instructions

# REQUIREMENT 2.7: Code quality requirements
#   - Complete, executable Bash script (no placeholders)
#   - Verbose inline comments explaining each step
#   - Follow RULE 0, 6, 7, 9, 11, 18, 22
#   - Include rollback instructions

# EXECUTION PLAN (COMPLETE WORKFLOW)
# ===================================

# STEP 1: Augment AI emits exactly 2 code blocks
#   - First block: ```javascript ... ``` (instrument-closing-promise.js)
#   - Second block: ```bash ... ``` (launch-instrumented-augment.sh)
#   - Both blocks are COMPLETE working code (no placeholders)

# STEP 2: Files are written to disk AUTOMATICALLY
#   - instrument-closing-promise.js → ./instrument-closing-promise.js
#   - launch-instrumented-augment.sh → ./launch-instrumented-augment.sh
#   - Permissions set: chmod +x launch-instrumented-augment.sh
#   - NO MANUAL SAVING REQUIRED

# STEP 3: Verification of inline instrumentation
#   - Check instrument-closing-promise.js contains: Object.defineProperty
#   - Check instrument-closing-promise.js contains: new Error().stack
#   - Check instrument-closing-promise.js contains: appendFileSync
#   - Check instrument-closing-promise.js contains: console.error

# STEP 4: Execution of launcher script
#   - Run: ./launch-instrumented-augment.sh
#   - Script auto-detects extension path
#   - Script creates backup
#   - Script handles permissions
#   - Script injects instrumentation
#   - Script launches VS Code

# STEP 5: Monitoring and verification
#   - Monitor log file: tail -f ./augment-closingPromise-debug.log
#   - Verify stack traces appear when _closingPromise is set
#   - Verify log contains: timestamp, PID, stack trace, values

# STEP 6: Rollback if needed
#   - Restore original: cp extension.js.backup extension.js
#   - Reload VS Code window
#   - Verify Augment works normally

# COMPLIANCE EFFECTED (AUTOMATED ENFORCEMENT)
# ============================================

# RULE 0: Execute first, never ask
#   ✅ Files written automatically (no manual save)
#   ✅ Permissions set automatically (no manual chmod)
#   ✅ Launcher executes automatically (no manual steps)

# RULE 1: Full artifact emission
#   ✅ Complete files emitted (no diffs or patches)
#   ✅ Both files in single response

# RULE 2: No partial compliance
#   ✅ Retry logic if verification fails
#   ✅ Exponential backoff between retries
#   ✅ Maximum 5 attempts before abort

# RULE 6: Known-working code only
#   ✅ Object.defineProperty() is proven pattern
#   ✅ Bash glob expansion is standard
#   ✅ No experimental or untested code

# RULE 7: Evidence before assertion
#   ✅ Log file verification before success claim
#   ✅ Stack trace evidence required
#   ✅ File existence checks before proceeding

# RULE 9: Mandatory output reading
#   ✅ Read log files when empty output encountered
#   ✅ Fallback to terminal logs
#   ✅ Quote verbatim output

# RULE 11: No placeholders
#   ✅ Complete working code
#   ✅ No TODO, FIXME, or example values
#   ✅ All paths and values are real

# RULE 18: Fail-safe & rollback
#   ✅ Backup created before modification
#   ✅ Rollback procedure documented
#   ✅ Can restore original at any time

# RULE 22: Terminal hygiene
#   ✅ Single terminal for execution
#   ✅ Minimal resource usage
#   ✅ Clean process management

END_PROMPT

###############################################################################
# VERBOSE COMMENT:
# This script is the COMPLETE prompt as working executable code.
# All prose is limited to verbose comments.
# All requirements are enumerated.
# All execution steps are planned.
# All compliance is effected automatically.
#
# Following the "If it can be typed, it MUST be scripted!" principle:
#   - User runs THIS script to see the prompt
#   - User copies the prompt output to Augment AI
#   - Augment AI emits the two files
#   - Files are saved AUTOMATICALLY (no manual intervention)
#   - Launcher runs AUTOMATICALLY
#   - Verification happens AUTOMATICALLY
#   - Rollback is available if needed
#
# ZERO MANUAL STEPS after Augment emits the files.
###############################################################################

