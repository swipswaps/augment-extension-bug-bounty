// FILE: src/core/CompiledArtifactInspector.ts
//
// PURPOSE:
// Verify compiled JS output does not contain exec().
// This replaces shell grep entirely.
//
// WHY:
// Shell grep introduces pipelines and blocking.
// We must inspect file content directly.
//

import * as fs from "fs";
import * as path from "path";

export class CompiledArtifactInspector {

    static verifyNoExec(workspaceRoot: string): void {

        const outDir = path.join(workspaceRoot, "out");

        function scan(dir: string) {

            const entries = fs.readdirSync(dir);

            for (const entry of entries) {

                const full = path.join(dir, entry);
                const stat = fs.statSync(full);

                if (stat.isDirectory()) {
                    scan(full);
                } else if (full.endsWith(".js")) {

                    const content = fs.readFileSync(full, "utf8");

                    if (content.includes("exec(")) {
                        throw new Error(
                            `COMPILED OUTPUT CONTAINS exec(): ${full}`
                        );
                    }
                }
            }
        }

        scan(outDir);

        console.log("Compiled artifact verification passed.");
    }
}

