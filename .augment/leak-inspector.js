#!/usr/bin/env node
/***************************************************************************************************
TITLE:
VS Code Extension Host Network Leak Inspector

PURPOSE:
- Log + tee troubleshooting data to console AND file
- Inspect active TCP sockets for a target process (extension host)
- Show undici pool state (if instrumented in-process)
- Help confirm whether leak is:
      A) Undici pooled sockets not being reclaimed
      B) Raw TCP sockets accumulating outside pooling

USAGE:
1) Find extension host PID:
     ps aux | grep -- '--extensionHost'
   OR inside VS Code:
     Developer: Show Running Extensions

2) Run:
     node leak-inspector.js <PID>

3) Let it run while FD growth occurs.

NOTES:
- Designed for Linux (/proc based inspection)
- Does NOT modify target process
- Undici pool state requires in-process hook (see Section 7)

***************************************************************************************************/

const fs = require("fs");
const path = require("path");

if (process.argv.length < 3) {
    console.error("Usage: node leak-inspector.js <extension-host-pid>");
    process.exit(1);
}

const TARGET_PID = process.argv[2];
const LOG_FILE = `leak-inspector-${TARGET_PID}.log`;
const SAMPLE_INTERVAL_MS = 5000;



/***************************************************************************************************
SECTION 1 — TEE LOGGER

Logs to console AND file.
***************************************************************************************************/

function log(...args) {
    const line =
        `[${new Date().toISOString()}] ` +
        args.map(a =>
            typeof a === "object"
                ? JSON.stringify(a, null, 2)
                : String(a)
        ).join(" ");

    console.log(line);
    fs.appendFileSync(LOG_FILE, line + "\n");
}



/***************************************************************************************************
SECTION 2 — BASIC FD COUNT

Counts total open file descriptors.
***************************************************************************************************/

function getFdCount(pid) {
    try {
        return fs.readdirSync(`/proc/${pid}/fd`).length;
    } catch {
        return -1;
    }
}



/***************************************************************************************************
SECTION 3 — ACTIVE TCP SOCKET INSPECTION

Determines:
- How many TCP sockets exist
- Which are ESTABLISHED
- Whether they are accumulating

Uses:
    /proc/<pid>/fd
    /proc/net/tcp
***************************************************************************************************/

function getSocketInodes(pid) {
    const fdDir = `/proc/${pid}/fd`;
    const inodes = [];

    try {
        const fds = fs.readdirSync(fdDir);

        for (const fd of fds) {
            const fdPath = path.join(fdDir, fd);
            try {
                const link = fs.readlinkSync(fdPath);
                const match = link.match(/^socket:\[(\d+)\]$/);
                if (match) {
                    inodes.push(match[1]);
                }
            } catch {}
        }
    } catch {}

    return inodes;
}

function getTcpConnectionsForInodes(inodes) {
    const tcpFile = fs.readFileSync("/proc/net/tcp", "utf8");
    const lines = tcpFile.split("\n").slice(1);

    const results = [];

    for (const line of lines) {
        const cols = line.trim().split(/\s+/);
        if (cols.length < 10) continue;

        const inode = cols[9];
        if (inodes.includes(inode)) {
            const stateHex = cols[3];
            const state = parseInt(stateHex, 16);

            results.push({
                inode,
                state
            });
        }
    }

    return results;
}



/***************************************************************************************************
SECTION 4 — TCP STATE DECODER

Linux TCP states:
01 = ESTABLISHED
02 = SYN_SENT
03 = SYN_RECV
04 = FIN_WAIT1
05 = FIN_WAIT2
06 = TIME_WAIT
07 = CLOSE
08 = CLOSE_WAIT
09 = LAST_ACK
0A = LISTEN
0B = CLOSING
***************************************************************************************************/

const TCP_STATES = {
    1: "ESTABLISHED",
    2: "SYN_SENT",
    3: "SYN_RECV",
    4: "FIN_WAIT1",
    5: "FIN_WAIT2",
    6: "TIME_WAIT",
    7: "CLOSE",
    8: "CLOSE_WAIT",
    9: "LAST_ACK",
    10: "LISTEN",
    11: "CLOSING"
};



/***************************************************************************************************
SECTION 5 — RAW SOCKET LEAK DETECTION

Logic:
If TCP ESTABLISHED sockets increase monotonically,
AND FD count increases,
THEN raw sockets likely leaking.

If TCP count stable but FD grows,
THEN leak may be pipes/IPC or non-network descriptors.

***************************************************************************************************/

let baselineFd = getFdCount(TARGET_PID);
let baselineTcpCount = 0;

function sample() {
    const fdCount = getFdCount(TARGET_PID);
    const socketInodes = getSocketInodes(TARGET_PID);
    const tcpConns = getTcpConnectionsForInodes(socketInodes);

    const stateCounts = {};
    for (const conn of tcpConns) {
        const stateName = TCP_STATES[conn.state] || `STATE_${conn.state}`;
        stateCounts[stateName] = (stateCounts[stateName] || 0) + 1;
    }

    const tcpCount = tcpConns.length;

    if (!baselineTcpCount) baselineTcpCount = tcpCount;

    log("FD_COUNT:", fdCount,
        "FD_DELTA:", fdCount - baselineFd);

    log("TCP_TOTAL:", tcpCount,
        "TCP_DELTA:", tcpCount - baselineTcpCount);

    log("TCP_STATES:", stateCounts);

    log("--------------------------------------------------");
}



/***************************************************************************************************
SECTION 6 — UNDICI POOL STATE (OUT-OF-PROCESS LIMITATION)

IMPORTANT:
Undici pool state CANNOT be inspected from outside the process.

To inspect pooling vs raw socket leak:

You must inject this inside the extension host:

    const { getGlobalDispatcher } = require("undici");
    const dispatcher = getGlobalDispatcher();
    console.log(dispatcher);

If using Pool:
    pool.stats

Without in-process access,
we infer pooling behavior heuristically:

HEURISTIC:
- If TCP ESTABLISHED count remains low (e.g., < 20)
  but FD count grows massively,
  then pooling is likely NOT the issue.

- If TCP ESTABLISHED grows proportionally with FD count,
  then sockets are not being returned to pool.

This script logs TCP growth for that inference.

***************************************************************************************************/



/***************************************************************************************************
SECTION 7 — OPTIONAL IN-PROCESS UNDICI PROBE (MANUAL INSERTION REQUIRED)

Insert into extension host (temporary):

    const { getGlobalDispatcher } = require("undici");
    setInterval(() => {
        const d = getGlobalDispatcher();
        if (d && d.stats) {
            console.log("UNDICI_STATS", d.stats);
        }
    }, 5000);

If:
    pending > 0 and grows
    connected grows
Then pooling leak.

If:
    stats stable but TCP grows
Then raw sockets outside pool.

***************************************************************************************************/



/***************************************************************************************************
SECTION 8 — MAIN LOOP

Runs continuously.
***************************************************************************************************/

log("Starting leak inspector for PID", TARGET_PID);
log("Logging to", LOG_FILE);

setInterval(sample, SAMPLE_INTERVAL_MS);
sample();



/***************************************************************************************************
INTERPRETING RESULTS:

CASE A — TCP ESTABLISHED grows steadily with FD:
    Likely sockets not being returned to undici pool.
    → Incomplete response.body.cancel() or iterator.return()

CASE B — TCP small but FD huge:
    Likely IPC pipe leak or webview reload churn.

CASE C — TCP mostly TIME_WAIT:
    Likely rapid reconnect storm (timeout → retry).

CASE D — TCP stable after disabling stream:
    Confirms stream as primary driver.

***************************************************************************************************/

