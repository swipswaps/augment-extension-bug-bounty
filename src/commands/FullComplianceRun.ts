/**
 * FULL COMPLIANCE RUNNER
 *
 * PURPOSE:
 * Enforces deterministic, shell-free compliance across the extension.
 *
 * ARCHITECTURAL GUARANTEES:
 *  - NO child_process.exec()
 *  - NO terminal shell pipelines
 *  - NO interactive compilation
 *  - NO environment-coupled grep/wc/tee
 *  - FULL programmatic verification
 *
 * REFERENCES:
 *  - Node.js child_process documentation:
 *      https://nodejs.org/api/child_process.html
 *      exec() buffers and is unsafe for large output.
 *      spawn() is streaming and deterministic.
 *
 *  - TypeScript Compiler API:
 *      https://github.com/microsoft/TypeScript/wiki/Using-the-Compiler-API
 *
 *  - VS Code Extension Guidelines:
 *      https://code.visualstudio.com/api
 *
 * COMPLIANCE MODEL:
 *  STEP 1: Compile via TypeScript API
 *  STEP 2: Inspect compiled JS artifacts
 *  STEP 3: Reject forbidden APIs
 *  STEP 4: Emit structured verification report
 */

import * as ts from "typescript";
import * as fs from "fs";
import * as path from "path";

export class FullComplianceRun {

    public static async execute(projectRoot: string): Promise<void> {

        // ---------------------------------------------------------------------
        // STEP 1: PROGRAMMATIC TYPESCRIPT COMPILATION
        // ---------------------------------------------------------------------

        const configPath = ts.findConfigFile(
            projectRoot,
            ts.sys.fileExists,
            "tsconfig.json"
        );

        if (!configPath) {
            throw new Error("tsconfig.json not found");
        }

        const configFile = ts.readConfigFile(configPath, ts.sys.readFile);

        if (configFile.error) {
            throw new Error(
                ts.formatDiagnosticsWithColorAndContext(
                    [configFile.error],
                    {
                        getCurrentDirectory: ts.sys.getCurrentDirectory,
                        getCanonicalFileName: f => f,
                        getNewLine: () => ts.sys.newLine
                    }
                )
            );
        }

        const parsed = ts.parseJsonConfigFileContent(
            configFile.config,
            ts.sys,
            projectRoot
        );

        const program = ts.createProgram(
            parsed.fileNames,
            parsed.options
        );

        const emitResult = program.emit();

        const diagnostics = ts.getPreEmitDiagnostics(program)
            .concat(emitResult.diagnostics);

        if (diagnostics.length > 0) {
            const formatted = ts.formatDiagnosticsWithColorAndContext(
                diagnostics,
                {
                    getCurrentDirectory: ts.sys.getCurrentDirectory,
                    getCanonicalFileName: f => f,
                    getNewLine: () => ts.sys.newLine
                }
            );

            throw new Error("Compilation failed:\n" + formatted);
        }

        // ---------------------------------------------------------------------
        // STEP 2: VERIFY NO FORBIDDEN RUNTIME APIS
        // ---------------------------------------------------------------------

        const outDir = parsed.options.outDir || "out";
        const absoluteOut = path.join(projectRoot, outDir);

        if (!fs.existsSync(absoluteOut)) {
            throw new Error("Compiled output directory not found: " + absoluteOut);
        }

        const forbiddenPatterns = [
            "exec(",
            "execSync(",
            "spawnSync(",
            "npm run",
            "grep ",
            "tee ",
            "wc "
        ];

        const violations: string[] = [];

        const files = this.walk(absoluteOut);

        for (const file of files) {

            if (!file.endsWith(".js")) continue;

            const content = fs.readFileSync(file, "utf8");

            for (const pattern of forbiddenPatterns) {
                if (content.includes(pattern)) {
                    violations.push(`${file} -> contains forbidden pattern: ${pattern}`);
                }
            }
        }

        if (violations.length > 0) {

            throw new Error(
                "COMPLIANCE FAILURE:\n\n" +
                violations.join("\n")
            );
        }

        // ---------------------------------------------------------------------
        // STEP 3: STRUCTURED SUCCESS REPORT
        // ---------------------------------------------------------------------

        const report = {
            timestamp: new Date().toISOString(),
            projectRoot,
            compiled: true,
            forbiddenApiDetected: false,
            filesScanned: files.length
        };

        console.log(
            JSON.stringify(report, null, 2)
        );
    }

    /**
     * Recursive directory walker.
     * Deterministic. No shell. No globbing.
     */
    private static walk(dir: string): string[] {

        let results: string[] = [];

        const list = fs.readdirSync(dir);

        for (const file of list) {

            const full = path.join(dir, file);
            const stat = fs.statSync(full);

            if (stat && stat.isDirectory()) {
                results = results.concat(this.walk(full));
            } else {
                results.push(full);
            }
        }

        return results;
    }
}

