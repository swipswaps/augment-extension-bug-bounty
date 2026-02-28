/**
 * VisibleTerminal.ts
 *
 * Ensures:
 *  - No hidden terminals
 *  - Terminal always shown
 *  - Terminal reuse
 */

import * as vscode from "vscode";

export class VisibleTerminal {

    private static terminal: vscode.Terminal | null = null;

    static get(): vscode.Terminal {

        if (!this.terminal) {
            this.terminal = vscode.window.createTerminal({
                name: "Augment Deterministic Terminal",
                hideFromUser: false,      // CRITICAL: never hidden
                isTransient: false
            });
        }

        this.terminal.show(true); // force reveal
        return this.terminal;
    }

    static send(command: string) {
        const term = this.get();
        term.sendText(command, true);
    }
}

