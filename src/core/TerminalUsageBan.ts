// FILE: src/core/TerminalUsageBan.ts
//
// PURPOSE:
// Detect if extension tries to run verification commands
// via vscode.window.createTerminal or terminal.sendText.
//
// If verification phase attempts to use terminal,
// throw compliance failure.
//

import * as vscode from "vscode";

export class TerminalUsageBan {

    static enforceVerificationPhase() {

        const originalCreate = vscode.window.createTerminal;

        vscode.window.createTerminal = function() {
            throw new Error(
                "Terminal usage forbidden during compliance verification."
            );
        };

        return () => {
            vscode.window.createTerminal = originalCreate;
        };
    }
}

