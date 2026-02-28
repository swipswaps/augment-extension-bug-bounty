#!/usr/bin/env bash
# Comprehensive Backup and Restore System for Augment Extension

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_ROOT="$SCRIPT_DIR/backups"

show_usage() {
    cat << EOF
╔════════════════════════════════════════════════════════════════════════════╗
║                    AUGMENT BACKUP/RESTORE SYSTEM                           ║
╚════════════════════════════════════════════════════════════════════════════╝

USAGE:
  $0 backup [version]    - Create full backup of extension
  $0 list                - List all backups
  $0 restore <backup>    - Restore from backup
  $0 diff <backup>       - Show differences from backup

EXAMPLES:
  $0 backup              - Backup active version
  $0 backup 0.754.3      - Backup specific version
  $0 list                - Show all backups
  $0 restore backup-0.779.0-2026-02-12-173000
  $0 diff backup-0.779.0-2026-02-12-173000

EOF
}

get_active_version() {
    code --list-extensions --show-versions 2>/dev/null | grep augment | cut -d'@' -f2
}

create_backup() {
    local VERSION="${1:-$(get_active_version)}"
    local EXT_DIR="$HOME/.vscode/extensions/augment.vscode-augment-$VERSION"
    
    if [ ! -d "$EXT_DIR" ]; then
        echo "❌ Extension directory not found: $EXT_DIR"
        exit 1
    fi
    
    local STAMP=$(date +%F-%H%M%S)
    local BACKUP_DIR="$BACKUP_ROOT/backup-$VERSION-$STAMP"
    
    mkdir -p "$BACKUP_DIR"
    
    echo "Creating backup of version $VERSION..."
    echo "Source: $EXT_DIR"
    echo "Destination: $BACKUP_DIR"
    echo ""
    
    # Copy entire extension
    cp -r "$EXT_DIR" "$BACKUP_DIR/extension"
    
    # Create metadata
    cat > "$BACKUP_DIR/metadata.txt" << METADATA
Backup created: $(date)
Version: $VERSION
Source: $EXT_DIR
Hostname: $(hostname)
User: $(whoami)
METADATA
    
    # Create checksums
    find "$BACKUP_DIR/extension" -type f -exec sha256sum {} \; > "$BACKUP_DIR/checksums.txt"
    
    echo "✅ Backup created: $BACKUP_DIR"
    echo ""
    echo "Files backed up: $(find "$BACKUP_DIR/extension" -type f | wc -l)"
    echo "Total size: $(du -sh "$BACKUP_DIR" | cut -f1)"
}

list_backups() {
    if [ ! -d "$BACKUP_ROOT" ]; then
        echo "No backups found"
        return
    fi
    
    echo "Available backups:"
    echo ""
    
    for backup in "$BACKUP_ROOT"/backup-*; do
        if [ -d "$backup" ]; then
            local NAME=$(basename "$backup")
            local SIZE=$(du -sh "$backup" 2>/dev/null | cut -f1)
            local DATE=$(grep "Backup created:" "$backup/metadata.txt" 2>/dev/null | cut -d: -f2- || echo "unknown")
            
            echo "📦 $NAME"
            echo "   Size: $SIZE"
            echo "   Date:$DATE"
            echo ""
        fi
    done
}

restore_backup() {
    local BACKUP_NAME="$1"
    local BACKUP_DIR="$BACKUP_ROOT/$BACKUP_NAME"
    
    if [ ! -d "$BACKUP_DIR" ]; then
        echo "❌ Backup not found: $BACKUP_DIR"
        exit 1
    fi
    
    # Extract version from backup name
    local VERSION=$(echo "$BACKUP_NAME" | sed 's/backup-\([0-9.]*\)-.*/\1/')
    local EXT_DIR="$HOME/.vscode/extensions/augment.vscode-augment-$VERSION"
    
    echo "⚠️  WARNING: This will replace the current extension!"
    echo "Backup: $BACKUP_DIR"
    echo "Target: $EXT_DIR"
    echo ""
    read -p "Continue? (yes/no): " CONFIRM
    
    if [ "$CONFIRM" != "yes" ]; then
        echo "Cancelled"
        exit 0
    fi
    
    # Create safety backup of current state
    if [ -d "$EXT_DIR" ]; then
        local SAFETY_BACKUP="$EXT_DIR.before-restore-$(date +%F-%H%M%S)"
        echo "Creating safety backup: $SAFETY_BACKUP"
        cp -r "$EXT_DIR" "$SAFETY_BACKUP"
    fi
    
    # Restore
    echo "Restoring..."
    rm -rf "$EXT_DIR"
    cp -r "$BACKUP_DIR/extension" "$EXT_DIR"
    
    echo "✅ Restore complete"
    echo "⚠️  RESTART VS Code for changes to take effect"
}

show_diff() {
    local BACKUP_NAME="$1"
    local BACKUP_DIR="$BACKUP_ROOT/$BACKUP_NAME"
    
    if [ ! -d "$BACKUP_DIR" ]; then
        echo "❌ Backup not found: $BACKUP_DIR"
        exit 1
    fi
    
    local VERSION=$(echo "$BACKUP_NAME" | sed 's/backup-\([0-9.]*\)-.*/\1/')
    local EXT_DIR="$HOME/.vscode/extensions/augment.vscode-augment-$VERSION"
    
    echo "Comparing current extension with backup..."
    echo ""
    
    diff -r "$BACKUP_DIR/extension" "$EXT_DIR" || true
}

# Main
case "${1:-}" in
    backup)
        create_backup "${2:-}"
        ;;
    list)
        list_backups
        ;;
    restore)
        if [ -z "${2:-}" ]; then
            echo "❌ Backup name required"
            show_usage
            exit 1
        fi
        restore_backup "$2"
        ;;
    diff)
        if [ -z "${2:-}" ]; then
            echo "❌ Backup name required"
            show_usage
            exit 1
        fi
        show_diff "$2"
        ;;
    *)
        show_usage
        exit 1
        ;;
esac

