#!/usr/bin/env node
"use strict";

/*
RETRY-ENFORCING COMPLIANCE DRIVER
=================================

PURPOSE:
  Force Augment AI to emit two complete executable files that instrument
  the Augment extension's _closingPromise property to prove what sets it.
  
  This driver enforces FULL REQUEST COMPLIANCE by:
  1. Validating exactly two code blocks are emitted
  2. Writing files to disk
  3. Executing the instrumentation launcher
  4. Verifying non-empty log output
  5. RETRYING if output is empty (not just failing)
  6. Using exponential backoff between retries
  7. Aborting only after MAX_RETRIES exhausted

APPLICABLE RULES FROM mandatory-rules-v6.6.md:
  
  RULE 0 (Emission Gate):
    - No artifact output until all checks pass
    - No partial compliance
    - No uncertainty being guessed over
    - Partial answers are forbidden
    - EXECUTE FIRST, NEVER ASK
  
  RULE 1 (Full Artifact Emission):
    - Entire requested files must be emitted in single contiguous block
    - Partial files, diffs, or patches alone are forbidden
  
  RULE 2 (No Partial Compliance):
    - Partial compliance equals non-compliance
    - CONTINUATION MANDATE: Must continue until 100% complied with
    - CORRECT WORKFLOW ORDER: Code fix → Build → TEST LOCALLY → Commit → Push → Deploy → Verify
    - FORBIDDEN STOPPING POINTS: After code edit without testing, after build without testing, etc.
    - TIMEOUTS ARE NOT STOP SIGNALS: Continue to test if server is running
  
  RULE 6 (Known-Working Code Only):
    - All code must be syntactically valid
    - Based on documented, proven patterns
    - No fabrication, no placeholders
  
  RULE 7 (Evidence Before Assertion):
    - All success claims require logs, tests, references, or official documentation
    - No assertions without evidence
  
  RULE 8 (Process Output Capture Reliability):
    - launch-process with wait=true runs in user's visible terminal
    - Output is in tool result <output> section - READ IT
    - NEVER use wait=false - creates hidden background terminals
    - NEVER call read-process - AI-only hidden tool
    - NEVER call list-processes - AI-only hidden tool
  
  RULE 9 (Mandatory Output Reading - ZERO EXCEPTIONS):
    - THE ONLY PATTERN (MANDATORY):
      Step 1: Call launch-process with wait=true, max_wait_seconds=10
      Step 2: Tool returns with <output> section
      Step 3: RUN .augment/scripts/terminal-watchdog.sh (MANDATORY)
      Step 4: READ the <output> section (MANDATORY - NOT OPTIONAL)
      Step 5: READ the log file from .notes/terminal-*.log (MANDATORY)
      Step 6: QUOTE verbatim output from BOTH sources
      Step 7: ANALYZE what the output means
      Step 8: RUN .augment/scripts/pre-response-check.sh before responding (MANDATORY)
      Step 9: PROCEED with next action
    - FORBIDDEN: Skipping steps 3-6 and calling list-processes or read-process instead
    - FORBIDDEN: Asking "should I run this?" instead of executing
    - FORBIDDEN: Claiming "no output" without reading <output> section
    - FORBIDDEN: Responding without running watchdog scripts
  
  RULE 11 (No Placeholders):
    - No TODOs, fake values, or example credentials
    - All code must be complete and executable
  
  RULE 13 (Self-Audit Before Emission):
    - If anything was removed, assumed, skipped, or fabricated, stop
    - Audit checklist must pass before emission
  
  RULE 15 (Zero-Hang Guarantee):
    - No incomplete steps or dangling actions
    - Execution Abort may ONLY trigger if at least one of:
      * Tool returned no <output> section
      * START marker observed without END marker
      * Tool returned explicit error
    - Timeout alone is insufficient
  
  RULE 22 (Terminal Hygiene & Resource Management):
    - ONE command per launch-process call when possible
    - Reuse terminals - don't spawn new ones unnecessarily
    - NEVER use wait=false unless launching long-running server
    - Kill servers before respawning
    - Combine related checks into ONE command
    - Maximum active terminals: if >5, HALT and consolidate

APPLICABLE RULES FROM .augment/instructions.md:

  MANDATORY PRE-EXECUTION CHECKLIST:
    1. WRITE THEN FOLLOW EXACTLY THE CORRECT PROMPT
    2. PROCEED WITHOUT STOPPING UNLESS IMPOSSIBLE
    3. EXECUTE FIRST, NEVER ASK
    4. ALWAYS use wait=true
    5. ALWAYS use max_wait_seconds=10
    6. Output is in tool result - read <output> section
    7. MANDATORY TERMINAL LOGGING to .notes/terminal-*.log
    8. READ FROM LOG FILES after EVERY command
    9. Use echo markers: "START: action" && command && "END: action"
    10. Complete all steps - NO incomplete actions
    11. Verify tool names before calling
    12. View before editing
    13. FULL REQUEST COMPLIANCE - 100%, not partial
    14. WATCHDOG ENFORCEMENT (MANDATORY)
    15. THE ONLY PATTERN (MANDATORY) - 9 steps, follow in order

  RULE 9 VIOLATION DETECTOR:
    - PROVEN FACT: launch-process with wait=true runs in user's VISIBLE terminal
    - CRITICAL: ALL commands MUST use wait=true
    - CRITICAL: Output is in <output> section - MUST READ IT EVERY TIME
    - CRITICAL: NEVER use wait=false - creates hidden background terminals
    - AFTER EVERY launch-process call, assistant MUST read <output> section
    - TIMEOUT PROTOCOL: Check <output> section even after timeout
    - FORBIDDEN: Calling read-process or list-processes in normal workflow

  RULE LV-1 (No Push Without Local Execution):
    - MUST NOT commit or push without local execution and observable results
    - "Local execution" means: running app, triggering code path, producing logs
    - Mocking, reasoning, or "this should work" does NOT qualify

  RULE LV-2 (Evidence Before State Advancement):
    - Before advancing edited → committed → pushed → deployed
    - MUST present evidence: verbatim console output, browser observation, test output
    - Assertions without evidence are INVALID

REQUIRED EMITTED FILES (exact headers required):
  
  File 1: instrument-closing-promise.js
    Header: // instrument-closing-promise.js
    Purpose: Monkey patch MCP client to intercept _closingPromise mutations
    Must: Log timestamp, PID, stack trace, previous value, new value
    Must: Tee to stdout AND ./augment-closingPromise-debug.log
    Must: Preserve original behavior
  
  File 2: launch-instrumented-augment.sh
    Header: # launch-instrumented-augment.sh
    Purpose: Detect VSCode extension path, backup extension.js, inject instrumentation
    Must: Use tee to preserve terminal logs
    Must: Launch code with clean environment

ENFORCEMENT STRATEGY:
  - Validate exactly two fenced code blocks in Augment response
  - Extract code from blocks
  - Validate headers match exactly
  - Write both files to disk
  - chmod +x launcher script
  - Execute launcher
  - Verify log file exists at ./augment-closingPromise-debug.log
  - Verify log file is non-empty
  - Verify log contains "_closingPromise" string
  - Verify log contains "STACK TRACE" string
  - If any verification fails → RETRY execution (not abort)
  - Use exponential backoff between retries
  - Abort only after MAX_RETRIES exhausted

NO PROSE ALLOWED IN AUGMENT RESPONSE:
  - Exactly two code blocks
  - No markdown outside fenced blocks
  - No diffs
  - No partial files
  - No truncation
  - No ellipses
  - No summaries
  - No explanations outside code comments
*/

const fs = require("fs");
const { spawnSync } = require("child_process");

// CONFIGURATION
const MAX_RETRIES = 5;           // Maximum retry attempts before aborting
const BACKOFF_MS = 1500;         // Base backoff milliseconds (multiplied by attempt number)
const LOG_PATH = "./augment-closingPromise-debug.log";  // Expected log file path

// ENFORCEMENT FUNCTIONS

/*
RULE 0 (Emission Gate): Halt immediately if validation fails
RULE 7 (Evidence Before Assertion): Provide explicit failure reason
*/
function fail(msg) {
  console.error("ENFORCEMENT FAILURE:", msg);
  console.error("APPLICABLE RULES VIOLATED:");
  console.error("  - RULE 0: Emission gate - partial compliance detected");
  console.error("  - RULE 1: Full artifact emission - incomplete files");
  console.error("  - RULE 2: No partial compliance - request not 100% satisfied");
  process.exit(1);
}

/*
RULE 2 (No Partial Compliance): Retry instead of aborting on empty output
RULE 15 (Zero-Hang Guarantee): Use exponential backoff, not immediate abort
*/
function sleep(ms) {
  return new Promise(r => setTimeout(r, ms));
}

/*
RULE 1 (Full Artifact Emission): Extract exactly two complete code blocks
RULE 6 (Known-Working Code Only): Validate code blocks are non-empty
RULE 11 (No Placeholders): Ensure no TODOs or ellipses in code
*/
function extractBlocks(text) {
  // Match fenced code blocks with optional language identifier
  const matches = [...text.matchAll(/```(?:[a-z]*)?\n([\s\S]*?)```/g)];

  if (matches.length !== 2) {
    fail(`Expected exactly 2 code blocks, got ${matches.length}. RULE 1 violation: Full artifact emission required.`);
  }

  const blocks = matches.map(m => m[1]);

  // RULE 11: Check for placeholders
  blocks.forEach((block, idx) => {
    if (block.includes("TODO") || block.includes("...") || block.includes("FIXME")) {
      fail(`Code block ${idx + 1} contains placeholders (TODO/FIXME/...). RULE 11 violation: No placeholders allowed.`);
    }
    if (block.trim().length === 0) {
      fail(`Code block ${idx + 1} is empty. RULE 1 violation: Full artifact emission required.`);
    }
  });

  return blocks;
}

/*
RULE 1 (Full Artifact Emission): Validate exact headers are present
RULE 6 (Known-Working Code Only): Ensure files follow documented patterns
*/
function validateHeaders(blocks) {
  // File 1 must be instrument-closing-promise.js
  if (!blocks[0].startsWith("// instrument-closing-promise.js")) {
    fail("First file missing required header: '// instrument-closing-promise.js'. RULE 1 violation.");
  }

  // File 2 must be launch-instrumented-augment.sh
  if (!blocks[1].startsWith("# launch-instrumented-augment.sh")) {
    fail("Second file missing required header: '# launch-instrumented-augment.sh'. RULE 1 violation.");
  }

  console.log("✅ Headers validated - RULE 1 compliance confirmed");
}

/*
RULE 8 (Process Output Capture): Write files to disk for execution
RULE 13 (Self-Audit): Verify files written successfully before proceeding
*/
function writeFiles(blocks) {
  try {
    fs.writeFileSync("instrument-closing-promise.js", blocks[0]);
    fs.writeFileSync("launch-instrumented-augment.sh", blocks[1]);
    fs.chmodSync("launch-instrumented-augment.sh", 0o755);

    console.log("✅ Files written to disk:");
    console.log("   - instrument-closing-promise.js");
    console.log("   - launch-instrumented-augment.sh (executable)");
  } catch (err) {
    fail(`Failed to write files: ${err.message}. RULE 13 violation: Cannot proceed without verified artifacts.`);
  }
}

/*
RULE 8 (Process Output Capture): Execute launcher with wait=true equivalent
RULE 9 (Mandatory Output Reading): Capture output for verification
RULE 22 (Terminal Hygiene): Use timeout to prevent runaway processes
*/
function runLauncher() {
  console.log("Executing launcher script...");

  // spawnSync is equivalent to wait=true - blocks until completion
  const result = spawnSync("./launch-instrumented-augment.sh", {
    stdio: "inherit",  // Show output in terminal (user-visible)
    timeout: 20000     // 20 second timeout (RULE 22: prevent runaway processes)
  });

  if (result.error) {
    console.warn(`⚠️  Launcher execution error: ${result.error.message}`);
    console.warn("   This may be expected if instrumentation is still initializing");
  }

  return result;
}

/*
RULE 7 (Evidence Before Assertion): Verify log file exists and contains required data
RULE 9 (Mandatory Output Reading): Read log file and validate content
RULE 15 (Zero-Hang Guarantee): Return boolean, don't abort - allow retry
*/
function verifyLog() {
  // Check log file exists
  if (!fs.existsSync(LOG_PATH)) {
    console.warn(`⚠️  Log file not found: ${LOG_PATH}`);
    console.warn("   RULE 7 violation: No evidence of instrumentation execution");
    return false;
  }

  // Read log content
  const content = fs.readFileSync(LOG_PATH, "utf8");

  // Check log is non-empty
  if (!content || content.trim() === "") {
    console.warn(`⚠️  Log file is empty: ${LOG_PATH}`);
    console.warn("   RULE 7 violation: No evidence captured");
    return false;
  }

  // Check log contains required markers
  if (!content.includes("_closingPromise")) {
    console.warn(`⚠️  Log missing '_closingPromise' marker`);
    console.warn("   RULE 7 violation: Instrumentation did not capture target property");
    return false;
  }

  if (!content.includes("STACK TRACE")) {
    console.warn(`⚠️  Log missing 'STACK TRACE' marker`);
    console.warn("   RULE 7 violation: No stack trace evidence captured");
    return false;
  }

  // All checks passed
  console.log("✅ Log verification passed:");
  console.log(`   - File exists: ${LOG_PATH}`);
  console.log(`   - Content length: ${content.length} bytes`);
  console.log(`   - Contains '_closingPromise': YES`);
  console.log(`   - Contains 'STACK TRACE': YES`);
  console.log("   RULE 7 compliance: Evidence before assertion confirmed");

  return true;
}

/*
RULE 2 (No Partial Compliance): RETRY instead of aborting on empty output
RULE 15 (Zero-Hang Guarantee): Use exponential backoff, max retries
RULE 9 (Mandatory Output Reading): Verify log output after each attempt
*/
async function executeWithRetries() {
  for (let attempt = 1; attempt <= MAX_RETRIES; attempt++) {
    console.log(`\n========================================`);
    console.log(`Attempt ${attempt}/${MAX_RETRIES}`);
    console.log(`========================================`);

    // Clean up previous log file (RULE 13: Start with clean state)
    if (fs.existsSync(LOG_PATH)) {
      fs.unlinkSync(LOG_PATH);
      console.log(`🗑️  Removed previous log file`);
    }

    // Execute launcher (RULE 8: Process output capture)
    runLauncher();

    // Verify log output (RULE 9: Mandatory output reading)
    if (verifyLog()) {
      console.log("\n✅ INSTRUMENTATION VERIFIED - COMPLIANCE ACHIEVED");
      console.log("   RULE 2: Full request compliance confirmed");
      console.log("   RULE 7: Evidence before assertion satisfied");
      console.log("   RULE 9: Mandatory output reading completed");
      return;
    }

    // Verification failed - retry with backoff (RULE 2: No partial compliance)
    if (attempt < MAX_RETRIES) {
      const backoffTime = BACKOFF_MS * attempt;
      console.warn(`\n⚠️  Empty or invalid output detected`);
      console.warn(`   RULE 2: Retrying instead of aborting (attempt ${attempt}/${MAX_RETRIES})`);
      console.warn(`   RULE 15: Exponential backoff - waiting ${backoffTime}ms before retry`);
      await sleep(backoffTime);
    }
  }

  // All retries exhausted - now we can fail
  fail(`Exceeded maximum retries (${MAX_RETRIES}) without valid instrumentation. RULE 2 violation: Request not 100% satisfied.`);
}

// MAIN EXECUTION
if (require.main === module) {
  console.log("RETRY-ENFORCING COMPLIANCE DRIVER");
  console.log("=================================\n");

  // Read input from stdin (Augment's response)
  const input = fs.readFileSync(0, "utf8");

  // RULE 9: Check for empty <output> block at transport layer
  if (!input || input.trim() === "") {
    fail("Empty <output> block detected at transport layer. RULE 9 violation: Mandatory output reading failed.");
  }

  console.log(`📥 Received input: ${input.length} bytes`);

  // RULE 1: Extract exactly two code blocks
  const blocks = extractBlocks(input);

  // RULE 1: Validate headers
  validateHeaders(blocks);

  // RULE 8: Write files to disk
  writeFiles(blocks);

  // RULE 2: Execute with retries (not immediate abort)
  executeWithRetries().catch(err => {
    fail(`Execution failed: ${err.message}`);
  });
}


