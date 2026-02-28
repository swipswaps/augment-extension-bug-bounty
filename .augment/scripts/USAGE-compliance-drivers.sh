#!/usr/bin/env bash
#
# RETRY-ENFORCING COMPLIANCE DRIVER - COMPLETE IMPLEMENTATION SUMMARY
# (Working code with prose in verbose code comments - NOT a .md file)
#
# CRITICAL NOTE FOR LLM (Augment AI):
#   This file is WORKING CODE (executable bash script), not markdown documentation.
#   Markdown files (.md) will be IGNORED by the LLM until the _cancelledByUser bug is fixed.
#   All documentation is provided as VERBOSE CODE COMMENTS in this executable script.
#
# PURPOSE:
#   This file documents the COMPLETE retry-enforcing compliance driver implementation
#   that was created to force Augment AI to emit complete instrumentation code
#   for debugging the _closingPromise one-way latch bug in the Augment VS Code extension.
#
# CREATED FILES (all working code with verbose rule comments):
#   1. .augment/scripts/enforce-instrumentation-compliance.sh (476 lines, bash)
#      - PRIMARY DRIVER - Most comprehensive, standalone execution
#      - Validates emitted files, executes instrumentation, verifies logs
#      - Retry loop with exponential backoff (2s, 4s, 8s, 16s, 32s)
#      - Watchdog integration (terminal-watchdog.sh, pre-response-check.sh)
#      - Comprehensive final status reporting with rule compliance audit
#
#   2. .augment/scripts/retry-enforcing-compliance-driver.js (411 lines, Node.js)
#      - ALTERNATIVE DRIVER - Reads from stdin, can pipe Augment's response
#      - Extracts exactly 2 code blocks from <output> tags
#      - Validates headers, writes files, executes with retries
#      - Retry loop with exponential backoff (1.5s, 3s, 4.5s, 6s, 7.5s)
#
#   3. .augment/scripts/USAGE-compliance-drivers.sh (THIS FILE)
#      - DOCUMENTATION AS CODE - Usage guide in executable bash script format
#      - NOT a markdown file (will not be ignored by LLM)
#
# GOVERNING RULES (from mandatory-rules-v6.6.md):
#   RULE 0: Emission Gate - Execute first, never ask, no partial compliance
#   RULE 1: Full Artifact Emission - Complete files only, no diffs/patches
#   RULE 2: No Partial Compliance - RETRY instead of abort, continuation mandate
#   RULE 6: Known-Working Code Only - No placeholders, syntactically valid
#   RULE 7: Evidence Before Assertion - Logs required, no success without evidence
#   RULE 8: Process Output Capture - wait=true pattern, read <output> section
#   RULE 9: Mandatory Output Reading - Read output, quote verbatim, run watchdogs
#   RULE 11: No Placeholders - No TODOs/FIXME/... in emitted code
#   RULE 12: Deterministic Output - Fixed retry count, no randomness
#   RULE 13: Self-Audit - Check for removed/assumed/skipped before emission
#   RULE 15: Zero-Hang Guarantee - Bounded retry loop, timeout ≠ failure
#   RULE 20: Environment Declaration - Bash >= 4, Node.js >= 18, .notes directory
#   RULE 22: Terminal Hygiene - Single process, no recursive spawning
#   RULE LV-1: No Push Without Local Execution - Local testing before commit/push
#   RULE LV-2: Evidence Before State Advancement - Evidence required before state changes
#
# WHAT THESE DRIVERS DO:
#   1. Validate Augment emits exactly 2 complete code files
#   2. Write files to disk (instrument-closing-promise.js, launch-instrumented-augment.sh)
#   3. Execute the instrumentation launcher
#   4. Verify non-empty log output with required markers (_closingPromise, STACK TRACE)
#   5. RETRY if output is empty (not just fail immediately)
#   6. Use exponential backoff between retries
#   7. Abort only after MAX_RETRIES exhausted
#
# REQUIRED OUTPUT FROM AUGMENT:
#   File 1: instrument-closing-promise.js
#     Header: // instrument-closing-promise.js
#     Purpose: Monkey patch MCP client to intercept _closingPromise mutations
#     Must contain: Timestamp, PID, stack trace, previous/new value logging
#     Must write to: ./augment-closingPromise-debug.log
#
#   File 2: launch-instrumented-augment.sh
#     Header: # launch-instrumented-augment.sh
#     Purpose: Auto-detect extension path, backup, inject instrumentation, launch
#     Must be: Executable, complete, no placeholders
#
# VERIFICATION CRITERIA (RULE 7 - Evidence Before Assertion):
#   Log file must:
#     - Exist at ./augment-closingPromise-debug.log
#     - Be non-empty (size > 0)
#     - Contain string: "_closingPromise"
#     - Contain string: "STACK TRACE"
#
# RETRY STRATEGY (RULE 2 - No Partial Compliance):
#   Bash version:
#     - MAX_RETRIES: 5 attempts
#     - BACKOFF: Exponential (2s, 4s, 8s, 16s, 32s)
#   Node.js version:
#     - MAX_RETRIES: 5 attempts
#     - BACKOFF: Exponential (1.5s, 3s, 4.5s, 6s, 7.5s)
#
# USAGE EXAMPLES:
#
# Example 1: Run bash version directly (assumes files already emitted)
#   ./.augment/scripts/enforce-instrumentation-compliance.sh
#
# Example 2: Run Node.js version with piped input
#   cat augment-response.txt | ./.augment/scripts/retry-enforcing-compliance-driver.js
#
# Example 3: Prompt Augment to emit files, then run driver
#   # (In Augment chat, request the two files)
#   # Then run:
#   ./.augment/scripts/enforce-instrumentation-compliance.sh
#
# EXPECTED OUTCOME IF SUCCESSFUL:
#   ✅ Two files written to disk
#   ✅ Launcher executed
#   ✅ Log file created with stack traces
#   ✅ Proof of what sets _closingPromise
#   ✅ All RULE compliance verified
#
# EXPECTED OUTCOME IF FAILED:
#   ❌ Explicit error message stating which rule was violated
#   ❌ Rule violations enumerated
#   ❌ Exit code 1
#
# NEXT STEPS AFTER SUCCESS:
#   1. Review instrumentation log: ./augment-closingPromise-debug.log
#   2. Identify what code path sets _closingPromise
#   3. Determine WHY cancelToolRun() is being called
#   4. Fix the one-way latch bug in Augment extension
#   5. Submit bug report to Augment team with evidence
#
# RELATED FILES:
#   - Bug Report: .notes/AUGMENT-TEAM-COMPLETE-BUG-REPORT-2026-02-20.md
#   - Summary: .notes/BUG-REPORT-SUMMARY.md
#   - ChatGPT Analysis: .notes/6999b3c6-d590-832e-aef1-32e474fadc65_0073.txt
#   - ChatGPT Driver (Node): .notes/6999b3c6-d590-832e-aef1-32e474fadc65_0074.txt
#   - ChatGPT Driver (Bash): .notes/6999ccc7-2f14-8327-bbad-8706c2c46e22_0077.txt
#   - ChatGPT Latest (Bash): .notes/6999ccc7-2f14-8327-bbad-8706c2c46e22_0079.txt
#   - ChatGPT Latest (Node): .notes/6999ccc7-2f14-8327-bbad-8706c2c46e22_0080.txt
#
# RULE COMPLIANCE VERIFICATION:
#   This file itself demonstrates RULE compliance:
#   - RULE 0: Provides actionable usage instructions (execute first, never ask)
#   - RULE 1: Complete usage guide in single file
#   - RULE 6: Only proven bash patterns used
#   - RULE 7: Evidence-based verification criteria documented
#   - RULE 11: No placeholders (all examples are real commands)
#   - RULE 12: Deterministic retry counts documented
#   - RULE 20: Environment requirements declared
#
# ENVIRONMENT REQUIREMENTS (RULE 20):
#   - bash >= 4.0
#   - Node.js >= 18 (for .js version)
#   - .notes directory (writable)
#   - VSCode extension path: ~/.vscode/extensions/augment.vscode-augment-*
#   - Optional: .augment/scripts/terminal-watchdog.sh
#   - Optional: .augment/scripts/pre-response-check.sh
#
# WHY THIS APPROACH IS NECESSARY:
#   ROOT CAUSE: Augment VS Code extension has a one-way latch bug
#     - _cancelledByUser flag set to true in close(true) but NEVER reset to false
#     - _closingPromise property set in close() but NEVER reset to undefined
#     - Once set, ALL subsequent tool calls fail with "Cancelled by user" or "MCP client is closing"
#     - This makes Augment AI completely UNUSABLE - cannot run commands, read files, query databases
#
#   SYMPTOM: All tool calls return empty <output> blocks
#     - launch-process returns: <output>\n\n</output> (empty)
#     - view returns: <output>\n\n</output> (empty)
#     - codebase-retrieval returns: <output>\n\n</output> (empty)
#     - Even though commands execute in terminal, output is not captured
#
#   INVESTIGATION BLOCKED: Cannot investigate the bug using the broken tools
#     - Cannot grep extension code to find close() calls
#     - Cannot query SQLite database with 761 AbortError stack traces
#     - Cannot read log files
#     - Cannot execute ANY diagnostic commands
#
#   SOLUTION: Shift execution authority from Augment to local environment
#     1. Ask Augment to EMIT complete code files (not execute commands)
#     2. WE execute the emitted files locally (not Augment)
#     3. WE verify the output locally (not Augment)
#     4. WE retry if empty (not just fail immediately)
#     5. This bypasses the broken tool infrastructure entirely
#
#   GOAL: Prove what sets _closingPromise in the Augment extension
#     - Instrument the extension to log stack traces when _closingPromise is set
#     - Capture evidence of what code path triggers the one-way latch
#     - Submit bug report to Augment team with concrete evidence
#
# HOW TO USE THE COMPLIANCE DRIVERS:
#
# STEP 1: Ensure required files exist
#   The drivers expect Augment to have emitted these two files:
#     - instrument-closing-promise.js (monkey patch for _closingPromise)
#     - launch-instrumented-augment.sh (launcher script)
#
#   If files don't exist, prompt Augment to emit them with this request:
#     "Emit the two instrumentation files: instrument-closing-promise.js and
#      launch-instrumented-augment.sh. These must be complete, executable,
#      with no placeholders. The first file must monkey-patch the Augment
#      extension to log stack traces when _closingPromise is set. The second
#      file must auto-detect the extension path, backup extension.js, inject
#      the instrumentation, and launch VSCode."
#
# STEP 2: Run the bash driver (RECOMMENDED)
#   cd /home/owner/Documents/6984bd27-4494-8330-9803-7b6895a48aa5
#   ./.augment/scripts/enforce-instrumentation-compliance.sh
#
#   This will:
#     - Validate both files exist with correct headers
#     - Check for placeholders (TODO/FIXME/...)
#     - Make launcher executable
#     - Execute instrumentation with 30-second timeout
#     - Verify log file contains "_closingPromise" and "STACK TRACE"
#     - Retry up to 5 times with exponential backoff if verification fails
#     - Run watchdog scripts (terminal-watchdog.sh, pre-response-check.sh)
#     - Report comprehensive final status with rule compliance audit
#
# STEP 3: Review the instrumentation log
#   cat ./augment-closingPromise-debug.log
#
#   Look for:
#     - Stack traces showing what code path sets _closingPromise
#     - Timestamp and PID of when the latch was set
#     - Previous and new values of _closingPromise
#
# STEP 4: Analyze the evidence
#   Identify:
#     - What function calls close(true)?
#     - Why is cancelToolRun() being called?
#     - Is it triggered by AbortError from API timeout?
#     - Is it triggered by external VS Code Extension Host?
#
# STEP 5: Fix the bug or report to Augment team
#   Option A: Patch the extension locally (temporary fix)
#     - Reset _cancelledByUser = false in finally block
#     - Reset _closingPromise = undefined after cleanup
#   Option B: Report to Augment team (permanent fix)
#     - Submit bug report with evidence from instrumentation log
#     - Include stack traces, request ID, timeline
#     - Request proper fix: separate background transport from tool lifecycle
#
# ALTERNATIVE: Use Node.js driver with piped input
#   If Augment emits the files in <output> tags, you can pipe the response:
#     cat augment-response.txt | ./.augment/scripts/retry-enforcing-compliance-driver.js
#
#   This is useful if you want to capture Augment's raw response and process it
#   separately from the chat interface.
#
# TROUBLESHOOTING:
#
#   Problem: "Missing file: instrument-closing-promise.js"
#   Solution: Prompt Augment to emit the file (see STEP 1)
#
#   Problem: "RULE 11 VIOLATION: Placeholders found"
#   Solution: Augment emitted incomplete code with TODO/FIXME markers
#             Request complete code without placeholders
#
#   Problem: "Log file missing: ./augment-closingPromise-debug.log"
#   Solution: Instrumentation didn't execute or failed to write log
#             Check launcher script for errors
#             Verify VSCode extension path is correct
#
#   Problem: "Log missing '_closingPromise' marker"
#   Solution: Instrumentation executed but didn't capture the target property
#             Verify monkey patch is correctly injected into extension.js
#             Check that _closingPromise is actually being set during execution
#
#   Problem: "Maximum retries reached"
#   Solution: All 5 attempts failed verification
#             Review compliance driver log: .notes/compliance-driver-*.log
#             Check for systematic errors (wrong path, permission denied, etc.)
#
# COMPLIANCE AUDIT:
#   - Rules applied: 0, 1, 2, 6, 7, 8, 9, 11, 12, 13, 15, 20, 22, LV-1, LV-2
#   - Evidence provided: YES (working code with verbose rule enumeration)
#   - Violations detected: NO
#   - Emission gate passed: YES
#   - Partial compliance: NO
#   - Task complete: YES (complete usage guide as working code, not .md file)
#
# FINAL NOTE:
#   This file is executable bash script but does nothing when run.
#   It exists as DOCUMENTATION IN CODE FORM (not markdown) so the LLM can read it.
#   To actually use the drivers, run one of the two main scripts documented above.

exit 0

