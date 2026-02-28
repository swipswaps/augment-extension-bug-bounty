#!/usr/bin/env bash
###############################################################################
# LIFECYCLE FIX VERIFICATION SCRIPT
#
# PURPOSE:
#   Verify that lifecycle fixes are working correctly by:
#   1. Checking FD count before/after
#   2. Monitoring latch reset behavior
#   3. Verifying stream cleanup
#   4. Checking for runaway zygote
#
# USAGE:
#   ./.augment/verify-lifecycle-fix.sh
###############################################################################

set -euo pipefail

LOGFILE=".notes/lifecycle-verification-$(date +%Y%m%d-%H%M%S).log"

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE"
}

log "========================================================================"
log "LIFECYCLE FIX VERIFICATION STARTING"
log "========================================================================"

###############################################################################
# PHASE 1: PRE-CHECK
###############################################################################

log ""
log "PHASE 1: Pre-check system state"
log "------------------------------------------------------------------------"

# Check if extension is patched
EXTENSION_PATH="$HOME/.vscode/extensions/augment.vscode-augment-0.792.0/out/extension.js"

if [ ! -f "$EXTENSION_PATH" ]; then
  log "ERROR: Extension not found at $EXTENSION_PATH"
  exit 1
fi

# Check for backup
BACKUP_COUNT=$(find "$HOME/.vscode/extensions/augment.vscode-augment-0.792.0/out/" -name "extension.js.backup-lifecycle-fix-*" 2>/dev/null | wc -l)
log "Backup files found: $BACKUP_COUNT"

if [ "$BACKUP_COUNT" -eq 0 ]; then
  log "WARNING: No backup found - extension may not be patched yet"
fi

# Get current FD count
FD_COUNT=$(lsof 2>/dev/null | grep -c "code" || echo "0")
log "Current FD count: $FD_COUNT"

if [ "$FD_COUNT" -gt 50000 ]; then
  log "⚠ WARNING: FD count exceeds threshold (50,000)"
  log "⚠ Recommend reloading VS Code before testing"
fi

###############################################################################
# PHASE 2: CHECK INSTRUMENTATION
###############################################################################

log ""
log "PHASE 2: Check instrumentation logs"
log "------------------------------------------------------------------------"

if [ -f ".notes/lifecycle-guard.log" ]; then
  GUARD_LOG_SIZE=$(wc -l < ".notes/lifecycle-guard.log")
  log "Lifecycle guard log entries: $GUARD_LOG_SIZE"
  
  # Show recent entries
  log "Recent guard log entries:"
  tail -10 ".notes/lifecycle-guard.log" | while read -r line; do
    log "  $line"
  done
else
  log "⚠ No lifecycle-guard.log found - instrumentation may not be active"
fi

###############################################################################
# PHASE 3: CHECK FOR LATCH RESETS
###############################################################################

log ""
log "PHASE 3: Check for latch reset behavior"
log "------------------------------------------------------------------------"

if [ -f ".notes/lifecycle-guard.log" ]; then
  LATCH_RESETS=$(grep -c "latch reset complete" ".notes/lifecycle-guard.log" || echo "0")
  CLOSE_CALLS=$(grep -c "close: called" ".notes/lifecycle-guard.log" || echo "0")
  
  log "close() calls: $CLOSE_CALLS"
  log "Latch resets: $LATCH_RESETS"
  
  if [ "$CLOSE_CALLS" -gt 0 ] && [ "$LATCH_RESETS" -eq "$CLOSE_CALLS" ]; then
    log "✓ All close() calls properly reset latch"
  elif [ "$CLOSE_CALLS" -gt 0 ]; then
    log "⚠ WARNING: Some close() calls did not reset latch"
    log "  close() calls: $CLOSE_CALLS"
    log "  Latch resets: $LATCH_RESETS"
  fi
fi

###############################################################################
# PHASE 4: CHECK FOR STREAM CLEANUP
###############################################################################

log ""
log "PHASE 4: Check for stream cleanup"
log "------------------------------------------------------------------------"

if [ -f ".notes/lifecycle-guard.log" ]; then
  STREAM_CLEANUPS=$(grep -c "cleanup complete" ".notes/lifecycle-guard.log" || echo "0")
  log "Stream cleanups: $STREAM_CLEANUPS"
  
  if [ "$STREAM_CLEANUPS" -gt 0 ]; then
    log "✓ Stream cleanup is active"
  else
    log "⚠ No stream cleanups detected yet"
  fi
fi

###############################################################################
# PHASE 5: CHECK FOR RUNAWAY ZYGOTE
###############################################################################

log ""
log "PHASE 5: Check for runaway zygote processes"
log "------------------------------------------------------------------------"

ZYGOTE_COUNT=$(ps aux | grep -c "[c]ode --type=zygote" || echo "0")
log "Zygote processes: $ZYGOTE_COUNT"

if [ "$ZYGOTE_COUNT" -gt 5 ]; then
  log "⚠ WARNING: Multiple zygote processes detected"
  ps aux | grep "[c]ode --type=zygote" | while read -r line; do
    log "  $line"
  done
else
  log "✓ Zygote process count is normal"
fi

###############################################################################
# PHASE 6: FD BREAKDOWN
###############################################################################

log ""
log "PHASE 6: File descriptor breakdown"
log "------------------------------------------------------------------------"

log "FD breakdown by type:"
lsof 2>/dev/null | grep "code" | awk '{print $5}' | sort | uniq -c | sort -rn | head -10 | while read -r count type; do
  log "  $count $type"
done

###############################################################################
# PHASE 7: CHECK ERROR DATABASE
###############################################################################

log ""
log "PHASE 7: Check error database for recent issues"
log "------------------------------------------------------------------------"

if [ -f ".augment/error_tracking.db" ]; then
  log "Recent errors (last 10):"
  sqlite3 .augment/error_tracking.db "SELECT timestamp, error_type, COUNT(*) as count FROM errors WHERE timestamp > datetime('now', '-1 hour') GROUP BY error_type ORDER BY count DESC LIMIT 10;" 2>/dev/null | while read -r line; do
    log "  $line"
  done || log "  (No recent errors or database query failed)"
else
  log "⚠ Error tracking database not found"
fi

###############################################################################
# PHASE 8: RECOMMENDATIONS
###############################################################################

log ""
log "PHASE 8: Recommendations"
log "------------------------------------------------------------------------"

if [ "$FD_COUNT" -gt 50000 ]; then
  log "⚠ RECOMMENDATION: Reload VS Code to clear accumulated FDs"
  log "  Command: Ctrl+Shift+P → 'Developer: Reload Window'"
fi

if [ "$BACKUP_COUNT" -eq 0 ]; then
  log "⚠ RECOMMENDATION: Apply lifecycle patches"
  log "  Command: node .augment/apply-lifecycle-fixes.js"
fi

if [ ! -f ".notes/lifecycle-guard.log" ]; then
  log "⚠ RECOMMENDATION: Ensure lifecycle guard module is loaded"
  log "  Check that extension is using the patched version"
fi

###############################################################################
# SUMMARY
###############################################################################

log ""
log "========================================================================"
log "VERIFICATION COMPLETE"
log "========================================================================"
log "Results saved to: $LOGFILE"
log ""
log "Next steps:"
log "1. Review this log for warnings"
log "2. Monitor FD count over next hour: watch -n 60 'lsof 2>/dev/null | grep -c code'"
log "3. Check lifecycle-guard.log for latch resets"
log "4. If FD count stabilizes below 50K, fix is working"
log ""

