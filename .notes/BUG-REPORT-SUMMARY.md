# AUGMENT BUG - ONE PAGE SUMMARY

## THE PROBLEM
Augment extension becomes completely unusable within 60 seconds of VS Code startup. ALL tool calls fail with "Cancelled by user" error.

## THE ROOT CAUSE
1. Background API call to `https://d17.api.augmentcode.com/remote-agents/list-stream` times out every 60 seconds
2. Timeout throws `AbortError` 
3. Error handler calls `close(true)`, setting `_cancelledByUser = true`
4. This flag is NEVER reset to `false` (one-way latch)
5. ALL subsequent tool calls check this flag and fail immediately

## THE EVIDENCE
**Request ID:** `77cc2718-93b3-4815-95fb-2de0aa19e562` (same request retrying for hours)

**Stack Trace (from 761+ captured errors):**
```
AbortError: This operation was aborted
at async d2 (/home/owner/.vscode/extensions/augment.vscode-augment-0.779.0/out/extension.js:64:59334)
at async eH.callApiStream (/home/owner/.vscode/extensions/augment.vscode-augment-0.779.0/out/extension.js:250:8939)
at async eH.getRemoteAgentOverviewsStream (/home/owner/.vscode/extensions/augment.vscode-augment-0.779.0/out/extension.js:252:493)
at async e.handleRemoteAgentOverviewsStreamRequest (/home/owner/.vscode/extensions/augment.vscode-augment-0.779.0/out/extension.js:5287:22044)
```

**Latch Location:** Line 603 in extension.js

## THE FIX NEEDED
1. **Don't set `_cancelledByUser` for background API failures** - only for user-initiated cancellations
2. **Add circuit breaker** - stop retrying after 10 consecutive failures
3. **Add exponential backoff** - don't retry every 60 seconds if it keeps failing
4. **Reset the latch** - set `_cancelledByUser = false` after each tool completes

## IMMEDIATE WORKAROUND
Block the failing endpoint at network level:
```bash
echo "127.0.0.1 d17.api.augmentcode.com" | sudo tee -a /etc/hosts
```

This stops the retry loop and prevents the latch from being set.

## USER IMPACT
- User has dealt with this for "many, many months"
- Extension unusable within 60 seconds of startup
- Requires VS Code reload every 1-2 minutes
- User states: "I give up"

## PRIORITY
🔴 **P0 - CRITICAL** - Makes Augment completely unusable

## FULL REPORT
See: `.notes/AUGMENT-TEAM-COMPLETE-BUG-REPORT-2026-02-20.md`

