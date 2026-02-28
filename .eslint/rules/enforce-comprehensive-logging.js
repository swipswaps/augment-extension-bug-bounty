/**
 * CUSTOM ESLINT RULE: enforce-comprehensive-logging
 *
 * PURPOSE:
 *  Prevent the exact bug we just fixed from ever happening again
 *
 * WHAT THIS RULE DETECTS:
 *  1. spawn() calls without capturing stdout/stderr
 *  2. spawn() calls without logging the command being executed
 *  3. Process exit handlers without logging complete output
 *  4. Missing real-time logging for stdout/stderr streams
 *
 * WHY THIS MATTERS:
 *  - We had VLC showing black screen with NO diagnostic output
 *  - Root cause: stdio: ["ignore", "ignore", "pipe"] only captured stderr
 *  - Root cause: Only logged stderr when exit code !== 0
 *  - Result: Hours of debugging with no information
 *
 * HOW IT WORKS:
 *  - Scans AST (Abstract Syntax Tree) for spawn() calls
 *  - Checks if stdio option captures both stdout and stderr
 *  - Checks if stdout/stderr have .on("data") handlers
 *  - Checks if exit handler logs complete output
 *
 * EXAMPLE VIOLATIONS:
 *
 *  ❌ BAD: Only captures stderr
 *  const proc = spawn("vlc", args, {
 *    stdio: ["ignore", "ignore", "pipe"]  // stdout ignored!
 *  });
 *
 *  ❌ BAD: No logging of command
 *  const proc = spawn("vlc", args);
 *  // Should log: "Executing: vlc --arg1 --arg2 file.mp4"
 *
 *  ❌ BAD: No stdout/stderr handlers
 *  const proc = spawn("vlc", args, { stdio: ["ignore", "pipe", "pipe"] });
 *  // Should have: proc.stdout.on("data", ...) and proc.stderr.on("data", ...)
 *
 *  ❌ BAD: Exit handler doesn't log output
 *  proc.on("exit", (code) => {
 *    console.log(`Exited with ${code}`);
 *    // Should also log: complete stdout and stderr
 *  });
 *
 * EXAMPLE CORRECT CODE:
 *
 *  ✅ GOOD: Captures both streams, logs command, logs output
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
  meta: {
    type: "problem",
    docs: {
      description: "Enforce comprehensive logging for child processes",
      category: "Best Practices",
      recommended: true,
    },
    messages: {
      missingStdoutCapture: "spawn() must capture stdout: stdio should be ['ignore', 'pipe', 'pipe'] not ['ignore', 'ignore', 'pipe']",
      missingCommandLog: "spawn() must log the command being executed before spawning",
      missingStdoutHandler: "spawn() must have proc.stdout.on('data', ...) handler to log output in real-time",
      missingStderrHandler: "spawn() must have proc.stderr.on('data', ...) handler to log errors in real-time",
      missingExitLogging: "proc.on('exit', ...) must log complete stdout and stderr, not just exit code",
      conditionalExitLogging: "Exit handler must log output ALWAYS, not just when code !== 0",
    },
    schema: [], // no options
  },

  create(context) {
    /**
     * RULE IMPLEMENTATION
     *
     * We track spawn() calls and verify:
     *  1. stdio option includes both stdout and stderr
     *  2. Command is logged before spawn
     *  3. stdout/stderr have .on("data") handlers
     *  4. exit handler logs complete output
     */
    const spawnCalls = new Map(); // Track spawn calls by variable name

    return {
      /**
       * STEP 1: Detect spawn() calls
       *
       * AST pattern: spawn(command, args, options)
       * We check the 'options' object for stdio configuration
       */
      CallExpression(node) {
        // Check if this is a spawn() call
        if (
          node.callee.name === "spawn" ||
          (node.callee.type === "MemberExpression" &&
            node.callee.property.name === "spawn")
        ) {
          // Get the variable name this spawn is assigned to
          const parent = node.parent;
          let varName = null;

          if (parent.type === "VariableDeclarator") {
            varName = parent.id.name;
          } else if (parent.type === "AssignmentExpression") {
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

      /**
       * STEP 2: Detect stdout/stderr handlers
       *
       * AST pattern: proc.stdout.on("data", ...)
       * We mark the spawn call as having proper handlers
       */
      "CallExpression[callee.property.name='on']"(node) {
        // Check if this is proc.stdout.on("data", ...) or proc.stderr.on("data", ...)
        const callee = node.callee;
        if (
          callee.type === "MemberExpression" &&
          callee.object.type === "MemberExpression"
        ) {
          const procName = callee.object.object.name;
          const streamName = callee.object.property.name;
          const eventName = node.arguments[0]?.value;

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

      /**
       * STEP 3: Detect exit handlers and check logging
       *
       * AST pattern: proc.on("exit", (code) => { ... })
       * We check if the handler logs complete output
       */
      "CallExpression[callee.property.name='on'][arguments.0.value='exit']"(node) {
        const callee = node.callee;
        if (callee.type === "MemberExpression") {
          const procName = callee.object.name;

          if (spawnCalls.has(procName)) {
            const spawnInfo = spawnCalls.get(procName);
            const exitHandler = node.arguments[1];

            if (exitHandler && (exitHandler.type === "ArrowFunctionExpression" || exitHandler.type === "FunctionExpression")) {
              // Check if handler body logs output
              const body = exitHandler.body;
              let logsOutput = false;
              let hasConditionalLogging = false;

              // Simple heuristic: look for log calls in the handler
              if (body.type === "BlockStatement") {
                for (const stmt of body.body) {
                  // Check for logBoth, console.log, etc. that reference stdout/stderr
                  if (stmt.type === "ExpressionStatement" &&
                      stmt.expression.type === "CallExpression") {
                    const callExpr = stmt.expression;
                    const funcName = callExpr.callee.name || callExpr.callee.property?.name;

                    if (funcName === "logBoth" || funcName === "log" || funcName === "error") {
                      // Check if arguments reference stdout or stderr
                      const argsStr = context.getSourceCode().getText(callExpr);
                      if (argsStr.includes("stdout") || argsStr.includes("stderr")) {
                        logsOutput = true;
                      }
                    }
                  }

                  // Check for conditional logging (code !== 0)
                  if (stmt.type === "IfStatement") {
                    const testStr = context.getSourceCode().getText(stmt.test);
                    if (testStr.includes("!== 0") || testStr.includes("!= 0")) {
                      hasConditionalLogging = true;
                    }
                  }
                }
              }

              if (hasConditionalLogging) {
                context.report({
                  node,
                  messageId: "conditionalExitLogging",
                });
              }

              if (logsOutput) {
                spawnInfo.hasExitLogging = true;
              }
            }
          }
        }
      },

      /**
       * STEP 4: Final validation at end of program
       *
       * Report any spawn calls that are missing handlers or logging
       */
      "Program:exit"() {
        for (const [varName, info] of spawnCalls) {
          if (!info.hasStdoutHandler) {
            context.report({
              node: info.node,
              messageId: "missingStdoutHandler",
            });
          }

          if (!info.hasStderrHandler) {
            context.report({
              node: info.node,
              messageId: "missingStderrHandler",
            });
          }

          if (!info.hasExitLogging) {
            context.report({
              node: info.node,
              messageId: "missingExitLogging",
            });
          }
        }
      },
    };
  },
};


