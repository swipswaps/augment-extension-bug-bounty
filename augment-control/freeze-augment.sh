#!/usr/bin/env bash

EXT_DIR="$HOME/.vscode/extensions"
BACKUP_DIR="$HOME/augment-backups"
mkdir -p "$BACKUP_DIR"

ACTIVE=$(ls -d $EXT_DIR/augment.vscode-augment-* | sort -V | tail -1)

if [ -z "$ACTIVE" ]; then
    echo "Augment extension not found."
    exit 1
fi

echo "Active extension:"
echo "$ACTIVE"

STAMP=$(date +%F-%H%M%S)

cp -r "$ACTIVE" "$BACKUP_DIR/$(basename $ACTIVE)-$STAMP"

echo "Backup created at:"
echo "$BACKUP_DIR/$(basename $ACTIVE)-$STAMP"
