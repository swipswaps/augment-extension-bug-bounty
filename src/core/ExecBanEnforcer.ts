/**
 * EXEC BAN ENFORCER
 *
 * PURPOSE:
 * Hard-prevent use of child_process.exec / execSync at runtime.
 *
 * RATIONALE:
 * Node.js documentation:
 *   https://nodejs.org/api/child_process.html
 *
 * exec() buffers entire output in memory and is unsafe for large output.
 * spawn() streams and is deterministic.
 *
 * This file monkey-patches forbidden APIs at activation time.
 *
 * ANY ATTEMPT TO USE exec OR execSync WILL THROW IMMEDIATELY.
 *
 * AUGMENT DIRECTIVE:
 *   DO NOT attempt to reintroduce exec via dynamic require().
 *   DO NOT alias exec under another name.
 *   DO NOT use spawnSync either.
 */

import * as child_process from "child_process";

export class ExecBanEnforcer {

    public static enforce(): void {

        const forbidden = [
            "exec",
            "execSync",
            "spawnSync"
        ];

        for (const method of forbidden) {

            const original = (child_process as any)[method];

            Object.defineProperty(child_process, method, {
                value: function () {
                    throw new Error(
                        `FORBIDDEN API DETECTED: child_process.${method}()\n` +
                        `Use spawn() with streaming instead.`
                    );
                }
            });

            // Preserve reference for debugging visibility
            (child_process as any)[`__original_${method}`] = original;
        }
    }
}

