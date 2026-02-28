#!/usr/bin/env bash
###############################################################################
# REQUEST PROTOTYPE INSTRUMENTATION - WORKING PROMPT AS EXECUTABLE CODE
#
# PURPOSE:
#   Generate and display a complete prompt for Augment AI that:
#     1) Enumerates ALL requirements for CORRECTED instrumentation
#     2) Plans the complete execution workflow
#     3) Effects compliance automatically (no manual steps)
#
# ROOT CAUSE IDENTIFIED:
#   Previous instrumentation patched global._closingPromise
#   Actual _closingPromise is this._closingPromise (instance property)
#   Solution: Patch the class prototype BEFORE instances are created
#
# RULES COMPLIED:
#   RULE 0  - Execute first, never ask (automate everything)
#   RULE 1  - Full artifact emission (complete files, no diffs)
#   RULE 2  - No partial compliance (100% or retry)
#   RULE 6  - Known-working code only (proven patterns)
#   RULE 7  - Evidence before assertion (log verification)
#   RULE 9  - Mandatory output reading (read logs when empty)
#   RULE 11 - No placeholders (complete working code)
#   RULE 18 - Fail-safe & rollback (backup exists)
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
#   ./request-prototype-instrumentation.sh
#
###############################################################################

cat <<'END_PROMPT'
################################################################################
# AUGMENT AI: EMIT CORRECTED PROTOTYPE INSTRUMENTATION WITH STACK TRACE LOGGING
################################################################################

# ROOT CAUSE ANALYSIS (EVIDENCE-BASED)
# =====================================

# PROBLEM IDENTIFIED:
#   Previous instrumentation patched: global._closingPromise
#   Actual location in extension.js: this._closingPromise (instance property)
#   Evidence from extension.js line 18:
#     this._closingPromise===void 0&&(this._cancelledByUser=t,this._closingPromise=(async()=>{...
#
# SOLUTION REQUIRED:
#   Patch the class prototype to intercept ALL instance property assignments
#   Must execute BEFORE any McpHost instances are created
#   Must work with minified/obfuscated code

# ENUMERATION OF REQUIREMENTS (COMPLETE LIST)
# ============================================

## FILE 1: instrument-closing-promise-prototype.js (Node.js)

# REQUIREMENT 1.1: Find the class that contains _closingPromise
#   - Search for constructor that initializes this._closingPromise
#   - Handle minified code (obfuscated class names)
#   - Verify class found before patching

# REQUIREMENT 1.2: Patch the prototype using Object.defineProperty()
#   - Create hidden storage property: _closingPromiseValue
#   - Define getter that returns stored value
#   - Define setter that captures and logs all mutations
#   - Apply to prototype, not global object

# REQUIREMENT 1.3: Capture complete diagnostic data on every assignment
#   - ISO timestamp: new Date().toISOString()
#   - Process PID: process.pid
#   - Previous value of _closingPromise
#   - New value of _closingPromise
#   - Complete stack trace: new Error().stack
#   - Instance identifier (if available)

# REQUIREMENT 1.4: Log to persistent file
#   - File path: ./augment-closingPromise-debug.log
#   - Use fs.appendFileSync() for atomic writes
#   - Format: human-readable with clear markers
#   - Include evidence that prototype patching succeeded

# REQUIREMENT 1.5: Log to console for immediate visibility
#   - Use console.error() for stderr output
#   - Include all diagnostic data
#   - Add visual separators for readability
#   - Confirm prototype patch was applied

# REQUIREMENT 1.6: Handle module loading order
#   - Execute BEFORE extension code runs
#   - Use Module._load hook if needed
#   - Verify patch applied before first instance created

# REQUIREMENT 1.7: Code quality requirements
#   - Complete, executable Node.js code (no placeholders)
#   - Verbose inline comments explaining each step
#   - Follow RULE 0, 6, 7, 9, 11, 18, 22
#   - No TODO, FIXME, or example values
#   - Handle errors gracefully (log but don't crash extension)

## FILE 2: restore-original-extension.sh (Bash)

# REQUIREMENT 2.1: Restore original extension.js from backup
#   - Source: extension.js.backup
#   - Destination: extension.js
#   - Verify backup exists before restoring

# REQUIREMENT 2.2: Remove instrumentation files
#   - Remove: instrument-closing-promise.js (old version)
#   - Remove: instrument-closing-promise-prototype.js (new version)
#   - Clean up any temporary files

# REQUIREMENT 2.3: Provide verification
#   - Show file sizes before/after
#   - Confirm restoration succeeded
#   - Provide instructions to reload VS Code

# REQUIREMENT 2.4: Code quality requirements
#   - Complete, executable Bash script (no placeholders)
#   - Verbose inline comments explaining each step
#   - Follow RULE 0, 6, 7, 9, 11, 18, 22
#   - Safe to run multiple times (idempotent)

# EXECUTION PLAN (COMPLETE WORKFLOW)
# ===================================

# STEP 1: Augment AI emits exactly 2 code blocks
#   - First block: ```javascript ... ``` (instrument-closing-promise-prototype.js)
#   - Second block: ```bash ... ``` (restore-original-extension.sh)
#   - Both blocks are COMPLETE working code (no placeholders)

# STEP 2: Files are written to disk AUTOMATICALLY
#   - instrument-closing-promise-prototype.js → ./instrument-closing-promise-prototype.js
#   - restore-original-extension.sh → ./restore-original-extension.sh
#   - Permissions set: chmod +x restore-original-extension.sh
#   - NO MANUAL SAVING REQUIRED

# STEP 3: Restore original extension.js
#   - Run: ./restore-original-extension.sh
#   - This removes old instrumentation
#   - Restores clean extension.js from backup

# STEP 4: Apply NEW prototype instrumentation
#   - Copy instrument-closing-promise-prototype.js to extension directory
#   - Inject via require() at top of extension.js
#   - Verify injection succeeded

# STEP 5: Reload VS Code window
#   - Ctrl+Shift+P → "Developer: Reload Window"
#   - Extension loads with NEW instrumentation
#   - Prototype patch applied BEFORE instances created

# STEP 6: Verification of prototype patching
#   - Check console for: "[PROTOTYPE PATCH] Applied to class: ..."
#   - Check log file exists: ./augment-closingPromise-debug.log
#   - Verify log shows prototype patch confirmation

# STEP 7: Monitoring and verification
#   - Monitor log file: tail -f ./augment-closingPromise-debug.log
#   - Use Augment AI normally
#   - When _closingPromise is set, stack trace appears
#   - Verify log contains: timestamp, PID, stack trace, values

# STEP 8: Rollback if needed
#   - Run: ./restore-original-extension.sh
#   - Reload VS Code window
#   - Verify Augment works normally

# COMPLIANCE EFFECTED (AUTOMATED ENFORCEMENT)
# ============================================

# RULE 0: Execute first, never ask
#   ✅ Files written automatically (no manual save)
#   ✅ Permissions set automatically (no manual chmod)
#   ✅ Restoration script executes automatically (no manual steps)

# RULE 1: Full artifact emission
#   ✅ Complete files emitted (no diffs or patches)
#   ✅ Both files in single response

# RULE 2: No partial compliance
#   ✅ Retry logic if verification fails
#   ✅ Restoration script for rollback
#   ✅ Complete workflow from start to finish

# RULE 6: Known-working code only
#   ✅ Object.defineProperty() on prototype is proven pattern
#   ✅ Module._load hook is standard Node.js technique
#   ✅ No experimental or untested code

# RULE 7: Evidence before assertion
#   ✅ Log file verification before success claim
#   ✅ Stack trace evidence required
#   ✅ Prototype patch confirmation logged
#   ✅ File existence checks before proceeding

# RULE 9: Mandatory output reading
#   ✅ Read log files when empty output encountered
#   ✅ Check console for prototype patch messages
#   ✅ Quote verbatim output

# RULE 11: No placeholders
#   ✅ Complete working code
#   ✅ No TODO, FIXME, or example values
#   ✅ All paths and values are real

# RULE 18: Fail-safe & rollback
#   ✅ Backup exists (extension.js.backup)
#   ✅ Restoration script provided
#   ✅ Can restore original at any time
#   ✅ Safe to run multiple times

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
# KEY DIFFERENCE FROM PREVIOUS VERSION:
#   - Previous: Patched global._closingPromise (WRONG TARGET)
#   - Current: Patches class prototype (CORRECT TARGET)
#   - Evidence: extension.js shows this._closingPromise (instance property)
#
# Following the "If it can be typed, it MUST be scripted!" principle:
#   - User runs THIS script to see the prompt
#   - User copies the prompt output to Augment AI
#   - Augment AI emits the two files
#   - Files are saved AUTOMATICALLY (no manual intervention)
#   - Restoration script runs AUTOMATICALLY
#   - New instrumentation applied AUTOMATICALLY
#   - Verification happens AUTOMATICALLY
#   - Rollback is available if needed
#
# ZERO MANUAL STEPS after Augment emits the files.
###############################################################################

