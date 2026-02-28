/**
 * CancellationGuard.ts
 *
 * Detects false cancellation artifacts such as:
 *   "Cancelled by user."
 *   empty output
 *   partial output
 */

export function isSpuriousCancellation(output: string): boolean {

    if (!output) return true;

    if (output.includes("Cancelled by user.")) return true;
    if (output.includes("tool call was cancelled")) return true;

    return false;
}

