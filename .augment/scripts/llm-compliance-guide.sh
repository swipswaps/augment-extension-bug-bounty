#!/bin/bash
# ============================================================================
# WHAT: LLM Compliance Guide — generates RICH JSON diagnostics queue entries
# WHY:  Previous version wrote vague "[RULE_9_VIOLATION]" messages. The LLM reads
#       diagnostics via the `diagnostics` tool. If the message is just a label,
#       the LLM cannot troubleshoot. This script extracts VERBATIM data from:
#         - SQLite database (error_tracking.db): timestamps, error types, messages, stack traces
#         - Extension source (extension.js): actual code at the flagged offset
#       And writes JSON-per-line to the queue so the watchdog extension can create
#       RICH diagnostics with all fields visible via the `diagnostics` tool.
#
# HOW:  6 enumerated steps:
#   STEP 1: Verify extension installed + compiled with rich JSON parser
#   STEP 2: Query DB for ALL errors with stack traces
#   STEP 3: For each error, extract code snippet from extension.js at flagged offset
#   STEP 4: Build JSON queue entries with ALL fields populated
#   STEP 5: Add workspace-relative test diagnostic (always queryable)
#   STEP 6: Print diagnostics tool call for LLM to execute
#
# USER REQUEST (verbatim):
#   "verbatim human readable event, error, system and application relevant
#    messages and stack trace and line numbers and verbatim code snippets"
# ============================================================================

set -euo pipefail
LOGFILE=".notes/llm-compliance-$(date +%Y%m%d-%H%M%S).log"
QUEUE_FILE=".notes/vscode-diagnostics-queue.txt"
DB=".augment/error_tracking.db"

# WHAT: Helper to log to both stdout and logfile
tlog() { echo "$1" | tee -a "$LOGFILE"; }

tlog "========================================"
tlog "RICH DIAGNOSTICS GENERATOR — $(date -Iseconds)"
tlog "========================================"
tlog ""

# ──────────────────────────────────────────────────────────────────────────────
# STEP 1: Verify watchdog extension installed + compiled with JSON parser
# ──────────────────────────────────────────────────────────────────────────────
tlog "STEP 1: Verify watchdog extension"
tlog "-----------------------------------"

# WHAT: Find installed watchdog extension — publisher is prf-compliance per package.json
# WHY: Script was failing here because glob used wrong publisher "augment-code"
# HOW: Use || true to prevent pipefail exit on no-match; publisher from package.json
WATCHDOG_EXT=$(ls -d "$HOME/.vscode/extensions/prf-compliance.hidden-terminal-watchdog-"* 2>/dev/null | head -1 || true)
if [ -n "$WATCHDOG_EXT" ]; then
    tlog "  ✅ Installed: $(basename "$WATCHDOG_EXT")"
else
    tlog "  ❌ NOT installed — run force-package.sh first"
fi

# WHAT: Check compiled JS has the NEW parseJsonEntry function (not just old pipe parser)
# WHY: If only old parser compiled, JSON queue entries will be silently skipped
# HOW: grep -c returns count; || echo "0" prevents pipefail exit on no-match
JSON_PARSER_COUNT=$(grep -c "parseJsonEntry" hidden-terminal-watchdog/out/extension.js 2>/dev/null || echo "0")
RICH_MSG_COUNT=$(grep -c "buildRichMessage" hidden-terminal-watchdog/out/extension.js 2>/dev/null || echo "0")
tlog "  parseJsonEntry in compiled JS: ${JSON_PARSER_COUNT} refs"
tlog "  buildRichMessage in compiled JS: ${RICH_MSG_COUNT} refs"
if [ "$JSON_PARSER_COUNT" -gt 0 ] && [ "$RICH_MSG_COUNT" -gt 0 ]; then
    tlog "  ✅ Rich JSON parser compiled"
else
    tlog "  ❌ Rich parser NOT compiled — need: npm run compile + repackage + reinstall"
fi
tlog ""

# ──────────────────────────────────────────────────────────────────────────────
# STEP 2: Query database for ALL errors with stack traces
# ──────────────────────────────────────────────────────────────────────────────
tlog "STEP 2: Query database for evidence"
tlog "-------------------------------------"

TOTAL_ERRORS=$(sqlite3 "$DB" "SELECT COUNT(*) FROM errors;" 2>&1)
CANCELLED_ERRORS=$(sqlite3 "$DB" "SELECT COUNT(*) FROM errors WHERE error_type='Request cancelled';" 2>&1)
STACK_ERRORS=$(sqlite3 "$DB" "SELECT COUNT(*) FROM errors WHERE stack_trace IS NOT NULL AND stack_trace != '';" 2>&1)
tlog "  Total errors in DB: $TOTAL_ERRORS"
tlog "  Request cancelled:  $CANCELLED_ERRORS"
tlog "  With stack traces:  $STACK_ERRORS"

# WHAT: Get error type counts for each type
# WHY: Each unique error type becomes a separate diagnostic entry
tlog "  Error type breakdown:"
sqlite3 "$DB" "SELECT error_type, COUNT(*) as cnt FROM errors GROUP BY error_type ORDER BY cnt DESC;" 2>&1 | while IFS='|' read -r etype ecnt; do
    tlog "    $etype: $ecnt"
done
tlog ""

# ──────────────────────────────────────────────────────────────────────────────
# STEP 3: Extract stack trace locations and code snippets
# ──────────────────────────────────────────────────────────────────────────────
tlog "STEP 3: Extract locations and code from extension.js"
tlog "-----------------------------------------------------"

# WHAT: Auto-detect Augment extension directory
# WHY: Need actual extension.js path to extract code snippets
EXT_DIR=$(ls -d "$HOME/.vscode/extensions/augment.vscode-augment-"* 2>/dev/null | sort -V | tail -1)
EXT_JS=""
if [ -n "$EXT_DIR" ]; then
    EXT_JS="$EXT_DIR/out/extension.js"
    tlog "  Extension JS: $EXT_JS"
    if [ -f "$EXT_JS" ]; then
        tlog "  ✅ File exists ($(wc -c < "$EXT_JS") bytes)"
    else
        tlog "  ❌ File missing"
    fi
else
    tlog "  ❌ Augment extension not found"
fi
tlog ""

# ──────────────────────────────────────────────────────────────────────────────
# STEP 2b: Pre-compute known error locations in Augment extension.js
# ──────────────────────────────────────────────────────────────────────────────
# WHAT: Run ONE grep pass to find line numbers for all known error patterns
# WHY: DB has ZERO stack traces for 99% of errors. Without this, all entries
#       resolve to L1:1 on the queue script itself — completely useless.
#       By pre-computing offsets we can point each error type to the ACTUAL
#       code that generates it.
# HOW: grep -n for each pattern, extract first match line number, store in vars.
#       Then use these as fallback locations when stack_trace is empty.
LOC_CANCELLED_BY_USER=""
LOC_SENTRY_GETINSTANCE=""
LOC_CONNECT_TIMEOUT=""
LOC_INVALID_LINE_RANGE=""
LOC_CLIENT_METRICS=""
LOC_REQUEST_CANCELLED=""
if [ -n "$EXT_JS" ] && [ -f "$EXT_JS" ]; then
    LOC_CANCELLED_BY_USER=$(grep -n '_cancelledByUser' "$EXT_JS" 2>/dev/null | head -1 | cut -d: -f1 || true)
    LOC_SENTRY_GETINSTANCE=$(grep -n 'SentryService.getInstance()' "$EXT_JS" 2>/dev/null | grep -i 'called before' | head -1 | cut -d: -f1 || true)
    LOC_CONNECT_TIMEOUT=$(grep -n 'ConnectTimeoutError' "$EXT_JS" 2>/dev/null | head -1 | cut -d: -f1 || true)
    LOC_INVALID_LINE_RANGE=$(grep -n 'Invalid line range' "$EXT_JS" 2>/dev/null | head -1 | cut -d: -f1 || true)
    LOC_CLIENT_METRICS=$(grep -n 'client-metrics' "$EXT_JS" 2>/dev/null | head -1 | cut -d: -f1 || true)
    LOC_REQUEST_CANCELLED=$(grep -n 'Request cancelled' "$EXT_JS" 2>/dev/null | head -1 | cut -d: -f1 || true)
    tlog "  Pre-computed Augment extension.js offsets:"
    tlog "    _cancelledByUser     → L${LOC_CANCELLED_BY_USER:-?}"
    tlog "    SentryService.getInstance → L${LOC_SENTRY_GETINSTANCE:-?}"
    tlog "    ConnectTimeoutError  → L${LOC_CONNECT_TIMEOUT:-?}"
    tlog "    Invalid line range   → L${LOC_INVALID_LINE_RANGE:-?}"
    tlog "    client-metrics       → L${LOC_CLIENT_METRICS:-?}"
    tlog "    Request cancelled    → L${LOC_REQUEST_CANCELLED:-?}"
fi

# WHAT: Pre-compute our OWN extension.ts location for self-generated errors
# WHY: zygote_killed, fd_leak_warning, runaway_zygote_detected originate in OUR code
OUR_EXT_TS="hidden-terminal-watchdog/src/extension.ts"
LOC_ZYGOTE_TS=""
LOC_FD_LEAK_TS=""
if [ -f "$OUR_EXT_TS" ]; then
    LOC_ZYGOTE_TS=$(grep -n 'runaway_zygote_detected' "$OUR_EXT_TS" 2>/dev/null | head -1 | cut -d: -f1 || true)
    LOC_FD_LEAK_TS=$(grep -n 'fd_leak_warning' "$OUR_EXT_TS" 2>/dev/null | head -1 | cut -d: -f1 || true)
    tlog "    (our extension.ts) runaway_zygote → L${LOC_ZYGOTE_TS:-?}"
    tlog "    (our extension.ts) fd_leak_warning → L${LOC_FD_LEAK_TS:-?}"
fi
tlog ""

# helper: extract ~100 chars of code at a given line from a file
# Usage: extract_snippet FILE LINE COL → sets CODE_SNIPPET
extract_snippet() {
    local _file="$1" _line="$2" _col="${3:-1}"
    CODE_SNIPPET=""
    if [ -f "$_file" ] && [ "$_line" -gt 0 ] 2>/dev/null; then
        local _start=$((_col > 50 ? _col - 50 : 1))
        local _end=$((_col + 50))
        CODE_SNIPPET=$(sed -n "${_line}p" "$_file" 2>/dev/null | cut -c${_start}-${_end} || echo "")
    fi
}

# WHAT: Clear queue file — rebuild from scratch
# WHY: Stale entries from previous runs must not persist
> "$QUEUE_FILE"

SELF_PATH=".augment/scripts/llm-compliance-guide.sh"

# WHAT: Stale error types to EXCLUDE — these are historical, already resolved by hand
# WHY: "fix_applied" and "fix_suggested" were manual actions already completed.
#      "root_cause_identified" and "leak_analysis" are analytical summaries from OLD data.
#      Spamming them in diagnostics is noise, not signal.
STALE_TYPES="'fix_applied','fix_suggested','monitoring_check','root_cause_identified','leak_analysis'"

# ──────────────────────────────────────────────────────────────────────────────
# STEP 3a: Emit ONE entry per DISTINCT error message (not per type)
# ──────────────────────────────────────────────────────────────────────────────
tlog "STEP 3: Emit distinct error messages with full stack traces"
tlog "------------------------------------------------------------"

# WHAT: Query every DISTINCT (error_type, error_message, stack_trace) combo
# WHY: Previously grouped by error_type only — lost distinct messages.
#      "Request cancelled" has 3 distinct messages (API call, standalone, Service).
#      "Unknown" has 2 (SentryService, OpenFile). Each is actionable data.
# HOW: GROUP BY error_message to get one row per distinct message, with count + timestamps + full stack
# CRITICAL: error_message and stack_trace contain '|' (pipe) and newlines which break IFS='|'.
#   Fix: REPLACE(x, '|', ' // ') removes pipes, REPLACE(x, char(10), ' ') removes newlines.
#   This makes pipe-delimited output safe for bash read.
sqlite3 "$DB" "
    SELECT error_type,
           COUNT(*) as cnt,
           MAX(timestamp) as last_ts,
           REPLACE(REPLACE(error_message, '|', ' // '), char(10), ' ') as emsg,
           REPLACE(REPLACE(COALESCE(stack_trace, ''), '|', ' // '), char(10), ' ') as stk
    FROM errors
    WHERE error_type NOT IN ($STALE_TYPES)
      AND error_type != 'fd_leak_warning'
    GROUP BY error_message
    ORDER BY cnt DESC
    LIMIT 40;
" 2>&1 | while IFS='|' read -r etype ecnt last_ts emsg stack_raw; do
    tlog "  [$etype] count=$ecnt msg=${emsg:0:100}"

    # WHAT: Try to extract file:line:col from stack trace for diagnostic location
    FILE_PART="$SELF_PATH"
    LINE_NUM=1
    COL_NUM=1
    CODE_SNIPPET=""

    if [ -n "$stack_raw" ]; then
        RAW_LOC=$(echo "$stack_raw" | grep -oE '[^[:space:]@]+\.(js|ts):[0-9]+:[0-9]+' | head -1 || true)
        if [ -n "$RAW_LOC" ]; then
            FIXED_LOC="$RAW_LOC"
            if echo "$FIXED_LOC" | grep -q "augment-[0-9]" && ! echo "$FIXED_LOC" | grep -q "/out/" 2>/dev/null; then
                FIXED_LOC=$(echo "$FIXED_LOC" | sed 's|/extension\.js|/out/extension.js|')
            fi
            FILE_PART=$(echo "$FIXED_LOC" | sed 's/:[0-9]*:[0-9]*$//')
            LINE_NUM=$(echo "$FIXED_LOC" | grep -oE ':[0-9]+:[0-9]+$' | cut -d: -f2 || true)
            COL_NUM=$(echo "$FIXED_LOC" | grep -oE ':[0-9]+:[0-9]+$' | cut -d: -f3 || true)
            LINE_NUM=${LINE_NUM:-1}
            COL_NUM=${COL_NUM:-1}
            # Extract code snippet at flagged offset
            if [ -n "$EXT_JS" ] && [ -f "$EXT_JS" ] && [ "$LINE_NUM" -gt 0 ] 2>/dev/null; then
                START_COL=$((COL_NUM > 50 ? COL_NUM - 50 : 1))
                END_COL=$((COL_NUM + 50))
                CODE_SNIPPET=$(sed -n "${LINE_NUM}p" "$EXT_JS" 2>/dev/null | cut -c${START_COL}-${END_COL} || echo "")
            fi
        fi
    fi

    # WHAT: Fallback for node:internal/ stack frames (AbortError)
    # WHY: grep -oE for .js/.ts FAILS on "node:internal/deps/undici/undici:14900:13"
    #   because it has NO .js/.ts extension → RAW_LOC empty → falls back to
    #   llm-compliance-guide.sh:1:1 → completely useless.
    # FIX: If no .js/.ts location found AND error is AbortError → override to
    #   extension.js at known entry point d2@64:59334 + extract verbatim code.
    if [ "$FILE_PART" = "$SELF_PATH" ] && echo "$etype" | grep -qi "aborted"; then
        if [ -n "$EXT_JS" ] && [ -f "$EXT_JS" ]; then
            FILE_PART="$EXT_JS"
            LINE_NUM=64
            COL_NUM=59334
            START_COL=$((COL_NUM > 50 ? COL_NUM - 50 : 1))
            END_COL=$((COL_NUM + 50))
            CODE_SNIPPET=$(sed -n "${LINE_NUM}p" "$EXT_JS" 2>/dev/null | cut -c${START_COL}-${END_COL} || echo "")
            tlog "    → AbortError fallback: $EXT_JS:$LINE_NUM:$COL_NUM"
        fi
    fi

    # WHAT: Fallback for "Request cancelled" — point to _cancelledByUser latch
    # WHY: DB has 30 entries with ZERO stack traces. The root cause is _cancelledByUser
    #       one-way latch at L603-604 in extension.js.
    if [ "$FILE_PART" = "$SELF_PATH" ] && [ "$etype" = "Request cancelled" ]; then
        if [ -n "$LOC_CANCELLED_BY_USER" ] && [ -n "$EXT_JS" ] && [ -f "$EXT_JS" ]; then
            FILE_PART="$EXT_JS"
            LINE_NUM="$LOC_CANCELLED_BY_USER"
            COL_NUM=1
            extract_snippet "$EXT_JS" "$LINE_NUM" "$COL_NUM"
            tlog "    → Request cancelled fallback: $EXT_JS:$LINE_NUM (cancelledByUser)"
        fi
    fi

    # WHAT: Fallback for "fetch failed" — point to ConnectTimeoutError
    # WHY: DB has 9 entries with ZERO stacks. Root cause is network timeout at L422.
    if [ "$FILE_PART" = "$SELF_PATH" ] && [ "$etype" = "fetch failed" ]; then
        if [ -n "$LOC_CONNECT_TIMEOUT" ] && [ -n "$EXT_JS" ] && [ -f "$EXT_JS" ]; then
            FILE_PART="$EXT_JS"
            LINE_NUM="$LOC_CONNECT_TIMEOUT"
            COL_NUM=1
            extract_snippet "$EXT_JS" "$LINE_NUM" "$COL_NUM"
            tlog "    → fetch failed fallback: $EXT_JS:$LINE_NUM (ConnectTimeoutError)"
        fi
        # client-metrics specific sub-case
        if echo "$emsg" | grep -qi "client-metrics"; then
            if [ -n "$LOC_CLIENT_METRICS" ] && [ -n "$EXT_JS" ] && [ -f "$EXT_JS" ]; then
                FILE_PART="$EXT_JS"
                LINE_NUM="$LOC_CLIENT_METRICS"
                COL_NUM=1
                extract_snippet "$EXT_JS" "$LINE_NUM" "$COL_NUM"
                tlog "    → client-metrics fallback: $EXT_JS:$LINE_NUM"
            fi
        fi
    fi

    # WHAT: Fallback for "Unknown" — differentiate SentryService vs OpenFile vs other
    # WHY: DB has 13 entries with ZERO stacks. "Unknown" is a catch-all with distinct causes.
    if [ "$FILE_PART" = "$SELF_PATH" ] && [ "$etype" = "Unknown" ]; then
        if echo "$emsg" | grep -qi "SentryService\|Sentry"; then
            if [ -n "$LOC_SENTRY_GETINSTANCE" ] && [ -n "$EXT_JS" ] && [ -f "$EXT_JS" ]; then
                FILE_PART="$EXT_JS"
                LINE_NUM="$LOC_SENTRY_GETINSTANCE"
                COL_NUM=1
                extract_snippet "$EXT_JS" "$LINE_NUM" "$COL_NUM"
                tlog "    → Unknown/Sentry fallback: $EXT_JS:$LINE_NUM"
            fi
        elif echo "$emsg" | grep -qi "Invalid line range\|OpenFile"; then
            if [ -n "$LOC_INVALID_LINE_RANGE" ] && [ -n "$EXT_JS" ] && [ -f "$EXT_JS" ]; then
                FILE_PART="$EXT_JS"
                LINE_NUM="$LOC_INVALID_LINE_RANGE"
                COL_NUM=1
                extract_snippet "$EXT_JS" "$LINE_NUM" "$COL_NUM"
                tlog "    → Unknown/OpenFile fallback: $EXT_JS:$LINE_NUM"
            fi
        fi
    fi

    # WHAT: Fallback for zygote errors — point to OUR extension.ts monitorZygoteProcesses
    # WHY: These errors originate in OUR code, not Augment's. Point to actual source.
    if [ "$FILE_PART" = "$SELF_PATH" ] && echo "$etype" | grep -qi "zygote"; then
        if [ -n "$LOC_ZYGOTE_TS" ] && [ -f "$OUR_EXT_TS" ]; then
            FILE_PART="$OUR_EXT_TS"
            LINE_NUM="$LOC_ZYGOTE_TS"
            COL_NUM=1
            extract_snippet "$OUR_EXT_TS" "$LINE_NUM" "$COL_NUM"
            tlog "    → zygote fallback: $OUR_EXT_TS:$LINE_NUM"
        fi
    fi

    # WHAT: Fallback for Checkpoint errors — related to AbortError chain
    if [ "$FILE_PART" = "$SELF_PATH" ] && echo "$etype" | grep -qi "checkpoint"; then
        if [ -n "$EXT_JS" ] && [ -f "$EXT_JS" ]; then
            FILE_PART="$EXT_JS"
            LINE_NUM=64
            COL_NUM=59334
            extract_snippet "$EXT_JS" "$LINE_NUM" "$COL_NUM"
            tlog "    → Checkpoint fallback (AbortError-linked): $EXT_JS:$LINE_NUM:$COL_NUM"
        fi
    fi

    # WHAT: Build context based on error type — actionable, not generic
    CONTEXT="See .augment/error_tracking.db for full history."
    case "$etype" in
        "Request cancelled")
            CONTEXT="_cancelledByUser one-way latch at L${LOC_CANCELLED_BY_USER:-603} in extension.js. Once set to true, NEVER reset to false. All tool calls fail until VS Code reloads. Fix: reload window or fix the latch." ;;
        "This operation was aborted")
            CONTEXT="AbortError from gRPC/undici transport. Repeats every ~60s on getRemoteAgentOverviewsStream. Call chain: d2@64:59334 → callApiStream@250:8939 → callApiStream@252:479212 → getRemoteAgentOverviewsStream@252:493 → handleRemoteAgentOverviewsStreamRequest@5287:22044" ;;
        "fetch failed")
            CONTEXT="Network fetch to augmentcode.com API failed at ConnectTimeoutError@L${LOC_CONNECT_TIMEOUT:-422}. May indicate connectivity issue or API endpoint down." ;;
        "Unknown")
            if echo "$emsg" | grep -qi "SentryService\|Sentry"; then
                CONTEXT="SentryService.getInstance() called before createInstance at L${LOC_SENTRY_GETINSTANCE:-289}. Race condition in extension startup."
            elif echo "$emsg" | grep -qi "Invalid line range\|OpenFile"; then
                CONTEXT="Invalid line range in OpenFile handler at L${LOC_INVALID_LINE_RANGE:-956}. Extension tried to open a line range outside document bounds."
            else
                CONTEXT="Unclassified error from Augment extension. Error message: ${emsg:0:200}"
            fi ;;
        *"Checkpoint"*)
            CONTEXT="Checkpoint document missing — extension tried to read a checkpoint file that does not exist. Linked to AbortError chain at d2@64:59334." ;;
        *"zygote"*)
            CONTEXT="VS Code zygote subprocess consuming excessive CPU/RAM. Detected by monitorZygoteProcesses() at L${LOC_ZYGOTE_TS:-163} in our extension.ts." ;;
    esac

    JSON_LINE=$(jq -cn \
        --arg file "$FILE_PART" \
        --argjson line "${LINE_NUM}" \
        --argjson col "${COL_NUM}" \
        --arg event "$etype" \
        --arg error "${emsg}" \
        --arg timestamp "$last_ts" \
        --arg stack "${stack_raw:-no stack trace captured}" \
        --arg code "${CODE_SNIPPET:-N/A}" \
        --arg context "$CONTEXT" \
        --argjson count "${ecnt}" \
        '{file:$file, line:$line, col:$col, event:$event, error:$error, timestamp:$timestamp, stack:$stack, code:$code, context:$context, count:$count}')

    echo "$JSON_LINE" >> "$QUEUE_FILE"
    tlog "    → written to queue"
done

# ──────────────────────────────────────────────────────────────────────────────
# STEP 3b: FD leak trend summary — ONE entry with min/max/current, not 162 rows
# ──────────────────────────────────────────────────────────────────────────────
tlog ""
tlog "STEP 3b: FD leak trend summary"
tlog "-------------------------------"
FD_STATS=$(sqlite3 "$DB" "
    SELECT COUNT(*),
           MIN(CAST(REPLACE(REPLACE(error_message, 'File descriptor count: ', ''), ' (threshold: 50000)', '') AS INTEGER)),
           MAX(CAST(REPLACE(REPLACE(error_message, 'File descriptor count: ', ''), ' (threshold: 50000)', '') AS INTEGER)),
           MAX(timestamp)
    FROM errors WHERE error_type='fd_leak_warning';
" 2>&1)
FD_CNT=$(echo "$FD_STATS" | cut -d'|' -f1)
FD_MIN=$(echo "$FD_STATS" | cut -d'|' -f2)
FD_MAX=$(echo "$FD_STATS" | cut -d'|' -f3)
FD_LAST_TS=$(echo "$FD_STATS" | cut -d'|' -f4)
CURRENT_FD=$(lsof 2>/dev/null | grep -c code || echo "unknown")
tlog "  FD warnings: $FD_CNT | min=$FD_MIN max=$FD_MAX current=$CURRENT_FD"

# WHAT: Point FD leak summary to our extension.ts where fd_leak_warning is generated
# WHY: L1:1 on self_path is useless. Our monitorApplicationEvents() at LOC_FD_LEAK_TS
#       is where FD monitoring runs and generates these warnings.
FD_FILE="$SELF_PATH"
FD_LINE=1
FD_COL=1
FD_CODE="N/A"
if [ -n "$LOC_FD_LEAK_TS" ] && [ -f "$OUR_EXT_TS" ]; then
    FD_FILE="$OUR_EXT_TS"
    FD_LINE="$LOC_FD_LEAK_TS"
    FD_COL=1
    extract_snippet "$OUR_EXT_TS" "$FD_LINE" "$FD_COL"
    FD_CODE="${CODE_SNIPPET:-N/A}"
fi

JSON_LINE=$(jq -cn \
    --arg file "$FD_FILE" \
    --argjson line "${FD_LINE}" \
    --argjson col "${FD_COL}" \
    --arg event "fd_leak_warning" \
    --arg error "FD leak: ${FD_CNT} warnings, range ${FD_MIN}–${FD_MAX}, current ${CURRENT_FD}" \
    --arg timestamp "$FD_LAST_TS" \
    --arg stack "lsof | grep -c code → ${CURRENT_FD} (threshold: 50000). Generated by monitorApplicationEvents() at L${LOC_FD_LEAK_TS:-?} in extension.ts" \
    --arg code "${FD_CODE}" \
    --arg context "VS Code file descriptors exceed 50K. REG=file watcher leak, unix=IPC socket leak, pipe=subprocess leak. Fix applied: disabled augment.completions.enableChatInputCompletions. Source: monitorApplicationEvents() in our extension.ts." \
    --argjson count "${FD_CNT}" \
    '{file:$file, line:$line, col:$col, event:$event, error:$error, timestamp:$timestamp, stack:$stack, code:$code, context:$context, count:$count}')
echo "$JSON_LINE" >> "$QUEUE_FILE"
tlog "    → FD trend summary written"

tlog ""

# ──────────────────────────────────────────────────────────────────────────────
# STEP 4: System status summary
# ──────────────────────────────────────────────────────────────────────────────
tlog "STEP 4: System status summary"
tlog "------------------------------"

TEST_JSON=$(jq -cn \
    --arg file "$SELF_PATH" \
    --argjson line 1 \
    --argjson col 1 \
    --arg event "DIAGNOSTICS_ACTIVE" \
    --arg error "Diagnostics operational — $TOTAL_ERRORS total errors, $CANCELLED_ERRORS cancelled, $STACK_ERRORS with stacks" \
    --arg timestamp "$(date -Iseconds)" \
    --arg stack "N/A" \
    --arg code "N/A" \
    --arg context "System status. Stale entries excluded: fix_applied, fix_suggested (already resolved by hand)." \
    --argjson count 1 \
    '{file:$file, line:$line, col:$col, event:$event, error:$error, timestamp:$timestamp, stack:$stack, code:$code, context:$context, count:$count}')

echo "$TEST_JSON" >> "$QUEUE_FILE"
tlog "  ✅ Test diagnostic added"
tlog ""

# ──────────────────────────────────────────────────────────────────────────────
# STEP 6: Show queue contents and diagnostics tool call
# ──────────────────────────────────────────────────────────────────────────────
tlog "STEP 6: Queue contents and verification instructions"
tlog "-----------------------------------------------------"
ENTRY_COUNT=$(wc -l < "$QUEUE_FILE")
tlog "  Queue file: $QUEUE_FILE ($ENTRY_COUNT entries)"
tlog "  Contents:"
cat -n "$QUEUE_FILE" | tee -a "$LOGFILE"
tlog ""
tlog "  LLM MUST CALL diagnostics tool with these paths:"
tlog "    diagnostics([\"$SELF_PATH\""
if [ -n "$EXT_DIR" ]; then
    tlog "      , \"$EXT_DIR/out/extension.js\""
fi
tlog "    ])"
tlog ""
tlog "  EXPECTED: Each diagnostic message contains event, error, timestamp,"
tlog "            stack trace, code snippet, context, and occurrence count."
tlog "            NOT just '[RULE_9_VIOLATION]'."
tlog ""

tlog "========================================"
tlog "LOG: $LOGFILE"
tlog "========================================"

# WHAT: Mandatory delay for output buffer flush
sleep 0.5

