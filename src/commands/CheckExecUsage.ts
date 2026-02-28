// FILE: src/commands/CheckExecUsage.ts
//
// PURPOSE:
// Deterministically check for exec() usage without spawning terminal processes.

import { CodeInspector } from "../core/CodeInspector";

export async function checkExecUsage(filePath: string) {

    const count = CodeInspector.findExecOccurrences(filePath);

    console.log(`Total exec() occurrences: ${count}`);

    CodeInspector.reportExecOccurrences(filePath);

    if (count > 0) {
        throw new Error("exec() usage detected. Refactor required.");
    }
}

