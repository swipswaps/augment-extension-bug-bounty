#!/bin/bash
# Cleanup Old Log Files - Prevents memory bloat from accumulated logs
# Run this periodically to keep .notes/ directory clean

set -euo pipefail

NOTES_DIR=".notes"
MAX_LOG_FILES=20  # Keep only the 20 most recent log files

echo "🧹 CLEANUP: Removing old log files from $NOTES_DIR"

# Count current log files
CURRENT_COUNT=$(find "$NOTES_DIR" -name "*.log" -type f 2>/dev/null | wc -l)
echo "📊 Current log files: $CURRENT_COUNT"

if [ "$CURRENT_COUNT" -le "$MAX_LOG_FILES" ]; then
    echo "✅ Log count is acceptable ($CURRENT_COUNT <= $MAX_LOG_FILES)"
    exit 0
fi

# Delete old log files, keep only the 20 most recent
echo "🗑️  Deleting old log files (keeping $MAX_LOG_FILES most recent)..."

# Find all log files, sort by modification time (oldest first), delete all except last 20
find "$NOTES_DIR" -name "*.log" -type f -printf '%T+ %p\n' 2>/dev/null | \
    sort | \
    head -n -"$MAX_LOG_FILES" | \
    cut -d' ' -f2- | \
    xargs -r rm -f

# Count remaining log files
REMAINING_COUNT=$(find "$NOTES_DIR" -name "*.log" -type f 2>/dev/null | wc -l)
DELETED_COUNT=$((CURRENT_COUNT - REMAINING_COUNT))

echo "✅ Deleted $DELETED_COUNT old log files"
echo "📊 Remaining log files: $REMAINING_COUNT"
echo "💾 Disk space freed: $(du -sh "$NOTES_DIR" 2>/dev/null | cut -f1)"

exit 0

