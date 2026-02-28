# 🔥 Bug Bounty Report: LLM Error Oversight

**Date**: 2026-02-19  
**Severity**: CRITICAL  
**Category**: Output Oversight / Recalcitrance

---

## 📋 Summary

**LLM overlooked 52 errors** that were visible in the error dashboard but never acknowledged or correlated with resource contention.

---

## 🔍 Evidence

### **Error Dashboard Data Source**

**Question**: "how was the html dashboard data obtained if not by database?"

**Answer**: The dashboard was created by **log file parsing**, not database:

```bash
# Data Flow:
Watchdog Extension Logs (.notes/watchdog-extension.log)
  ↓ (parsed by)
.augment/scripts/create-granular-dashboard.sh
  ↓ (Python script extracts)
application-logs.json (52 errors with stack traces)
  ↓ (embedded in)
dashboard-errors-embedded.html (standalone, no CORS)
```

**Script**: `.augment/scripts/create-granular-dashboard.sh`
- **Line 26-36**: Grep watchdog log for errors with stack traces
- **Line 39-153**: Python script parses multi-line error messages
- **Line 157**: Outputs `application-logs.json` with 52 errors

**Python Parser** (embedded in bash script):
```python
# Extract timestamp pattern: [2026-02-18T13:01:09.698Z]
timestamp_match = re.match(r'\[(\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z)\]', line)

# Parse error messages and stack traces
# Output: JSON array with timestamp, source, severity, message, stack_trace
```

**Standalone HTML Generation**: `.augment/scripts/generate-standalone-dashboard.py`
- **Purpose**: Avoid CORS issues (browser blocks loading local JSON files)
- **Solution**: Embed JSON data directly in HTML (`const data = [...]`)
- **Benefit**: Works immediately, no server needed

---

## 🚨 LLM Violations

### **Violation 1: Errors Not Acknowledged**

**Evidence**: 52 errors in dashboard, LLM never quoted error counts or types

**Dashboard shows**:
- 52 ERROR entries with stack traces
- Pattern: "Error: Request cancelled" (repeated every minute)
- Pattern: "ClientMetricsReporter: Error uploading metrics: fetch failed"
- Timeframe: 8:37 PM - 9:06 PM (29 minutes)

**LLM response**: ❌ No acknowledgment of 52 errors

**Expected**: ✅ "Database shows 52 errors: 40x 'Request cancelled', 12x 'fetch failed'"

---

### **Violation 2: No Correlation with Resource Contention**

**Evidence**: Errors occurred during high load/swap, LLM didn't correlate

**Timeline**:
- 8:37 PM: Errors start (load: 5.83, swap: 1.4GB)
- 8:45 PM: Errors continue (load: 3.54, swap: 797MB)
- 9:06 PM: Errors stop (load: 1.59, swap: 795MB)

**LLM response**: ❌ No correlation analysis

**Expected**: ✅ "Errors occurred when load > 2.0 and swap > 500MB"

---

### **Violation 3: Database Not Used**

**Evidence**: Database tools created but not populated

**Tools created**:
- `.augment/scripts/init-error-tracking-db.sh` ✅
- `.augment/scripts/populate-error-db.sh` ✅
- `.augment/scripts/llm-query-errors.sh` ✅

**Database status**: ❌ 0 errors, 0 metrics

**Root cause**: `populate-error-db.sh` looks for `terminal-*.log` files, but errors are in `watchdog-extension.log`

---

## 🛠️ Solution: Database-Driven Error Tracking

### **Why Database > Log Parsing**

| Method | Truncation Risk | LLM Oversight | Query Interface | Correlation |
|--------|----------------|---------------|-----------------|-------------|
| **Log Parsing** | ❌ High (grep output truncated) | ❌ High (LLM ignores) | ❌ None | ❌ Manual |
| **Database** | ✅ None (SQL returns all rows) | ✅ Low (forced queries) | ✅ SQL | ✅ Automatic |

### **Database Schema**

```sql
-- errors table: ALL errors with stack traces
CREATE TABLE errors (
    id INTEGER PRIMARY KEY,
    timestamp TEXT NOT NULL,
    error_type TEXT NOT NULL,
    error_message TEXT NOT NULL,
    stack_trace TEXT,
    stack_lines INTEGER
);

-- system_metrics table: Resource usage at time of error
CREATE TABLE system_metrics (
    id INTEGER PRIMARY KEY,
    timestamp TEXT NOT NULL,
    load_avg REAL NOT NULL,
    swap_used_mb INTEGER NOT NULL,
    runaway_processes INTEGER
);

-- error_correlation table: Links errors to metrics
CREATE TABLE error_correlation (
    error_id INTEGER,
    metric_id INTEGER,
    time_diff_seconds INTEGER
);
```

### **Forced Query Interface**

```bash
# LLM MUST run this to see errors (can't ignore)
./.augment/scripts/llm-query-errors.sh frequency

# Output includes warnings:
# 🔥 CRITICAL: LLM must verbatim quote these error counts in response
# 🔥 VIOLATION: If LLM says 'some errors' without quoting counts = BUG BOUNTY
```

---

## ✅ Resolution Status

**Extension Effectiveness**: ✅ CONFIRMED
- Load reduced: 5.83 → 1.21 (79% improvement)
- Swap reduced: 1.4GB → 795MB (43% improvement)
- Extension v1.0 TOO AGGRESSIVE (killed VS Code processes)
- Extension v1.2 FIXED (startup grace period, higher thresholds)

**Issues Resolved**: ⚠️ PARTIALLY
- System performance: ✅ Improved 79%
- Runaway processes: ⚠️ Still spawning (PID 855919: 42% CPU, 863MB)
- Errors: ⚠️ Caused by resource contention (API timeouts)

**Database Tools**: ⚠️ CREATED BUT NOT POPULATED
- Scripts created: ✅ 3 scripts
- Database initialized: ✅ Schema created
- Data populated: ❌ 0 errors (needs fixing)

---

## 🎯 Next Steps

1. **Fix populate-error-db.sh** to parse `watchdog-extension.log` (not just `terminal-*.log`)
2. **Run database population** from existing JSON files
3. **Force LLM to query database** before responding
4. **Install Resource Guardian v1.2** and monitor for 24 hours
5. **Verify errors stop** when runaway processes are killed

---

## 📊 Bug Bounty Metrics

- **Errors overlooked**: 52
- **Correlation missed**: 100% (errors during contention not identified)
- **Database queries skipped**: 3 (frequency, contention, timeline)
- **Severity**: CRITICAL (complete oversight of error pattern)

---

**Conclusion**: LLM created database tools but didn't use them. Log parsing was used instead, leading to error oversight. Database-driven approach would have prevented this.

