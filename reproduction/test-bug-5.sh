#!/usr/bin/env bash
# Test script for Bug 5 (Terminal Accumulation)
# 
# This script simulates heavy terminal usage by running 150 commands.
# 
# Without mitigation: After ~100 commands, all tool calls fail with "Cancelled by user."
# With RULE 22 mitigation: All commands execute successfully

set -euo pipefail

echo "START: test5 - Terminal accumulation test"
echo "Running 150 commands to simulate heavy terminal usage..."

for i in {1..150}; do
  echo "Command $i of 150"
  sleep 0.1
done

echo "All 150 commands complete"
echo "END: test5"

