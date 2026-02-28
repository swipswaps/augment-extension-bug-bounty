// FILE: src/core/StructuredLogger.ts
//
// PURPOSE:
// Deterministic logging without shell tee pipelines.
// Avoids blocking and terminal buffering.
//
// WHY:
// tee relies on shell and interactive pipelines.
// That causes blocking in VS Code integrated terminals.

import * as fs from "fs";

export class StructuredLogger {

    private static logFile = `.augment-structured-${Date.now()}.log`;

    static log(message: string) {

        const line = `[${new Date().toISOString()}] ${message}\n`;

        process.stdout.write(line);
        fs.appendFileSync(this.logFile, line);
    }

    static getLogFilePath(): string {
        return this.logFile;
    }
}

