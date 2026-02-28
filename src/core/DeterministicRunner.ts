// FILE: src/core/DeterministicRunner.ts
// PURPOSE: Deterministic live streaming runner.
// NEVER use exec() or execFile() anywhere else in the extension.

import { spawn } from "child_process";
import * as fs from "fs";
import * as path from "path";

/**
 * A deterministic runner that:
 * - streams stdout & stderr in real time
 * - logs everything to a log file (tee)
 * - visible output to user terminal
 * - rejects only on non-zero exit
 */
export class DeterministicRunner {

    static run(command: string, logPath?: string): Promise<void> {
        // Default log file per invocation
        const logFile =
            logPath ||
            path.join(process.cwd(), `.augment-run-${Date.now()}.log`);

        // Ensure log exists
        fs.writeFileSync(logFile, `\n=== COMMAND START: ${command}\n`);

        return new Promise((resolve, reject) => {
            // Use spawn for streaming
            const child = spawn(command, { shell: true });

            // Stream stdout
            child.stdout.on("data", (chunk) => {
                const text = chunk.toString();
                process.stdout.write(text);                // visible
                fs.appendFileSync(logFile, text);          // logged
            });

            // Stream stderr
            child.stderr.on("data", (chunk) => {
                const text = chunk.toString();
                process.stderr.write(text);
                fs.appendFileSync(logFile, text);
            });

            // On exit
            child.on("close", (code) => {
                fs.appendFileSync(
                    logFile,
                    `\n=== COMMAND EXIT CODE: ${code}\n`
                );
                if (code === 0) {
                    resolve();
                } else {
                    reject(new Error(`Exit code ${code}`));
                }
            });

            child.on("error", (err) => {
                fs.appendFileSync(logFile, `\n=== SPAWN ERROR: ${err}\n`);
                reject(err);
            });
        });
    }
}

