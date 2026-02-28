// FILE: src/core/CodeInspector.ts
//
// PURPOSE:
// Replace shell-based grep pipelines with deterministic TypeScript scanning.
// This avoids interactive terminal blocking and buffering issues.

import * as fs from "fs";

export class CodeInspector {

    static findExecOccurrences(filePath: string): number {

        const content = fs.readFileSync(filePath, "utf8");

        const matches = content.match(/exec\(/g);

        return matches ? matches.length : 0;
    }

    static reportExecOccurrences(filePath: string) {

        const content = fs.readFileSync(filePath, "utf8");

        const lines = content.split("\n");

        lines.forEach((line, index) => {
            if (line.includes("exec(")) {
                console.log(
                    `exec() found at line ${index + 1}: ${line.trim()}`
                );
            }
        });
    }
}

