// FILE: src/commands/ComplianceReport.ts
//
// PURPOSE:
// Produce deterministic compliance proof.
// Must be run before declaring success.

import * as fs from "fs";
import { StructuredLogger } from "../core/StructuredLogger";

export function generateComplianceReport() {

    const logPath = StructuredLogger.getLogFilePath();

    const lastLines = fs
        .readFileSync(logPath, "utf8")
        .split("\n")
        .slice(-20)
        .join("\n");

    console.log("=== COMPLIANCE REPORT ===");
    console.log("Log file:", logPath);
    console.log("Last 20 lines:");
    console.log(lastLines);
}

