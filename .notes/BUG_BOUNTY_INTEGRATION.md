# 🎯 BUG BOUNTY INTEGRATION GUIDE

## 📦 FOR `augment-extension-bug-bounty` REPO

This document explains how to integrate the Anti-Recalcitrance System with the bug bounty repo.

**Repo:** https://github.com/swipswaps/augment-extension-bug-bounty

---

## 🗂️ DIRECTORY STRUCTURE TO CREATE:

```
augment-extension-bug-bounty/
├── violations/
│   ├── schema.json              # Violation report format
│   ├── README.md                # How to submit violations
│   ├── submit-violation.sh      # Auto-submit script
│   └── reports/                 # Submitted violation reports
│       ├── 2026-02-18-001.json
│       ├── 2026-02-18-002.json
│       └── ...
├── .github/
│   └── workflows/
│       └── validate-violations.yml  # CI/CD to validate submissions
└── README.md                    # Main documentation
```

---

## 📋 FILE: `violations/schema.json`

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "LLM Recalcitrance Violation Report",
  "description": "Schema for reporting LLM failures to read output, ignore errors, or assume success",
  "type": "object",
  "required": ["violation_id", "timestamp", "violation_type", "severity", "evidence", "command"],
  "properties": {
    "violation_id": {
      "type": "integer",
      "description": "Unique violation ID from database"
    },
    "timestamp": {
      "type": "string",
      "format": "date-time",
      "description": "ISO 8601 timestamp of violation"
    },
    "violation_type": {
      "type": "string",
      "enum": ["output_not_read", "error_ignored", "assumed_success", "no_verbatim_quote"],
      "description": "Type of LLM recalcitrance"
    },
    "severity": {
      "type": "string",
      "enum": ["critical", "major", "minor"],
      "description": "Severity level"
    },
    "evidence": {
      "type": "string",
      "description": "What the LLM said/did that violated"
    },
    "context": {
      "type": "string",
      "description": "Additional context for debugging"
    },
    "command": {
      "type": "object",
      "required": ["command_id", "command", "exit_code"],
      "properties": {
        "command_id": {
          "type": "integer",
          "description": "Database command ID"
        },
        "command": {
          "type": "string",
          "description": "Full command executed"
        },
        "exit_code": {
          "type": "integer",
          "description": "Command exit code"
        },
        "duration_ms": {
          "type": "integer",
          "description": "Execution time in milliseconds"
        },
        "log_file": {
          "type": "string",
          "description": "Path to log file with full output"
        }
      }
    }
  }
}
```

---

## 📋 FILE: `violations/submit-violation.sh`

```bash
#!/bin/bash
# Auto-submit violation to bug bounty repo
# WHY: Streamlines bug bounty submission process

set -euo pipefail

REPORT_FILE="$1"
REPO_DIR="violations/reports"

if [ ! -f "$REPORT_FILE" ]; then
    echo "❌ Report file not found: $REPORT_FILE"
    exit 1
fi

# Validate JSON schema
if ! jq empty "$REPORT_FILE" 2>/dev/null; then
    echo "❌ Invalid JSON in report file"
    exit 1
fi

# Generate unique filename
TIMESTAMP=$(date +%Y-%m-%d-%H%M%S)
DEST_FILE="$REPO_DIR/$TIMESTAMP.json"

# Copy report
mkdir -p "$REPO_DIR"
cp "$REPORT_FILE" "$DEST_FILE"

echo "✅ Violation report copied to: $DEST_FILE"
echo ""
echo "🚀 NEXT STEPS:"
echo "  1. Review the report: cat $DEST_FILE | jq"
echo "  2. Commit: git add $DEST_FILE && git commit -m 'Add violation report $TIMESTAMP'"
echo "  3. Push: git push"
echo ""

exit 0
```

---

## 📋 FILE: `violations/README.md`

```markdown
# LLM Recalcitrance Violation Reports

This directory contains violation reports from the Anti-Recalcitrance System.

## What is LLM Recalcitrance?

**LLM Recalcitrance** is when AI assistants:
- ❌ Skip reading terminal output
- ❌ Assume commands succeeded without checking
- ❌ Move on without verifying results
- ❌ Don't log critical diagnostic data
- ❌ Ignore errors and warnings

## How to Submit a Violation

1. **Generate report** from your local database:
   ```bash
   .augment/scripts/export-violations.sh
   ```

2. **Submit to this repo**:
   ```bash
   ./violations/submit-violation.sh bug_bounty_report.json
   ```

3. **Commit and push**:
   ```bash
   git add violations/reports/*.json
   git commit -m "Add violation reports"
   git push
   ```

## Violation Types

- **output_not_read** - LLM didn't quote command output
- **error_ignored** - LLM ignored non-zero exit code
- **assumed_success** - LLM assumed success without checking
- **no_verbatim_quote** - LLM paraphrased instead of quoting

## Severity Levels

- **critical** - Command failed but LLM proceeded
- **major** - Output skipped, could miss important info
- **minor** - Minor compliance issue

## Schema

See `schema.json` for the violation report format.
```

---

## 🔄 WORKFLOW:

### **1. In `firefox-performance-tuner` or `hidden-terminal-watchdog` repo:**

```bash
# Execute command with logging
.augment/scripts/exec-with-logging.sh "your-command-here"

# Verify LLM read output
.augment/scripts/verify-output-read.sh

# Export violations
.augment/scripts/export-violations.sh
```

### **2. In `augment-extension-bug-bounty` repo:**

```bash
# Submit violation report
./violations/submit-violation.sh ../firefox-performance-tuner/bug_bounty_report.json

# Commit and push
git add violations/reports/*.json
git commit -m "Add violation reports from firefox-performance-tuner"
git push
```

---

## 🎯 WHY THIS ELIMINATES LLM RECALCITRANCE:

1. **Forced Visibility** - `tee` makes output unavoidable
2. **Database Accountability** - Every command tracked
3. **Watchdog Enforcement** - Scripts verify LLM compliance
4. **Bug Bounty Evidence** - Violations documented and submitted
5. **Continuous Improvement** - Patterns identified and fixed

---

## 📊 METRICS TO TRACK:

- **Total violations submitted**
- **Violations by type**
- **Violations by severity**
- **Time to fix**
- **Recurrence rate**

---

## ✅ COMPLIANCE CHECKLIST:

For each command execution:

- [ ] Command logged to database
- [ ] Output displayed with `tee`
- [ ] Exit code captured
- [ ] LLM quoted output verbatim
- [ ] LLM acknowledged errors
- [ ] Watchdog check passed
- [ ] Violations (if any) exported
- [ ] Violations submitted to bug bounty repo

