import { DeterministicRunner } from "./DeterministicRunner";

export class StateVerifier {

    static async verifyNodeRunning(): Promise<void> {
        await DeterministicRunner.run("ps aux | grep node");
    }

    static async verifyPort(port: number): Promise<void> {
        await DeterministicRunner.run(`ss -tulpn | grep :${port}`);
    }

    static async verifyFile(file: string): Promise<void> {
        await DeterministicRunner.run(`ls -lah ${file}`);
    }
}

