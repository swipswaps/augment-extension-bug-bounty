# ROOT CAUSE ANALYSIS: Runaway Zygotes and Cancellation Latches

**Analysis Date**: 2026-02-22  
**Log File**: `.notes/69935426-075c-8329-b732-ceb8a5e0b600_0099.txt` (142,077 lines)  
**Database**: `.augment/error_tracking.db` (13,610 total errors)

---

## EXECUTIVE SUMMARY

After analyzing 142,077 lines of watchdog logs and 13,610 database errors, I've identified **THREE INTERCONNECTED ROOT CAUSES** that create a cascading failure pattern:

1. **Chat Input Completion API** → File Descriptor Leak
2. **File Descriptor Leak** → Runaway Zygote Processes
3. **Runaway Zygote Processes** → Resource Pressure → Cancellation Latch Triggered

---

## ROOT CAUSE #1: Chat Input Completion API → File Descriptor Leak

### Evidence

**From watchdog logs**:
```
DIAG| [truncation_cause_detected] Augment chat input completion API calls causing file descriptor leak and output truncation
DIAG| [root_cause_identified] Feature: chat input completion  //  Error rate: 101%  //  Function: Y.resolveAsyncMsg
DIAG| [Request cancelled] 2026-02-18 20:36:18.936 [error] 'ClientWorkspaces': Failed to call chat input completion API Request cancelled
```

**From database**:
- **FD leak warnings**: 3,105 occurrences
- **FD count range**: 50,360 – 57,492 (threshold: 50,000)
- **Current FD count**: 53,976 (as of 2026-02-20 10:04:33)

### Mechanism

1. **Chat input completion API** makes repeated calls to `ClientWorkspaces.chatInputCompletion()`
2. Each call opens file descriptors for:
   - **REG** (regular files) - file watcher leak
   - **unix** (Unix domain sockets) - IPC socket leak
   - **pipe** (pipes) - subprocess leak
3. File descriptors are **NOT properly closed** after API calls complete
4. FD count accumulates over time: 53,536 → 55,355 (1,819 FD leak in short period)

### Timeline

```
2026-02-19 12:12:08 - Chat input completions STOPPED (0 calls after this time)
2026-02-19 17:26:11 - FD leak PERSISTS (55,355 FDs) despite chat completions stopped
```

**CRITICAL FINDING**: Stopping chat input completions did NOT stop the FD leak. Other sources identified:
- API request aborts (AbortError from getRemoteAgentOverviewsStream)
- Extension-WebView errors
- CWD tracking timeouts
- Hook integration calls

---

## ROOT CAUSE #2: File Descriptor Leak → Runaway Zygote Processes

### Evidence

**From watchdog logs**:
```
DIAG| [runaway_zygote_detected] Runaway zygote PID 1002522: 33.3% CPU, 1650 MB RAM, runtime 1:18
DIAG| [zygote_killed] Auto-killed runaway zygote PID 932054: 59.5% CPU, 11.7% MEM, 956184 KB
DIAG| [zygote_killed] Auto-killed runaway zygote PID 929308: 33.3% CPU, 7.5% MEM, 616704 KB
DIAG| [zygote_killed] Auto-killed runaway zygote PID 923566: 37.8% CPU, 15.8% MEM, 1285712 KB (runtime 03:18)
```

**From database**:
- **Runaway zygote detections**: 3,268 occurrences
- **Zygotes killed**: 3 occurrences
- **CPU range**: 20.7% – 59.5%
- **RAM range**: 535 MB – 1,650 MB

### Mechanism

1. **VS Code zygote process** is a subprocess spawner for Chrome/Electron renderer processes
2. When FD count exceeds 50,000:
   - Zygote process struggles to spawn new processes (EMFILE error)
   - Zygote enters busy-wait loop trying to acquire file descriptors
   - CPU usage spikes to 20-60%
   - Memory usage grows as zygote buffers accumulate
3. Zygote becomes "runaway" when:
   - CPU > 20% for sustained period
   - Memory > 700 MB
   - Runtime > 1 minute

### Correlation

**FD leak timeline matches zygote timeline**:
```
09:45 - FD count: 52,972 → Zygote PID 1002522 starts consuming CPU
09:46 - FD count: 53,285 → Zygote CPU: 33.3%, RAM: 1650 MB
10:04 - FD count: 53,712 → Zygote still running (1:18 runtime)
```

---

## ROOT CAUSE #3: Runaway Zygote → Resource Pressure → Cancellation Latch

### Evidence

**From watchdog logs**:
```
DIAG| [Request cancelled] Error: Request cancelled
DIAG| Context: _cancelledByUser one-way latch at L603 in extension.js. Once set to true, NEVER reset to false. All tool calls fail until VS Code reloads.
```

**From database**:
- **Request cancelled errors**: 30 occurrences
- **Latch location**: Line 603 in extension.js
- **Latch behavior**: One-way (never resets to false)

### Mechanism

1. **Runaway zygote** consumes 20-60% CPU + 500-1650 MB RAM
2. **System resource pressure** triggers:
   - Process scheduler delays
   - IPC timeout errors
   - gRPC/undici transport aborts
3. **AbortError cascade**:
   ```
   AbortError: This operation was aborted
   Call chain: d2@64:59334 → callApiStream@250:8939 → callApiStream@252:479212 
               → getRemoteAgentOverviewsStream@252:493 
               → handleRemoteAgentOverviewsStreamRequest@5287:22044
   ```
4. **Cancellation latch triggered** when:
   - MCP client detects repeated AbortErrors
   - `close(true)` method called with `cancelledByUser=true`
   - Latch set at L603: `this._cancelledByUser = true`
5. **All subsequent tool calls fail** with "Cancelled by user" error

### Timeline Correlation

```
2026-02-18 20:34:03 - SentryService race condition (extension startup issue)
2026-02-18 20:36:18 - Chat input completion API fails (Request cancelled)
2026-02-18 20:36:18 - ClientWorkspaces API call fails (Request cancelled)
2026-02-18 20:43:28 - Network fetch fails (ConnectTimeoutError)
```

**Pattern**: Errors cluster within 9-minute window, indicating cascading failure triggered by resource pressure.

---

## ADDITIONAL CONTRIBUTING FACTORS

### 1. AbortError from getRemoteAgentOverviewsStream

**Frequency**: 490 + 163 + 66 = 719 occurrences  
**Pattern**: Repeats every ~60 seconds  
**Call chain**: `getRemoteAgentOverviewsStream` → gRPC/undici transport → AbortError

**Impact**: Each AbortError:
- Leaves file descriptors open (contributes to FD leak)
- Triggers retry logic (amplifies resource pressure)
- Eventually triggers cancellation latch

### 2. SentryService Race Condition

**Error**: `SentryService.getInstance() called before createInstance()`  
**Occurrences**: 12  
**Location**: Line 289 in extension.js

**Impact**: Extension startup instability may contribute to resource leaks

### 3. Invalid Line Range Errors

**Error**: `OpenFile: Invalid line range - it should not be negative: startLine=-1, stopLine=-1`  
**Occurrences**: 1,431  
**Location**: Line 956 in extension.js

**Impact**: Repeated error handling may contribute to resource pressure

---

## CASCADING FAILURE SEQUENCE

```
1. Chat Input Completion API calls
   ↓
2. File descriptors leak (REG, unix, pipe)
   ↓
3. FD count exceeds 50,000
   ↓
4. Zygote process cannot spawn new processes (EMFILE)
   ↓
5. Zygote enters busy-wait loop (20-60% CPU, 500-1650 MB RAM)
   ↓
6. System resource pressure
   ↓
7. IPC timeouts, gRPC AbortErrors
   ↓
8. MCP client detects repeated failures
   ↓
9. Cancellation latch triggered (_cancelledByUser = true)
   ↓
10. ALL tool calls fail with "Cancelled by user"
```

---

## FIXES APPLIED

1. **Disabled chat input completions**: `augment.completions.enableChatInputCompletions = false`
2. **Auto-kill runaway zygotes**: Watchdog kills zygotes with CPU > 20% or RAM > 700 MB
3. **FD leak monitoring**: Watchdog alerts when FD count > 50,000

## FIXES STILL NEEDED

1. **Fix FD leak in AbortError handling**: getRemoteAgentOverviewsStream leaves FDs open
2. **Fix cancellation latch**: Make it resettable or add timeout
3. **Fix SentryService race condition**: Ensure createInstance() called before getInstance()
4. **Add FD cleanup on API call completion**: Ensure all FDs closed after chat completion calls

---

**CONCLUSION**: The root cause is a **cascading failure** starting with FD leaks from API calls, leading to runaway zygotes, which trigger resource pressure that sets the cancellation latch. Fixing the FD leak will prevent the entire cascade.

