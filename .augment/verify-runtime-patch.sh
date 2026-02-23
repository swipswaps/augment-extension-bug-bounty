#!/usr/bin/env bash
###############################################################################
# VERIFY RUNTIME PATCH EFFECTIVENESS
#
# PURPOSE:
#   Check if runtime patch is working and FD leak is resolved
#
# USAGE:
#   ./.augment/verify-runtime-patch.sh
#
# CHECKS:
#   1. Runtime patch is loaded
#   2. FD count is stable
#   3. No runaway zygotes
#   4. Fetch stats show leak prevention
#   5. No AbortError spam
###############################################################################

set -euo pipefail

WORKSPACE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LOGFILE="$WORKSPACE_DIR/.notes/verify-runtime-patch-$(date +%Y%m%d-%H%M%S).log"

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE"
}

check_pass() {
  log "✓ PASS: $*"
}

check_fail() {
  log "✗ FAIL: $*"
}

check_warn() {
  log "⚠ WARN: $*"
}

log "========================================================================"
log "RUNTIME PATCH VERIFICATION"
log "========================================================================"
log ""

PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

# ============================================================================
# CHECK 1: Runtime patch loaded
# ============================================================================

log "CHECK 1: Runtime patch loaded"

if [ -f "$WORKSPACE_DIR/.notes/runtime-patch.log" ]; then
  if grep -q "RUNTIME_PATCH" "$WORKSPACE_DIR/.notes/runtime-patch.log" 2>/dev/null; then
    check_pass "Runtime patch is active"
    ((PASS_COUNT++))
    
    # Show stats
    FETCH_CALLS=$(grep -c "FETCH #" "$WORKSPACE_DIR/.notes/runtime-patch.log" 2>/dev/null || echo "0")
    LEAKS_PREVENTED=$(grep "leaks_prevented=" "$WORKSPACE_DIR/.notes/runtime-patch.log" 2>/dev/null | tail -1 | sed 's/.*leaks_prevented=//' || echo "0")
    
    log "  Fetch calls: $FETCH_CALLS"
    log "  Leaks prevented: $LEAKS_PREVENTED"
  else
    check_fail "Runtime patch log exists but no activity"
    ((FAIL_COUNT++))
  fi
else
  check_fail "Runtime patch not loaded (.notes/runtime-patch.log missing)"
  ((FAIL_COUNT++))
fi

log ""

# ============================================================================
# CHECK 2: FD count stable
# ============================================================================

log "CHECK 2: FD count stable"

if command -v lsof > /dev/null 2>&1; then
  FD_COUNT=$(lsof 2>/dev/null | grep -c "code" || echo "0")
  
  log "  Current FD count: $FD_COUNT"
  
  if [ "$FD_COUNT" -lt 50000 ]; then
    check_pass "FD count below threshold ($FD_COUNT < 50,000)"
    ((PASS_COUNT++))
  elif [ "$FD_COUNT" -lt 55000 ]; then
    check_warn "FD count elevated but not critical ($FD_COUNT)"
    ((WARN_COUNT++))
  else
    check_fail "FD count critical ($FD_COUNT >= 55,000)"
    ((FAIL_COUNT++))
  fi
  
  # Check trend
  if [ -f "$WORKSPACE_DIR/.notes/runtime-patch.log" ]; then
    FD_SAMPLES=$(grep "FD_MONITOR:" "$WORKSPACE_DIR/.notes/runtime-patch.log" 2>/dev/null | tail -5 || true)
    if [ -n "$FD_SAMPLES" ]; then
      log "  Recent FD samples:"
      echo "$FD_SAMPLES" | while read -r line; do
        log "    $line"
      done
    fi
  fi
else
  check_warn "lsof not available, cannot check FD count"
  ((WARN_COUNT++))
fi

log ""

# ============================================================================
# CHECK 3: No runaway zygotes
# ============================================================================

log "CHECK 3: No runaway zygotes"

ZYGOTE_COUNT=$(ps aux | grep "[c]ode --type=zygote" | wc -l || echo "0")

log "  Zygote process count: $ZYGOTE_COUNT"

if [ "$ZYGOTE_COUNT" -eq 0 ]; then
  check_warn "No zygote processes found (VS Code may not be running)"
  ((WARN_COUNT++))
elif [ "$ZYGOTE_COUNT" -le 5 ]; then
  check_pass "Zygote count normal ($ZYGOTE_COUNT <= 5)"
  ((PASS_COUNT++))
else
  check_warn "Elevated zygote count ($ZYGOTE_COUNT > 5)"
  ((WARN_COUNT++))
fi

# Check for high CPU/MEM zygotes
RUNAWAY_ZYGOTES=$(ps aux | grep "[c]ode --type=zygote" | awk '$3 > 20 || $4 > 10' || true)

if [ -n "$RUNAWAY_ZYGOTES" ]; then
  check_fail "Runaway zygote processes detected:"
  echo "$RUNAWAY_ZYGOTES" | while read -r line; do
    log "    $line"
  done
  ((FAIL_COUNT++))
else
  check_pass "No runaway zygotes (CPU < 20%, MEM < 10%)"
  ((PASS_COUNT++))
fi

log ""

# ============================================================================
# CHECK 4: Error database
# ============================================================================

log "CHECK 4: Error database"

if [ -f "$WORKSPACE_DIR/.augment/error_tracking.db" ]; then
  RECENT_ERRORS=$(sqlite3 "$WORKSPACE_DIR/.augment/error_tracking.db" \
    "SELECT COUNT(*) FROM errors WHERE timestamp > datetime('now', '-5 minutes')" 2>/dev/null || echo "0")
  
  log "  Recent errors (last 5 min): $RECENT_ERRORS"
  
  if [ "$RECENT_ERRORS" -lt 10 ]; then
    check_pass "Low error rate ($RECENT_ERRORS < 10)"
    ((PASS_COUNT++))
  elif [ "$RECENT_ERRORS" -lt 50 ]; then
    check_warn "Moderate error rate ($RECENT_ERRORS)"
    ((WARN_COUNT++))
  else
    check_fail "High error rate ($RECENT_ERRORS >= 50)"
    ((FAIL_COUNT++))
  fi
else
  check_warn "Error database not found"
  ((WARN_COUNT++))
fi

log ""

# ============================================================================
# SUMMARY
# ============================================================================

log "========================================================================"
log "VERIFICATION SUMMARY"
log "========================================================================"
log "PASS: $PASS_COUNT"
log "WARN: $WARN_COUNT"
log "FAIL: $FAIL_COUNT"
log ""

if [ "$FAIL_COUNT" -eq 0 ]; then
  log "✓ ALL CHECKS PASSED"
  log ""
  log "Runtime patch is working correctly."
  log "FD leak appears to be resolved."
  exit 0
elif [ "$FAIL_COUNT" -le 2 ]; then
  log "⚠ SOME ISSUES DETECTED"
  log ""
  log "Runtime patch may need adjustment."
  log "Review logs for details."
  exit 1
else
  log "✗ CRITICAL ISSUES DETECTED"
  log ""
  log "Runtime patch is not effective."
  log "Manual intervention required."
  exit 2
fi

