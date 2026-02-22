#!/bin/bash
# monitor-fd-leak.sh - Continuous FD leak monitoring and reporting
# 
# PURPOSE: Track file descriptor leak in real-time and identify leak sources
# WHY: FD leak from getRemoteAgentOverviewsStream causes system instability
# HOW: Poll lsof every 60 seconds, log FD count, identify top FD consumers

set -euo pipefail

LOGFILE=".notes/fd-leak-monitor-$(date +%Y%m%d-%H%M%S).log"
DB=".augment/error_tracking.db"
THRESHOLD=50000
CRITICAL_THRESHOLD=55000

echo "START: FD leak monitoring at $(date)" | tee -a "$LOGFILE"
echo "Logging to: $LOGFILE"
echo "Database: $DB"
echo "Threshold: $THRESHOLD FDs"
echo "Critical threshold: $CRITICAL_THRESHOLD FDs"
echo ""

# Function to get FD count
get_fd_count() {
    lsof 2>/dev/null | grep -c code || echo 0
}

# Function to get FD breakdown by type
get_fd_breakdown() {
    lsof -n 2>/dev/null | grep code | awk '{
        for(i=1;i<=NF;i++) {
            if($i~/^(REG|DIR|CHR|FIFO|unix|IPv4|IPv6|sock|pipe|a_inode|netlink)$/) {
                print $i
            }
        }
    }' | sort | uniq -c | sort -rn
}

# Function to get top FD consumers
get_top_consumers() {
    lsof -n 2>/dev/null | grep code | awk '{
        cmd=$1; pid=$2; fd=""; type="";
        for(i=3;i<=NF;i++) {
            if($i~/^[0-9]+[urw]$/) fd=$i;
            if($i~/^(REG|DIR|CHR|FIFO|unix|IPv4|IPv6|sock|pipe|a_inode|netlink)$/) type=$i
        }
        if(fd && type) print cmd, pid, fd, type
    }' | sort | uniq -c | sort -rn | head -10
}

# Main monitoring loop
iteration=0
while true; do
    iteration=$((iteration + 1))
    timestamp=$(date +%Y-%m-%dT%H:%M:%S)
    
    echo "================================================================" | tee -a "$LOGFILE"
    echo "[$timestamp] Iteration $iteration" | tee -a "$LOGFILE"
    echo "================================================================" | tee -a "$LOGFILE"
    
    # Get current FD count
    fd_count=$(get_fd_count)
    echo "Total FD count: $fd_count" | tee -a "$LOGFILE"
    
    # Check if above threshold
    if [ "$fd_count" -gt "$THRESHOLD" ]; then
        echo "⚠️  WARNING: FD count ($fd_count) exceeds threshold ($THRESHOLD)" | tee -a "$LOGFILE"
        
        # Log to database
        sqlite3 "$DB" "INSERT INTO errors (timestamp, error_type, error_message, stack_trace) VALUES ('$timestamp', 'fd_leak_warning', 'File descriptor count: $fd_count (threshold: $THRESHOLD)', 'monitor-fd-leak.sh iteration $iteration');" 2>/dev/null || true
        
        # Get FD breakdown
        echo "" | tee -a "$LOGFILE"
        echo "FD breakdown by type:" | tee -a "$LOGFILE"
        get_fd_breakdown | tee -a "$LOGFILE"
        
        # Get top consumers
        echo "" | tee -a "$LOGFILE"
        echo "Top 10 FD consumers:" | tee -a "$LOGFILE"
        get_top_consumers | tee -a "$LOGFILE"
        
        # Check if critical
        if [ "$fd_count" -gt "$CRITICAL_THRESHOLD" ]; then
            echo "" | tee -a "$LOGFILE"
            echo "🚨 CRITICAL: FD count ($fd_count) exceeds critical threshold ($CRITICAL_THRESHOLD)" | tee -a "$LOGFILE"
            echo "🚨 ACTION REQUIRED: Reload VS Code immediately to prevent system crash" | tee -a "$LOGFILE"
            
            # Log critical event to database
            sqlite3 "$DB" "INSERT INTO errors (timestamp, error_type, error_message, stack_trace) VALUES ('$timestamp', 'fd_leak_critical', 'CRITICAL: File descriptor count: $fd_count (critical threshold: $CRITICAL_THRESHOLD)', 'monitor-fd-leak.sh iteration $iteration - RELOAD REQUIRED');" 2>/dev/null || true
        fi
    else
        echo "✅ FD count within normal range" | tee -a "$LOGFILE"
    fi
    
    echo "" | tee -a "$LOGFILE"
    
    # Sleep for 60 seconds
    sleep 60
done

