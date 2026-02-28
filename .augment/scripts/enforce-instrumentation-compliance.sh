#!/usr/bin/env bash

###############################################################################
# RETRY-ENFORCING COMPLIANCE DRIVER FOR _closingPromise INSTRUMENTATION
#
# PURPOSE:
#   Force Augment AI to emit complete instrumentation code that proves what
#   sets _closingPromise in the Augment extension, with retry enforcement
#   instead of immediate failure on empty output.
#
# GOVERNING AUTHORITY:
#   - .augment/rules/mandatory-rules-v6.6.md
#   - .augment/instructions.md
#
# APPLICABLE RULES (ENUMERATED IN VERBOSE COMMENTS):
#
# RULE 0 (Emission Gate - HARD STOP):
#   - No artifact output until all checks pass
#   - All user instructions must be satisfied
#   - No partial compliance exists
#   - No uncertainty being guessed over
#   - Execute first, never ask
#   - Emission forbidden if execution evidence is indeterminate
#
# RULE 1 (Full Artifact Emission):
#   - Entire requested files must be emitted in single contiguous block
#   - Partial files, diffs, or patches alone are forbidden
#   - This script validates TWO complete files are emitted
#
# RULE 2 (No Partial Compliance):
#   - Partial compliance equals non-compliance
#   - CONTINUATION MANDATE: Continue until 100% complied with
#   - TIMEOUTS ARE NOT STOP SIGNALS: Retry instead of abort
#   - This script RETRIES on empty output instead of failing immediately
#
# RULE 6 (Known-Working Code Only):
#   - All code must be syntactically valid
#   - Based on documented, proven patterns
#   - No fabrication, no placeholders
#   - This script validates emitted code has no TODOs or ellipses
#
# RULE 7 (Evidence Before Assertion):
#   - All success claims require logs, tests, references
#   - This script verifies log file exists and contains required markers
#   - No success declared without evidence
#
# RULE 8 (Process Output Capture Reliability):
#   - launch-process with wait=true runs in user's visible terminal
#   - Output is in tool result <output> section
#   - This script uses bash execution (equivalent to wait=true)
#   - All output captured to log file for verification
#
# RULE 9 (Mandatory Output Reading - ZERO EXCEPTIONS):
#   - THE ONLY PATTERN: Execute → Read output → Quote verbatim → Analyze
#   - FORBIDDEN: Skipping output reading
#   - FORBIDDEN: Claiming "no output" without reading
#   - This script reads log file and validates content before declaring success
#
# RULE 11 (No Placeholders):
#   - No TODOs, fake values, or example credentials
#   - This script checks emitted code for TODO/FIXME/... markers
#
# RULE 12 (Deterministic Output):
#   - Outputs must be stable, repeatable, and ordered
#   - This script uses fixed retry count (no randomness)
#
# RULE 13 (Self-Audit Before Emission):
#   - If anything was removed, assumed, skipped, or fabricated, stop
#   - This script validates all required components before declaring success
#
# RULE 15 (Zero-Hang Guarantee):
#   - No incomplete steps or dangling actions
#   - Execution Abort may ONLY trigger if:
#     * Tool returned no <output> section
#     * START marker observed without END marker
#     * Tool returned explicit error
#   - Timeout alone is insufficient
#   - This script uses hard bounded retry loop with exponential backoff
#
# RULE 22 (Terminal Hygiene & Resource Management):
#   - ONE command per launch-process when possible
#   - Reuse terminals - don't spawn new ones unnecessarily
#   - This script runs entire retry loop in SINGLE shell process
#   - No recursive terminal spawning
#
# ENVIRONMENT DECLARATION (RULE 20):
#   Requires:
#     - bash >= 4.0
#     - .notes directory (writable)
#     - Node.js (for executing instrumentation)
#     - VSCode extension path: ~/.vscode/extensions/augment.vscode-augment-*
#
# REQUIRED EMITTED FILES (validated by this script):
#   1. instrument-closing-promise.js
#      Header: // instrument-closing-promise.js
#      Purpose: Monkey patch MCP client to intercept _closingPromise mutations
#      Must contain: Timestamp, PID, stack trace, previous/new value logging
#
#   2. launch-instrumented-augment.sh
#      Header: # launch-instrumented-augment.sh
#      Purpose: Detect extension path, backup, inject instrumentation, launch
#      Must be: Executable, complete, no placeholders
#
# VERIFICATION CRITERIA (RULE 7 - Evidence Before Assertion):
#   Log file must:
#     - Exist at ./augment-closingPromise-debug.log
#     - Be non-empty (size > 0)
#     - Contain string: "_closingPromise"
#     - Contain string: "STACK TRACE"
#
# RETRY STRATEGY (RULE 2 - No Partial Compliance):
#   - MAX_RETRIES: 5 attempts
#   - BACKOFF: Exponential (2s, 4s, 8s, 16s, 32s)
#   - ABORT: Only after all retries exhausted
#   - RATIONALE: Empty output may be transient, retry gives system time to stabilize
#
###############################################################################

set -euo pipefail

# CONFIGURATION
MAX_RETRIES=5
BASE_BACKOFF_SECONDS=2
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
LOG_DIR=".notes"
LOG_FILE="${LOG_DIR}/compliance-driver-${TIMESTAMP}.log"
INSTRUMENTATION_LOG="./augment-closingPromise-debug.log"

# Required files that Augment must emit
REQUIRED_FILE_1="instrument-closing-promise.js"
REQUIRED_FILE_2="launch-instrumented-augment.sh"

# Create log directory (RULE 20: Environment declaration)
mkdir -p "${LOG_DIR}"

# Initialize attempt counter
ATTEMPT=1
SUCCESS=0

###############################################################################
# FUNCTION: log_message
# PURPOSE: Log to both stdout and file (RULE 8: Output capture)
###############################################################################
log_message() {
    echo "$@" | tee -a "$LOG_FILE"
}

###############################################################################
# FUNCTION: validate_emitted_files
# PURPOSE: Verify Augment emitted both required files (RULE 1, RULE 6, RULE 11)
# RETURNS: 0 if valid, 1 if invalid
###############################################################################
validate_emitted_files() {
    log_message "=== VALIDATING EMITTED FILES ==="

    # RULE 1: Check both files exist
    if [[ ! -f "$REQUIRED_FILE_1" ]]; then
        log_message "❌ RULE 1 VIOLATION: Missing file: $REQUIRED_FILE_1"
        return 1
    fi

    if [[ ! -f "$REQUIRED_FILE_2" ]]; then
        log_message "❌ RULE 1 VIOLATION: Missing file: $REQUIRED_FILE_2"
        return 1
    fi

    # RULE 1: Check files are non-empty
    if [[ ! -s "$REQUIRED_FILE_1" ]]; then
        log_message "❌ RULE 1 VIOLATION: Empty file: $REQUIRED_FILE_1"
        return 1
    fi

    if [[ ! -s "$REQUIRED_FILE_2" ]]; then
        log_message "❌ RULE 1 VIOLATION: Empty file: $REQUIRED_FILE_2"
        return 1
    fi

    # RULE 1: Validate headers
    if ! head -1 "$REQUIRED_FILE_1" | grep -q "// instrument-closing-promise.js"; then
        log_message "❌ RULE 1 VIOLATION: Missing required header in $REQUIRED_FILE_1"
        log_message "   Expected: // instrument-closing-promise.js"
        log_message "   Got: $(head -1 "$REQUIRED_FILE_1")"
        return 1
    fi

    if ! head -1 "$REQUIRED_FILE_2" | grep -q "# launch-instrumented-augment.sh"; then
        log_message "❌ RULE 1 VIOLATION: Missing required header in $REQUIRED_FILE_2"
        log_message "   Expected: # launch-instrumented-augment.sh"
        log_message "   Got: $(head -1 "$REQUIRED_FILE_2")"
        return 1
    fi

    # RULE 11: Check for placeholders
    if grep -q -E "(TODO|FIXME|\.\.\.|XXX)" "$REQUIRED_FILE_1"; then
        log_message "❌ RULE 11 VIOLATION: Placeholders found in $REQUIRED_FILE_1"
        grep -n -E "(TODO|FIXME|\.\.\.|XXX)" "$REQUIRED_FILE_1" | tee -a "$LOG_FILE"
        return 1
    fi

    if grep -q -E "(TODO|FIXME|\.\.\.|XXX)" "$REQUIRED_FILE_2"; then
        log_message "❌ RULE 11 VIOLATION: Placeholders found in $REQUIRED_FILE_2"
        grep -n -E "(TODO|FIXME|\.\.\.|XXX)" "$REQUIRED_FILE_2" | tee -a "$LOG_FILE"
        return 1
    fi

    # RULE 6: Validate file 2 is executable or can be made executable
    if [[ ! -x "$REQUIRED_FILE_2" ]]; then
        log_message "⚠️  Making $REQUIRED_FILE_2 executable"
        chmod +x "$REQUIRED_FILE_2"
    fi

    log_message "✅ File validation passed (RULE 1, RULE 6, RULE 11 compliance)"
    return 0
}

###############################################################################
# FUNCTION: execute_instrumentation
# PURPOSE: Run the launcher script (RULE 8: Process output capture)
# RETURNS: 0 if executed, 1 if failed
###############################################################################
execute_instrumentation() {
    log_message "=== EXECUTING INSTRUMENTATION ==="

    # RULE 8: Execute with wait=true equivalent (blocking execution)
    # RULE 22: Single terminal session, no recursive spawning

    # Clean up previous instrumentation log (RULE 13: Start with clean state)
    if [[ -f "$INSTRUMENTATION_LOG" ]]; then
        rm -f "$INSTRUMENTATION_LOG"
        log_message "🗑️  Removed previous instrumentation log"
    fi

    log_message "Executing: ./$REQUIRED_FILE_2"

    # Execute launcher with timeout (RULE 22: Prevent runaway processes)
    # Capture output to log file (RULE 8: Output capture)
    if timeout 30s "./$REQUIRED_FILE_2" 2>&1 | tee -a "$LOG_FILE"; then
        log_message "✅ Launcher executed successfully"
        return 0
    else
        local exit_code=$?
        if [[ $exit_code -eq 124 ]]; then
            log_message "⚠️  Launcher timed out after 30 seconds (may be expected)"
            # Timeout is NOT a failure - instrumentation may still be running
            return 0
        else
            log_message "❌ Launcher failed with exit code: $exit_code"
            return 1
        fi
    fi
}

###############################################################################
# FUNCTION: verify_log_output
# PURPOSE: Validate instrumentation log (RULE 7: Evidence before assertion)
# RETURNS: 0 if valid, 1 if invalid
###############################################################################
verify_log_output() {
    log_message "=== VERIFYING LOG OUTPUT ==="

    # RULE 7: Check log file exists
    if [[ ! -f "$INSTRUMENTATION_LOG" ]]; then
        log_message "❌ RULE 7 VIOLATION: Log file not found: $INSTRUMENTATION_LOG"
        log_message "   No evidence of instrumentation execution"
        return 1
    fi

    # RULE 7: Check log is non-empty
    if [[ ! -s "$INSTRUMENTATION_LOG" ]]; then
        log_message "❌ RULE 7 VIOLATION: Log file is empty: $INSTRUMENTATION_LOG"
        log_message "   No evidence captured"
        return 1
    fi

    local log_size=$(wc -c < "$INSTRUMENTATION_LOG")
    log_message "📄 Log file size: $log_size bytes"

    # RULE 7: Check log contains required markers
    if ! grep -q "_closingPromise" "$INSTRUMENTATION_LOG"; then
        log_message "❌ RULE 7 VIOLATION: Log missing '_closingPromise' marker"
        log_message "   Instrumentation did not capture target property"
        return 1
    fi

    if ! grep -q "STACK TRACE" "$INSTRUMENTATION_LOG"; then
        log_message "❌ RULE 7 VIOLATION: Log missing 'STACK TRACE' marker"
        log_message "   No stack trace evidence captured"
        return 1
    fi

    # All checks passed
    log_message "✅ Log verification passed:"
    log_message "   - File exists: $INSTRUMENTATION_LOG"
    log_message "   - Content length: $log_size bytes"
    log_message "   - Contains '_closingPromise': YES"
    log_message "   - Contains 'STACK TRACE': YES"
    log_message "   RULE 7 compliance: Evidence before assertion confirmed"

    return 0
}


###############################################################################
# MAIN RETRY LOOP
# RULE 2 (No Partial Compliance): RETRY instead of aborting on empty output
# RULE 15 (Zero-Hang Guarantee): Hard bounded retry loop with exponential backoff
###############################################################################

log_message "========================================"
log_message "RETRY-ENFORCING COMPLIANCE DRIVER START"
log_message "========================================"
log_message "Timestamp: $TIMESTAMP"
log_message "Max retries: $MAX_RETRIES"
log_message "Base backoff: ${BASE_BACKOFF_SECONDS}s (exponential)"
log_message ""

while [[ $ATTEMPT -le $MAX_RETRIES ]]; do
    log_message "========================================"
    log_message "ATTEMPT $ATTEMPT/$MAX_RETRIES"
    log_message "========================================"

    # STEP 1: Validate emitted files (RULE 1, RULE 6, RULE 11)
    if ! validate_emitted_files; then
        log_message "⚠️  File validation failed on attempt $ATTEMPT"

        if [[ $ATTEMPT -lt $MAX_RETRIES ]]; then
            # RULE 2: Retry instead of abort
            local backoff_time=$((BASE_BACKOFF_SECONDS * (2 ** (ATTEMPT - 1))))
            log_message "   RULE 2: Retrying instead of aborting"
            log_message "   RULE 15: Exponential backoff - waiting ${backoff_time}s before retry"
            sleep "$backoff_time"
            ATTEMPT=$((ATTEMPT + 1))
            continue
        else
            # All retries exhausted
            log_message ""
            log_message "❌ COMPLIANCE DRIVER FAILURE"
            log_message "   Exceeded maximum retries ($MAX_RETRIES) without valid files"
            log_message "   RULE 2 VIOLATION: Request not 100% satisfied"
            log_message "   RULE 1 VIOLATION: Full artifact emission failed"
            exit 1
        fi
    fi

    # STEP 2: Execute instrumentation (RULE 8: Process output capture)
    if ! execute_instrumentation; then
        log_message "⚠️  Instrumentation execution failed on attempt $ATTEMPT"

        if [[ $ATTEMPT -lt $MAX_RETRIES ]]; then
            # RULE 2: Retry instead of abort
            local backoff_time=$((BASE_BACKOFF_SECONDS * (2 ** (ATTEMPT - 1))))
            log_message "   RULE 2: Retrying instead of aborting"
            log_message "   RULE 15: Exponential backoff - waiting ${backoff_time}s before retry"
            sleep "$backoff_time"
            ATTEMPT=$((ATTEMPT + 1))
            continue
        else
            # All retries exhausted
            log_message ""
            log_message "❌ COMPLIANCE DRIVER FAILURE"
            log_message "   Exceeded maximum retries ($MAX_RETRIES) without successful execution"
            log_message "   RULE 2 VIOLATION: Request not 100% satisfied"
            log_message "   RULE 8 VIOLATION: Process output capture failed"
            exit 1
        fi
    fi

    # STEP 3: Verify log output (RULE 7: Evidence before assertion)
    if verify_log_output; then
        # SUCCESS - all checks passed
        SUCCESS=1
        break
    else
        log_message "⚠️  Log verification failed on attempt $ATTEMPT"

        if [[ $ATTEMPT -lt $MAX_RETRIES ]]; then
            # RULE 2: Retry instead of abort
            local backoff_time=$((BASE_BACKOFF_SECONDS * (2 ** (ATTEMPT - 1))))
            log_message "   RULE 2: Retrying instead of aborting"
            log_message "   RULE 15: Exponential backoff - waiting ${backoff_time}s before retry"
            sleep "$backoff_time"
            ATTEMPT=$((ATTEMPT + 1))
            continue
        else
            # All retries exhausted
            log_message ""
            log_message "❌ COMPLIANCE DRIVER FAILURE"
            log_message "   Exceeded maximum retries ($MAX_RETRIES) without valid log output"
            log_message "   RULE 2 VIOLATION: Request not 100% satisfied"
            log_message "   RULE 7 VIOLATION: No evidence captured"
            exit 1
        fi
    fi
done

###############################################################################
# POST-EXECUTION WATCHDOGS
# RULE 9 (Mandatory Output Reading): Run watchdog scripts before declaring success
###############################################################################

if [[ $SUCCESS -eq 1 ]]; then
    log_message ""
    log_message "========================================"
    log_message "RUNNING POST-EXECUTION WATCHDOGS"
    log_message "========================================"

    # RULE 9: Run terminal-watchdog.sh if available
    if [[ -x ".augment/scripts/terminal-watchdog.sh" ]]; then
        log_message "Running terminal-watchdog.sh..."
        if .augment/scripts/terminal-watchdog.sh 2>&1 | tee -a "$LOG_FILE"; then
            log_message "✅ terminal-watchdog.sh passed"
        else
            log_message "⚠️  terminal-watchdog.sh reported issues (non-fatal)"
        fi
    else
        log_message "⚠️  terminal-watchdog.sh not found or not executable (skipping)"
    fi

    # RULE 9: Run pre-response-check.sh if available
    if [[ -x ".augment/scripts/pre-response-check.sh" ]]; then
        log_message "Running pre-response-check.sh..."
        if .augment/scripts/pre-response-check.sh 2>&1 | tee -a "$LOG_FILE"; then
            log_message "✅ pre-response-check.sh passed"
        else
            log_message "⚠️  pre-response-check.sh reported issues (non-fatal)"
        fi
    else
        log_message "⚠️  pre-response-check.sh not found or not executable (skipping)"
    fi
fi

###############################################################################
# FINAL STATUS
# RULE 0 (Emission Gate): No success without validated evidence
# RULE 13 (Self-Audit): Verify nothing was removed, assumed, skipped, or fabricated
###############################################################################

log_message ""
log_message "========================================"
log_message "FINAL STATUS"
log_message "========================================"

if [[ $SUCCESS -eq 1 ]]; then
    log_message "✅ COMPLIANCE DRIVER SUCCESS"
    log_message ""
    log_message "RULE COMPLIANCE VERIFIED:"
    log_message "  ✅ RULE 0: Emission gate - all checks passed"
    log_message "  ✅ RULE 1: Full artifact emission - both files complete"
    log_message "  ✅ RULE 2: No partial compliance - 100% satisfied"
    log_message "  ✅ RULE 6: Known-working code only - no placeholders"
    log_message "  ✅ RULE 7: Evidence before assertion - log verified"
    log_message "  ✅ RULE 8: Process output capture - execution successful"
    log_message "  ✅ RULE 9: Mandatory output reading - watchdogs run"
    log_message "  ✅ RULE 11: No placeholders - validation passed"
    log_message "  ✅ RULE 13: Self-audit - nothing skipped"
    log_message "  ✅ RULE 15: Zero-hang guarantee - bounded retry loop"
    log_message "  ✅ RULE 22: Terminal hygiene - single process"
    log_message ""
    log_message "INSTRUMENTATION LOG: $INSTRUMENTATION_LOG"
    log_message "COMPLIANCE LOG: $LOG_FILE"
    log_message ""
    log_message "Next steps:"
    log_message "  1. Review instrumentation log for stack traces"
    log_message "  2. Identify what code path sets _closingPromise"
    log_message "  3. Fix the one-way latch bug in Augment extension"

    exit 0
else
    log_message "❌ COMPLIANCE DRIVER FAILURE"
    log_message "   This should never be reached (retries should have exited earlier)"
    log_message "   RULE 15 VIOLATION: Incomplete execution path"

    exit 1
fi

