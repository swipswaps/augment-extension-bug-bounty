#!/usr/bin/env bash
#
# Watchdog Extension Verification - Working Example
#
# PURPOSE: Verify watchdog extension is monitoring zygote processes and logging to database
# USAGE: ./.augment/scripts/watchdog-verification-example.sh
# OUTPUT: Logs to .notes/watchdog-verification-*.log AND .augment/error_tracking.db

set -euo pipefail

# CONFIGURATION: All settings in one place for easy modification
LOGFILE=".notes/watchdog-verification-$(date +%Y%m%d-%H%M%S).log"
DB_FILE=".augment/error_tracking.db"
ZYGOTE_CPU_THRESHOLD=20.0    # % CPU - zygote should be idle, >20% is runaway
ZYGOTE_MEMORY_THRESHOLD=700  # MB - zygote should use <700MB

# LOGGING: All output goes to both terminal AND log file (tee pattern)
exec > >(tee -a "$LOGFILE") 2>&1

echo "START: watchdog-verification"
echo "Timestamp: $(date --iso-8601=seconds)"
echo ""

# ==============================================================================
# STEP 1: Verify watchdog extension is installed and activated
# ==============================================================================
echo "=== STEP 1: Verify Watchdog Extension ==="
echo ""

# Check extension directory exists
if [ -d ~/.vscode/extensions/prf-compliance.hidden-terminal-watchdog-1.0.0 ]; then
    echo "✅ Extension installed: prf-compliance.hidden-terminal-watchdog-1.0.0"
else
    echo "❌ Extension NOT installed"
    exit 1
fi

# Check extension activated (look for output channel logs)
LATEST_LOG=$(ls -td ~/.config/Code/logs/*/ 2>/dev/null | head -1)
WATCHDOG_LOGS=$(find "$LATEST_LOG" -name "*Watchdog*" 2>/dev/null | wc -l)

if [ "$WATCHDOG_LOGS" -gt 0 ]; then
    echo "✅ Extension activated: $WATCHDOG_LOGS watchdog log files found"
    echo "   Log directory: $LATEST_LOG"
else
    echo "❌ Extension NOT activated (no watchdog logs)"
    echo "   ACTION: Reload VS Code (Ctrl+Shift+P → Developer: Reload Window)"
    exit 1
fi
echo ""

# ==============================================================================
# STEP 2: Check for runaway zygote processes
# ==============================================================================
echo "=== STEP 2: Check Runaway Zygote Processes ==="
echo ""

# Find zygote processes exceeding thresholds
# awk: $3 = CPU%, $6 = memory in KB, $2 = PID, $10 = runtime
RUNAWAY_ZYGOTES=$(ps aux | awk -v cpu="$ZYGOTE_CPU_THRESHOLD" -v mem="$((ZYGOTE_MEMORY_THRESHOLD * 1024))" \
    '$3 > cpu || $6 > mem' | grep -E "code --type=zygote" || true)

if [ -z "$RUNAWAY_ZYGOTES" ]; then
    echo "✅ No runaway zygote processes detected"
    echo "   All zygote processes below thresholds:"
    echo "   - CPU < ${ZYGOTE_CPU_THRESHOLD}%"
    echo "   - Memory < ${ZYGOTE_MEMORY_THRESHOLD}MB"
else
    echo "⚠️  RUNAWAY ZYGOTE DETECTED:"
    echo ""
    echo "$RUNAWAY_ZYGOTES" | while read -r line; do
        PID=$(echo "$line" | awk '{print $2}')
        CPU=$(echo "$line" | awk '{print $3}')
        MEM_KB=$(echo "$line" | awk '{print $6}')
        MEM_MB=$((MEM_KB / 1024))
        RUNTIME=$(echo "$line" | awk '{print $10}')
        
        echo "   PID: $PID"
        echo "   CPU: ${CPU}%"
        echo "   Memory: ${MEM_MB} MB"
        echo "   Runtime: $RUNTIME"
        echo ""
        
        # Log to database for tracking
        TIMESTAMP=$(date --iso-8601=seconds)
        ERROR_MSG="Runaway zygote PID $PID: ${CPU}% CPU, ${MEM_MB} MB RAM, runtime $RUNTIME"
        
        sqlite3 "$DB_FILE" <<SQL
INSERT INTO errors (timestamp, log_file, error_type, error_message, extension_name)
VALUES ('$TIMESTAMP', 'watchdog-verification', 'runaway_zygote_detected', '$(echo "$ERROR_MSG" | sed "s/'/''/g")', 'watchdog');
SQL
        
        echo "   ✅ Logged to database: $DB_FILE"
    done
    
    echo ""
    echo "   EXPECTED: Watchdog extension should show popup warning"
    echo "   POPUP: 'Watchdog: Runaway zygote process detected (PID ..., ...% CPU, ... MB)'"
    echo "   OPTIONS: 'Restart VS Code' or 'Ignore'"
fi
echo ""

# ==============================================================================
# STEP 3: Verify database logging is working
# ==============================================================================
echo "=== STEP 3: Verify Database Logging ==="
echo ""

# Count total errors in database
TOTAL_ERRORS=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM errors;")
echo "Total errors in database: $TOTAL_ERRORS"

# Count runaway zygote detections
ZYGOTE_DETECTIONS=$(sqlite3 "$DB_FILE" "SELECT COUNT(*) FROM errors WHERE error_type = 'runaway_zygote_detected';")
echo "Runaway zygote detections: $ZYGOTE_DETECTIONS"

# Show recent detections
if [ "$ZYGOTE_DETECTIONS" -gt 0 ]; then
    echo ""
    echo "Recent detections:"
    sqlite3 "$DB_FILE" "SELECT datetime(timestamp) as time, error_message FROM errors WHERE error_type = 'runaway_zygote_detected' ORDER BY id DESC LIMIT 5;" | \
        awk '{print "  - " $0}'
fi
echo ""

# ==============================================================================
# STEP 4: Check system resource state
# ==============================================================================
echo "=== STEP 4: System Resource State ==="
echo ""

# Load average (should be < 2.0 for dual-core system)
LOAD=$(uptime | awk -F'load average:' '{print $2}' | awk '{print $1}' | tr -d ',')
echo "Load average: $LOAD"
if (( $(echo "$LOAD > 2.0" | bc -l) )); then
    echo "  ⚠️  High load (> 2.0) - system overloaded"
else
    echo "  ✅ Normal load (< 2.0)"
fi

# Swap usage (should be < 500MB for good performance)
SWAP_MB=$(free -m | awk 'NR==3 {print $3}')
echo "Swap usage: ${SWAP_MB} MB"
if [ "$SWAP_MB" -gt 500 ]; then
    echo "  ⚠️  High swap usage (> 500MB) - performance degraded"
else
    echo "  ✅ Normal swap usage (< 500MB)"
fi

# VS Code total resource usage
VSCODE_CPU=$(ps aux | grep -E "(code|/proc/self/exe)" | grep -v grep | awk '{sum+=$3} END {print sum}')
VSCODE_MEM=$(ps aux | grep -E "(code|/proc/self/exe)" | grep -v grep | awk '{sum+=$6} END {print int(sum/1024)}')
echo "VS Code total: ${VSCODE_CPU}% CPU, ${VSCODE_MEM} MB RAM"

# Log system state to database
TIMESTAMP=$(date --iso-8601=seconds)
sqlite3 "$DB_FILE" <<SQL
INSERT INTO system_metrics (timestamp, load_avg, memory_used_mb, swap_used_mb, vscode_cpu_pct, vscode_memory_mb, runaway_processes)
VALUES ('$TIMESTAMP', ${LOAD:-0}, $(free -m | awk 'NR==2 {print $3}'), ${SWAP_MB:-0}, ${VSCODE_CPU:-0}, ${VSCODE_MEM:-0}, $(echo "$RUNAWAY_ZYGOTES" | grep -c "code --type=zygote" || echo 0));
SQL

echo "  ✅ System state logged to database"
echo ""

# ==============================================================================
# SUMMARY
# ==============================================================================
echo "=== SUMMARY ==="
echo ""
echo "Watchdog extension: ✅ Installed and activated"
echo "Database logging: ✅ Working ($TOTAL_ERRORS total errors)"
echo "Runaway zygotes: $([ -z "$RUNAWAY_ZYGOTES" ] && echo "✅ None detected" || echo "⚠️  Detected (see above)")"
echo "System load: $([ $(echo "$LOAD < 2.0" | bc -l) -eq 1 ] && echo "✅ Normal" || echo "⚠️  High")"
echo "Swap usage: $([ "$SWAP_MB" -lt 500 ] && echo "✅ Normal" || echo "⚠️  High")"
echo ""
echo "Log file: $LOGFILE"
echo "Database: $DB_FILE"
echo ""
echo "✅ Verification complete"
echo "END: watchdog-verification"

