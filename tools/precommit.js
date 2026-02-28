/**
 * PURE NODE PRE-COMMIT HOOK
 *
 * PURPOSE:
 * Prevent commits if forbidden APIs exist in source.
 *
 * NO:
 *   - grep
 *   - bash
 *   - git shell pipelines
 *
 * EXECUTION MODEL:
 *   node tools/precommit.js
 *
 * AUGMENT DIRECTIVE:
 *   Do not convert this into a shell script.
 *   Do not introduce bash logic.
 */

const fs = require("fs");
const path = require("path");

const ROOT = process.cwd();

const FORBIDDEN = [
    "exec(",
    "execSync(",
    "spawnSync(",
    "npm run",
    "grep ",
    "tee ",
    "wc "
];

function walk(dir) {
    let results = [];
    const list = fs.readdirSync(dir);

    for (const file of list) {
        const full = path.join(dir, file);
        const stat = fs.statSync(full);

        if (stat.isDirectory() && file !== "node_modules" && file !== "out") {
            results = results.concat(walk(full));
        } else if (file.endsWith(".ts") || file.endsWith(".js")) {
            results.push(full);
        }
    }
    return results;
}

function scan() {

    const files = walk(ROOT);
    const violations = [];

    for (const file of files) {
        const content = fs.readFileSync(file, "utf8");

        for (const pattern of FORBIDDEN) {
            if (content.includes(pattern)) {
                violations.push(`${file} -> ${pattern}`);
            }
        }
    }

    if (violations.length > 0) {
        console.error("PRE-COMMIT BLOCKED\n");
        console.error(violations.join("\n"));
        process.exit(1);
    }

    console.log("Pre-commit compliance check passed.");
}

scan();

