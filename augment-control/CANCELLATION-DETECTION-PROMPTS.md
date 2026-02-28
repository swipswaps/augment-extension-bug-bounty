# Cancellation Detection Prompts

**Purpose**: Force Augment to show exact code that cancels tool requests

**Usage**: Copy these prompts verbatim into Augment chat

---

## PROMPT 1 — Identify Cancellation Source (No Guessing)

```
You must identify the exact code path that cancels tool requests.

Requirements:

1. Search the active Augment extension directory for:
   - cancel
   - CancellationToken
   - AbortController
   - abort(
   - timeout
   - race(
   - Promise.race

2. Show:
   - Full file path
   - Exact line numbers
   - Full function definitions (no truncation)
   - The call site that triggers cancellation

3. Then trace:
   - Where the cancellation token originates
   - Where it is passed
   - Where it is triggered

4. You must show the actual code, not describe it.

5. If cancellation is triggered by timeout, show:
   - The timeout duration
   - The timer creation
   - The callback that triggers cancellation

Do not summarize.
Do not paraphrase.
Do not explain.
Only show the actual code with file paths and line numbers.
```

---

## PROMPT 2 — Trace Timeout-Based Cancellation

```
Trace the full lifecycle of a tool request that times out.

You must:

1. Locate where a timeout is defined for tool execution.
2. Show the code that sets the timer.
3. Show the code that cancels the request when the timer fires.
4. Show how cancellation propagates to:
   - webview
   - extension host
   - tool runner

Provide:

- Full function definitions
- Exact Promise chains
- Any use of Promise.race or AbortController

Then answer:

Does cancellation occur BEFORE stdout is read?
Show the code that proves your answer.

No summaries.
No commentary.
Only code and minimal trace annotations.
```

---

## PROMPT 3 — Prove Event Loop Blocking Trigger

```
Locate the code responsible for:

- getAggregateCheckpoint
- diff
- extractCommon

Show:

1. Where these functions are defined.
2. Whether they are synchronous.
3. Whether they run on the main extension host thread.
4. Whether they are wrapped in await or worker threads.

If synchronous:

Show how long-running execution would block the event loop.

Provide actual code only.

Then answer with evidence:

Does this code run before or after cancellation triggers?

Do not summarize.
Do not speculate.
Provide file paths and code only.
```

---

## PROMPT 4 — Detect Promise.race Cancellation

```
Search for all instances of Promise.race in the Augment extension.

For each instance:

1. Show full surrounding function.
2. Show both sides of the race.
3. Identify which branch cancels.
4. Show whether stdout reading occurs before race resolves.

Then state:

If timeout branch resolves first, is stdout discarded?

Show the code that proves it.
```

---

## PROMPT 5 — Cancellation Token Origin Trace

```
Search for all new CancellationTokenSource().

For each:

1. Show where it is created.
2. Show where .cancel() is called.
3. Show what triggers .cancel() (timeout? UI event? error?).

Then show how that token is passed to tool execution.

Trace it until it reaches process kill or abort.

Only show code.
No explanation.
```

---

## PROMPT 6 — Webview-Level Abort Detection

```
Search webview bundle for:

- abort(
- controller.abort(
- cancellation
- timed out
- cancelToolRun

Show:

1. Where cancelToolRun is defined.
2. What it returns.
3. Whether it waits for stdout to flush.
4. Whether it resolves before reading output.

Provide full function definitions.
No summaries.
```

---

## PROMPT 7 — Cancellation vs Output Read Order

```
For a timed-out tool call:

Show the exact order of operations:

1. Timeout fires
2. Cancellation token triggers
3. Process is killed
4. Stdout is read
5. Promise resolves

You must show code proving the actual order.

If cancellation happens before stdout read,
highlight the exact lines where ordering causes loss.

No narrative.
Only code and numbered sequence.
```

---

## Enforcement Addition

If Augment summarizes instead of showing code:

```
If you summarize instead of showing code,
you are violating the request.

Show raw code or respond:

"CODE NOT FOUND"
```

---

## Expected Patterns

One of these will be found:

### Pattern A — Promise.race timeout
```javascript
Promise.race([
   runTool(),
   timeout()
])
```
Timeout wins → output lost.

### Pattern B — CancellationToken before read
```javascript
token.cancel()
process.kill()
resolve()
```
No flush step.

### Pattern C — Event loop starvation triggers watchdog cancel

Extension host blocks → cancellation token fires → output not yet read.

---

## Usage Instructions

1. Copy prompt verbatim
2. Paste into Augment chat
3. Wait for code extraction
4. If Augment summarizes, use enforcement addition
5. Save extracted code to file for analysis

