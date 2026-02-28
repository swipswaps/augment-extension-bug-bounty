// FILE: src/core/ProgrammaticCompiler.ts
//
// PURPOSE:
// Eliminate shell-based compilation (`npm run compile`).
// Use Node child_process.spawn directly.
// No shell chaining.
// No &&
// No 2>&1
// No redirection.
// No grep.
// Deterministic streaming only.
//
// WHY:
// Shell pipelines inside VS Code integrated terminal cause:
// - interactive blocking
// - cancellation artifacts
// - hidden terminal buffering
// - "Waiting for user input"
// - truncated output
//
// This implementation:
// - streams stdout/stderr live
// - logs deterministically
// - fails explicitly on non-zero exit
//

import { spawn } from "child_process";
import * as path from "path";
import * as fs from "fs";

export class ProgrammaticCompiler {

    static compile(workspaceRoot: string): Promise<void> {

        const logFile = path.join(
            workspaceRoot,
            `.compile-log-${Date.now()}.log`
        );

        fs.writeFileSync(logFile, "=== PROGRAMMATIC COMPILE START ===\n");

        return new Promise((resolve, reject) => {

            const npm = spawn(
                process.platform === "win32" ? "npm.cmd" : "npm",
                ["run", "compile"],
                {
                    cwd: workspaceRoot,
                    stdio: ["ignore", "pipe", "pipe"]
                }
            );

            npm.stdout.on("data", (chunk) => {
                const text = chunk.toString();
                process.stdout.write(text);
                fs.appendFileSync(logFile, text);
            });

            npm.stderr.on("data", (chunk) => {
                const text = chunk.toString();
                process.stderr.write(text);
                fs.appendFileSync(logFile, text);
            });

            npm.on("close", (code) => {
                fs.appendFileSync(
                    logFile,
                    `\n=== COMPILE EXIT CODE: ${code} ===\n`
                );

                if (code === 0) {
                    resolve();
                } else {
                    reject(new Error(`Compile failed: ${code}`));
                }
            });

            npm.on("error", reject);
        });
    }
}

