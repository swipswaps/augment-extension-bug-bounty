#!/usr/bin/env bash

echo "=== VS Code Sandbox Detection ==="

CODE_PID=$(pgrep -n code)

if [ -z "$CODE_PID" ]; then
    echo "VS Code not running."
    exit 1
fi

echo "VS Code PID: $CODE_PID"

echo
echo "Process flags:"
grep -E "Name:|NoNewPrivs:" /proc/$CODE_PID/status

echo
echo "Terminal flag (current shell):"
grep NoNewPrivs /proc/self/status

if grep -q "NoNewPrivs:\s*1" /proc/$CODE_PID/status; then
    echo
    echo "Sandbox is ENABLED."
    echo "sudo will NOT work inside VS Code terminal."
else
    echo
    echo "Sandbox is DISABLED."
fi
