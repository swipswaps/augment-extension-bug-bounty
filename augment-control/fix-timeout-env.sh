#!/bin/bash
# Fix Method 1: Increase Tool Execution Timeout (Environment Variable)
# Difficulty: Easy | Risk: Low | Effectiveness: Medium

echo "=== Augment Extension Timeout Fix (Environment Variable) ==="
echo ""
echo "This script sets environment variables to increase tool execution timeouts."
echo ""

# Set environment variables
export AUGMENT_TOOL_TIMEOUT_MS=300000  # 5 minutes
export AUGMENT_MCP_TIMEOUT_MS=300000   # 5 minutes
export AUGMENT_COMPLETION_TIMEOUT_MS=300000  # 5 minutes

echo "Environment variables set:"
echo "  AUGMENT_TOOL_TIMEOUT_MS=$AUGMENT_TOOL_TIMEOUT_MS"
echo "  AUGMENT_MCP_TIMEOUT_MS=$AUGMENT_MCP_TIMEOUT_MS"
echo "  AUGMENT_COMPLETION_TIMEOUT_MS=$AUGMENT_COMPLETION_TIMEOUT_MS"
echo ""

# Launch VS Code with these environment variables
echo "Launching VS Code with extended timeouts..."
code

echo ""
echo "VS Code launched. If this doesn't work, try Method 4 (monkey patch)."

