/**
 * FULL COMPLIANCE RUNNER
 *
 * PURPOSE:
 * - Compile TypeScript deterministically.
 * - Inspect output artifacts for any forbidden exec() calls.
 * - Enforce compliance programmatically, no shell pipelines.
 *
 * AUGMENT DIRECTIVE:
 *   - Must return Promise<void>.
 *   - Must be used in VS Code activate() for deterministic verification.
 */

import * as ts from "typescript";
import * as fs from "fs";
import * as path from "path";

export class FullComplianceRun {

    /**
     * Execute full compliance for a given project root.
     */
    public static async execute(projectRoot: string): Promise<void> {

        // 1. Compile TS programmatically
        const configPath = ts.findConfigFile(projectRoot, ts.sys.fileExists, "tsconfig.json");
        if (!configPath) throw new Error("tsconfig.json not found");

        const { config, error } = ts.readConfigFile(configPath, ts.sys.readFile);
        if (error) throw new Error("tsconfig.json read error");

        const parsed = ts.parseJsonConfigFileContent(config, ts.sys, path.dirname(configPath));

        const program = ts.createProgram(parsed.fileNames, parsed.options);
        const emitResult = program.emit();

        const allDiagnostics = ts.getPreEmitDiagnostics(program).concat(emitResult.diagnostics);
        if (allDiagnostics.length > 0) {
            const messages = allDiagnostics.map(d => d.messageText.toString()).join("\n");
            throw new Error(`Compilation errors:\n${messages}`);
        }

        console.log("FullComplianceRun: Compilation successful.");

        // 2. Inspect all output JS files for exec() usage
        const outDir = parsed.options.outDir || projectRoot;
        FullComplianceRun.verifyNoExec(outDir);
    }

    /**
     * Scan compiled artifacts and throw if exec() is found
     */
    public static verifyNoExec(dir: string): void {
        const files = fs.readdirSync(dir);
        for (const f of files) {
            const full = path.join(dir, f);
            const stat = fs.statSync(full);
            if (stat.isDirectory()) FullComplianceRun.verifyNoExec(full);
            else if (f.endsWith(".js")) {
                const content = fs.readFileSync(full, "utf8");
                if (content.includes("exec(") || content.includes("execSync(") || content.includes("spawnSync(")) {
                    throw new Error(`COMPLIANCE FAILURE: Forbidden exec() call detected in ${full}`);
                }
            }
        }
        console.log(`FullComplianceRun: No forbidden exec() calls in ${dir}`);
    }
}

