# Working Code Examples - Augment Control

**Purpose**: Working code examples for every claim in augment-control/README.md

---

## Quick Start (README.md Line 100-103)

**Claim**: "Quick start commands to use Augment Control"

**Working Code**:
```bash
cd augment-control

# Execute command with full logging and compliance tracking
bash scripts/exec-with-logging.sh "npm test"

# Verify output was captured
bash scripts/verify-output-read.sh

# Check compliance metrics
bash scripts/show-metrics.sh
```

**Expected Output**:
```
START: npm-test
[test output here]
END: npm-test
Exit code: 0

✅ Output verified and logged
📊 Success rate: 100%
⚠️  Violations: 0
```

---

## Execute with Logging (README.md Line 23-26)

**Claim**: "Execute commands with automatic logging and output capture"

**Working Code**:
```bash
# Basic usage
bash scripts/exec-with-logging.sh "echo 'Hello World'"

# With complex command
bash scripts/exec-with-logging.sh "for i in {1..5}; do echo \"Line \$i\"; done"

# With command that might fail
bash scripts/exec-with-logging.sh "npm test" || echo "Command failed but output was captured"
```

**Expected Output**:
```
START: echo-hello-world
Hello World
END: echo-hello-world
Exit code: 0
Duration: 15ms
Status: ✅ SUCCESS
```

**Verification**:
```bash
# Check log file was created
ls -lh .notes/terminal-*.log | tail -1

# View log content
tail -20 .notes/terminal-*.log | tail -1
```

---

## Verify Output Read (README.md Line 39-41)

**Claim**: "Verify that LLM actually read the command output"

**Working Code**:
```bash
# Run a command first
bash scripts/exec-with-logging.sh "echo 'Test output'"

# Then verify it was read
bash scripts/verify-output-read.sh

# Check for violations
if [ $? -eq 0 ]; then
    echo "✅ Output was read correctly"
else
    echo "❌ VIOLATION: Output was not read"
fi
```

**Expected Output**:
```
🔍 Checking if output was read...
✅ Output verified in database
✅ Log file exists and contains START/END markers
✅ No violations detected
```

---

## Show Metrics (README.md Line 53-55)

**Claim**: "Display compliance metrics and success rates"

**Working Code**:
```bash
bash scripts/show-metrics.sh
```

**Expected Output**:
```
═══════════════════════════════════════════════════════════════════
📊 AUGMENT CONTROL METRICS
═══════════════════════════════════════════════════════════════════

📈 Total commands executed: 42
✅ Successful commands: 40
❌ Failed commands: 2
🎯 Success rate: 95.2%
⚠️  LLM violations logged: 0

🎉 ZERO VIOLATIONS = LLM IS COMPLIANT!

Last 5 commands:
  1. npm test (✅ SUCCESS, 2.3s)
  2. git status (✅ SUCCESS, 0.1s)
  3. echo test (✅ SUCCESS, 0.01s)
  4. npm build (❌ FAILED, 5.2s)
  5. ls -la (✅ SUCCESS, 0.05s)
```

---

## Cleanup Old Logs (README.md Line 67-69)

**Claim**: "Automatically cleanup old log files"

**Working Code**:
```bash
# Keep only 20 most recent log files
bash scripts/cleanup-old-logs.sh

# Custom: Keep only 10 most recent
bash scripts/cleanup-old-logs.sh 10

# Custom: Keep only 50 most recent
bash scripts/cleanup-old-logs.sh 50
```

**Expected Output**:
```
🧹 Cleaning up old log files...
📊 Current log count: 45
🎯 Target log count: 20
🗑️  Deleting 25 old log files...
✅ Cleanup complete
📊 New log count: 20
```

**Verification**:
```bash
# Count log files
ls -1 .notes/terminal-*.log 2>/dev/null | wc -l
# Expected: 20 (or your specified limit)
```

---

## Check Database (README.md Line 78-80)

**Claim**: "Query the SQLite database for command history"

**Working Code**:
```bash
# View all commands
sqlite3 .augment/command_history.db "SELECT * FROM commands ORDER BY timestamp DESC LIMIT 10;"

# View only failed commands
sqlite3 .augment/command_history.db "SELECT command, exit_code, timestamp FROM commands WHERE exit_code != 0;"

# View success rate
sqlite3 .augment/command_history.db "SELECT 
    COUNT(*) as total,
    SUM(CASE WHEN exit_code = 0 THEN 1 ELSE 0 END) as success,
    ROUND(100.0 * SUM(CASE WHEN exit_code = 0 THEN 1 ELSE 0 END) / COUNT(*), 2) as success_rate
FROM commands;"
```

**Expected Output**:
```
total|success|success_rate
42|40|95.24
```

---

## Export Violations (README.md Line 89-93)

**Claim**: "Export LLM violations to JSON for bug bounty submission"

**Working Code**:
```bash
# Export all violations
bash scripts/export-violations.sh

# View the exported file
cat bug_bounty_report.json | jq '.'
```

**Expected Output**:
```json
{
  "report_id": "174ab568-83ed-4b09-9ac9-dce2f07c6fcf",
  "timestamp": "2026-02-18T08:45:00Z",
  "total_violations": 0,
  "violations": []
}
```

**If violations exist**:
```json
{
  "report_id": "174ab568-83ed-4b09-9ac9-dce2f07c6fcf",
  "timestamp": "2026-02-18T08:45:00Z",
  "total_violations": 2,
  "violations": [
    {
      "command": "npm test",
      "violation_type": "output_not_read",
      "timestamp": "2026-02-18T08:30:00Z",
      "evidence": "LLM claimed 'no output' but log file contains 500 lines"
    }
  ]
}
```

---

## Manual Steps (README.md Line 113-128)

**Claim**: "Manual verification steps when automation fails"

**Working Code**:
```bash
# Step 1: Check if database exists
if [ -f .augment/command_history.db ]; then
    echo "✅ Database exists"
else
    echo "❌ Database missing - run exec-with-logging.sh first"
fi

# Step 2: Check if log files exist
LOG_COUNT=$(ls -1 .notes/terminal-*.log 2>/dev/null | wc -l)
echo "📊 Log files: $LOG_COUNT"

# Step 3: Verify last command was logged
LAST_LOG=$(ls -t .notes/terminal-*.log 2>/dev/null | head -1)
if [ -n "$LAST_LOG" ]; then
    echo "📄 Last log: $LAST_LOG"
    echo "Content:"
    cat "$LAST_LOG"
else
    echo "❌ No log files found"
fi

# Step 4: Check database integrity
sqlite3 .augment/command_history.db "PRAGMA integrity_check;"
# Expected: ok
```

---

## Testing (README.md Line 133-138)

**Claim**: "Test the Augment Control system"

**Working Code**:
```bash
# Test 1: Simple command
bash scripts/exec-with-logging.sh "echo 'Test 1'"
bash scripts/verify-output-read.sh
echo "Test 1: $?"

# Test 2: Multi-line output
bash scripts/exec-with-logging.sh "for i in {1..10}; do echo \"Line \$i\"; done"
bash scripts/verify-output-read.sh
echo "Test 2: $?"

# Test 3: Failed command
bash scripts/exec-with-logging.sh "false" || true
bash scripts/verify-output-read.sh
echo "Test 3: $?"

# Test 4: Check metrics
bash scripts/show-metrics.sh

# All tests should show:
# Test 1: 0 (success)
# Test 2: 0 (success)
# Test 3: 0 (success - output was read even though command failed)
# Test 4: Metrics displayed
```

---

## Integration with Bug Bounty Repo

**Working Code**:
```bash
# Copy violations to bug bounty repo
bash scripts/export-violations.sh
cp bug_bounty_report.json ../augment-extension-bug-bounty/evidence/

# Verify copy
ls -lh ../augment-extension-bug-bounty/evidence/bug_bounty_report.json
```

---

## Continuous Monitoring

**Working Code**:
```bash
# Monitor compliance in real-time
watch -n 5 'bash scripts/show-metrics.sh'

# Or create a monitoring loop
while true; do
    clear
    bash scripts/show-metrics.sh
    echo ""
    echo "Press Ctrl+C to exit"
    sleep 5
done
```

---

## Reset Database

**Working Code**:
```bash
# Backup current database
cp .augment/command_history.db .augment/command_history.db.backup-$(date +%Y%m%d-%H%M%S)

# Reset database (delete and recreate)
rm .augment/command_history.db

# Run a command to recreate database
bash scripts/exec-with-logging.sh "echo 'Database reset'"

# Verify new database
sqlite3 .augment/command_history.db "SELECT COUNT(*) FROM commands;"
# Expected: 1
```

---

**✅ ALL CLAIMS IN AUGMENT-CONTROL README NOW HAVE WORKING CODE EXAMPLES**

