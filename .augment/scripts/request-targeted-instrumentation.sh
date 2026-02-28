#!/usr/bin/env bash
###############################################################################
# REQUEST TARGETED INSTRUMENTATION - WORKING PROMPT AS EXECUTABLE CODE
#
# PURPOSE:
#   Generate and display a complete prompt for Augment AI that:
#     1) Enumerates ALL requirements for TARGETED instrumentation
#     2) Plans the complete execution workflow
#     3) Effects compliance automatically (no manual steps)
#
# PROBLEM IDENTIFIED:
#   Current instrumentation patches 663 classes (TOO MANY)
#   Evidence from log: Patches everything from Breakpoint to batch_write
#   Solution: Target ONLY the class that contains _closingPromise assignment
#
# ROOT CAUSE (FROM EXTENSION.JS LINE 18):
#   this._closingPromise===void 0&&(this._cancelledByUser=t,this._closingPromise=(async()=>{...
#
# STRATEGY:
#   Instead of patching ALL classes, search extension.js source code for:
#     - Pattern: this._closingPromise=(async()=>
#     - Find the class/function that contains this pattern
#     - Patch ONLY that specific class prototype
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
#   \"If it can be typed, it MUST be scripted!\"
#   - NO manual file saving
#   - NO manual copy/paste
#   - NO manual permission setting
#   - ALL steps automated
#
# USAGE:
#   ./request-targeted-instrumentation.sh
#
###############################################################################

cat <<'END_PROMPT'
################################################################################
# AUGMENT AI: EMIT TARGETED INSTRUMENTATION FOR _closingPromise
################################################################################

# PROBLEM ANALYSIS (EVIDENCE-BASED)
# ==================================

# CURRENT STATE:
#   ✅ Prototype instrumentation IS working
#   ✅ Log file shows 663 classes patched
#   ❌ TOO BROAD - Patching ALL classes from ALL modules
#   ❌ Performance impact - Unnecessary overhead
#   ❌ No _closingPromise mutations detected yet

# EVIDENCE FROM LOG FILE (VERBATIM):
#   [PROTOTYPE PATCH] Applied to class: Breakpoint
#   [PROTOTYPE PATCH] Applied to class: ChatCompletionItem
#   ...
#   [PROTOTYPE PATCH] Applied to class: batch_write
#   Total: 663 classes patched

# ROOT CAUSE:
#   Module._load hook patches EVERY class from EVERY module
#   We need to target ONLY the class that assigns _closingPromise

# EVIDENCE FROM EXTENSION.JS LINE 18:
#   this._closingPromise===void 0&&(this._cancelledByUser=t,this._closingPromise=(async()=>{...
#
# This shows:
#   - _closingPromise is assigned inside a method/constructor
#   - The assignment is: this._closingPromise=(async()=>{...
#   - We need to find which class contains this code

# ENUMERATION OF REQUIREMENTS (COMPLETE LIST)
# ============================================

## FILE 1: instrument-closing-promise-targeted.js (Node.js)

# REQUIREMENT 1.1: Search extension.js source code for _closingPromise assignment
#   - Read extension.js file content
#   - Search for pattern: this._closingPromise=(async()=>
#   - Extract surrounding context to identify class name
#   - Handle minified code (may need regex pattern matching)

# REQUIREMENT 1.2: Find the class constructor that contains _closingPromise
#   - Parse extension.js to find class definition
#   - Look for constructor or method that assigns this._closingPromise
#   - In minified code, class name may be obfuscated (e.g., single letter)
#   - Verify class found before patching

# REQUIREMENT 1.3: Patch ONLY the target class prototype
#   - Use Object.defineProperty() on the specific class prototype
#   - Create hidden storage property: Symbol('_closingPromiseValue')
#   - Define getter that returns stored value
#   - Define setter that captures and logs all mutations
#   - Apply to ONLY the target class, not all classes

# REQUIREMENT 1.4: Capture complete diagnostic data on every assignment
#   - ISO timestamp: new Date().toISOString()
#   - Process PID: process.pid
#   - Previous value of _closingPromise
#   - New value of _closingPromise
#   - Complete stack trace: new Error().stack
#   - Instance identifier (if available)
#   - Class name that was patched

# REQUIREMENT 1.5: Log to persistent file
#   - File path: ./augment-closingPromise-debug.log
#   - Use fs.appendFileSync() for atomic writes
#   - Format: human-readable with clear markers
#   - Include evidence that correct class was patched
#   - Show class name and line number where found

# REQUIREMENT 1.6: Log to console for immediate visibility
#   - Use console.error() for stderr output
#   - Include all diagnostic data
#   - Add visual separators for readability
#   - Confirm which class was patched (not 663 classes!)

# REQUIREMENT 1.7: Fallback strategy if class not found
#   - If pattern matching fails, log error
#   - Provide diagnostic info about what was searched
#   - Do NOT crash the extension
#   - Suggest manual inspection of extension.js

# REQUIREMENT 1.8: Code quality requirements
#   - Complete, executable Node.js code (no placeholders)
#   - Verbose inline comments explaining each step
#   - Follow RULE 0, 6, 7, 9, 11, 18, 22
#   - No TODO, FIXME, or example values
#   - Handle errors gracefully (log but don't crash extension)

## FILE 2: apply-targeted-instrumentation.sh (Bash)

# REQUIREMENT 2.1: Restore original extension.js
#   - Run: ./restore-original-extension.sh
#   - Verify restoration succeeded
#   - Remove old instrumentation files

# REQUIREMENT 2.2: Apply new targeted instrumentation
#   - Copy instrument-closing-promise-targeted.js to extension directory
#   - Inject require() at top of extension.js
#   - Verify injection succeeded

# REQUIREMENT 2.3: Provide verification
#   - Show file sizes before/after
#   - Confirm instrumentation applied
#   - Provide instructions to reload VS Code

# REQUIREMENT 2.4: Code quality requirements
#   - Complete, executable Bash script (no placeholders)
#   - Verbose inline comments explaining each step
#   - Follow RULE 0, 6, 7, 9, 11, 18, 22
#   - Safe to run multiple times (idempotent)

# EXECUTION PLAN (COMPLETE WORKFLOW)
# ===================================

# STEP 1: Augment AI emits exactly 2 code blocks
#   - First block: ```javascript ... ``` (instrument-closing-promise-targeted.js)
#   - Second block: ```bash ... ``` (apply-targeted-instrumentation.sh)
#   - Both blocks are COMPLETE working code (no placeholders)

# STEP 2: Files are written to disk AUTOMATICALLY
#   - instrument-closing-promise-targeted.js → ./instrument-closing-promise-targeted.js
#   - apply-targeted-instrumentation.sh → ./apply-targeted-instrumentation.sh
#   - Permissions set: chmod +x apply-targeted-instrumentation.sh
#   - NO MANUAL SAVING REQUIRED

# STEP 3: Execute application script
#   - Run: ./apply-targeted-instrumentation.sh
#   - This restores original extension.js
#   - Applies new targeted instrumentation
#   - Verifies application succeeded

# STEP 4: Reload VS Code window
#   - Ctrl+Shift+P → \"Developer: Reload Window\"
#   - Extension loads with TARGETED instrumentation
#   - Only 1 class patched (not 663!)

# STEP 5: Verification of targeted patching
#   - Check console for: \"[TARGETED PATCH] Applied to class: <ClassName>\"
#   - Check log file: ./augment-closingPromise-debug.log
#   - Verify log shows ONLY 1 class patched
#   - Verify class name matches the one found in extension.js

# STEP 6: Monitoring and verification
#   - Monitor log file: tail -f ./augment-closingPromise-debug.log
#   - Use Augment AI normally
#   - When _closingPromise is set, stack trace appears
#   - Verify log contains: timestamp, PID, stack trace, values, class name

# STEP 7: Rollback if needed
#   - Run: ./restore-original-extension.sh
#   - Reload VS Code window
#   - Verify Augment works normally

# COMPLIANCE EFFECTED (AUTOMATED ENFORCEMENT)
# ============================================

# All compliance checks from previous version PLUS:

# PERFORMANCE:
#   ✅ Patch ONLY 1 class (not 663)
#   ✅ Minimal overhead
#   ✅ No unnecessary prototype modifications

# PRECISION:
#   ✅ Target the EXACT class that assigns _closingPromise
#   ✅ Evidence-based class identification
#   ✅ Fallback if class not found

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
#   - Previous: Patched 663 classes (ALL classes from ALL modules)
#   - Current: Patch ONLY 1 class (the one that assigns _closingPromise)
#   - Evidence: Log shows 663 prototype patches (too many)
#   - Solution: Search extension.js for assignment pattern, patch only that class
#
# Following the \"If it can be typed, it MUST be scripted!\" principle:
#   - User runs THIS script to see the prompt
#   - Augment AI emits the two files
#   - Files are saved AUTOMATICALLY
#   - Application script runs AUTOMATICALLY
#   - Verification happens AUTOMATICALLY
#   - Rollback is available if needed
#
# ZERO MANUAL STEPS after Augment emits the files.
###############################################################################

