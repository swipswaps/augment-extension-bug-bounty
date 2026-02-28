/**
 * EXEC BAN ENFORCER (UPDATED)
 *
 * PURPOSE:
 * - Prevent hidden terminal truncation issues.
 * - Ensure Augment Code requests compliance programmatically.
 *
 * USAGE:
 *   import { ExecBanEnforcer } from './core/ExecBanEnforcer';
 *   ExecBanEnforcer.enforce();
 *
 * AUGMENT DIRECTIVE:
 *   - Any attempt to reintroduce exec is an immediate runtime error.
 *   - All output must stream via spawn().
 */

import * as child_process from "child_process";

export class ExecBanEnforcer {

    public static enforce(): void {
        const forbidden = ["exec", "execSync", "spawnSync"];
        for (const method of forbidden) {

            const original = (child_process as any)[method];

            Object.defineProperty(child_process, method, {
                value: function () {
                    throw new Error(
                        `FORBIDDEN API DETECTED: child_process.${method}()\n` +
                        `Replace with spawn() streaming for deterministic output.`
                    );
                }
            });

            (child_process as any)[`__original_${method}`] = original;
        }

        console.log("ExecBanEnforcer: All forbidden child_process methods patched.");
    }
}