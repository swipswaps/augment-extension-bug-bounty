#!/usr/bin/env bash
# Test script for Bug 2 (Stream Reader Timeout) and Bug 3 (Script File Flush Race)
# 
# This script generates 20 stages of output with delays between chunks.
# 
# Bug 2 (100ms timeout): Only 5/20 stages captured
# Bug 3 (flush race): Last 1-5 lines missing
# 
# With both fixes: All 20 stages + END marker captured

set -euo pipefail

echo "START: test2"

for i in {1..20}; do
  echo "=== Stage $i ==="
  seq 1 100
  sleep 0.05
  echo "stage-$i-complete"
done

echo "All 20 stages complete"
echo "END: test2"

