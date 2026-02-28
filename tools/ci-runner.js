/**
 * DETERMINISTIC CI RUNNER
 *
 * PURPOSE:
 * Replace:
 *   npm run build
 *   npm run test
 *   grep verification
 *
 * WITH:
 *   Programmatic compilation + verification
 *
 * NO:
 *   - bash
 *   - npm scripts
 *   - shell pipelines
 *
 * AUGMENT DIRECTIVE:
 *   CI must execute:
 *      node tools/ci-runner.js
 */

const path = require("path");
const { FullComplianceRun } = require("../out/core/FullComplianceRun");

(async () => {

    try {

        const projectRoot = path.resolve(__dirname, "..");

        console.log("=== CI START ===");

        await FullComplianceRun.execute(projectRoot);

        console.log("=== CI SUCCESS ===");

        process.exit(0);

    } catch (err) {

        console.error("=== CI FAILURE ===");
        console.error(err.message);
        process.exit(1);
    }

})();

