#!/usr/bin/env bash

SETTINGS="$HOME/.config/Code/User/settings.json"

mkdir -p "$(dirname "$SETTINGS")"

if [ ! -f "$SETTINGS" ]; then
    echo "{}" > "$SETTINGS"
fi

TMP=$(mktemp)

jq '. + {
  "chat.tools.terminal.sandbox.enabled": false
}' "$SETTINGS" > "$TMP" && mv "$TMP" "$SETTINGS"

echo "Sandbox disabled in settings."
echo "Restart VS Code completely."
