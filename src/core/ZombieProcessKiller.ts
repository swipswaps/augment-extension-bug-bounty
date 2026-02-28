// FILE: src/core/ZombieProcessKiller.ts
// PURPOSE: Prevent leftover processes after host reloads.

import { spawn } from "child_process";

export class ZombieProcessKiller {
    static async killPattern(pattern: string): Promise<void> {
        // kill processes matching pattern
        await new Promise<void>((resolve) => {
            const killer = spawn(`pkill -f "${pattern}" || true`, {
                shell: true
            });
            killer.on("close", () => resolve());
        });
    }

    static async killPort(port: number): Promise<void> {
        await new Promise<void>((resolve) => {
            const killer = spawn(`fuser -k ${port}/tcp || true`, {
                shell: true
            });
            killer.on("close", () => resolve());
        });
    }
}

