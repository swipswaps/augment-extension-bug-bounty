#!/usr/bin/env bash
# ==============================================================================
# Apply Firefox Performance Optimizations
# ==============================================================================
# Version: 1.0
# Updated: 2026-02-06
# Purpose: Copy optimized user.js to Firefox profile and verify application
# ==============================================================================

set -euo pipefail

RED=$'\e[31m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'; BLUE=$'\e[34m'; RESET=$'\e[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SOURCE_USER_JS="$SCRIPT_DIR/user.js"
MOZILLA_DIR="$HOME/.mozilla/firefox"
PROFILES_INI="$MOZILLA_DIR/profiles.ini"

# ------------------------------------------------------------------------------
# Resolve active Firefox profile
# ------------------------------------------------------------------------------
resolve_profile() {
  local install_default
  install_default=$(awk -F= '/^\[Install/{i=1} i && /^Default=/{print $2; exit}' "$PROFILES_INI" || true)

  if [[ -n "$install_default" ]]; then
    echo "$install_default"
    return
  fi

  awk -F= '/^\[Profile/{p=1} p && /^Default=1/{d=1} d && /^Path=/{print $2; exit}' "$PROFILES_INI"
}

echo "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo "${BLUE}Firefox Performance Optimization Installer${RESET}"
echo "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""

# Check source file exists
if [[ ! -f "$SOURCE_USER_JS" ]]; then
  echo "${RED}ERROR: user.js not found at: $SOURCE_USER_JS${RESET}"
  exit 1
fi

# Resolve profile
PROFILE_PATH="$(resolve_profile)"
if [[ -z "$PROFILE_PATH" ]]; then
  echo "${RED}ERROR: Cannot resolve Firefox profile${RESET}"
  exit 1
fi

PROFILE_DIR="$MOZILLA_DIR/$PROFILE_PATH"
TARGET_USER_JS="$PROFILE_DIR/user.js"

echo "Source file: $SOURCE_USER_JS"
echo "Target profile: $PROFILE_PATH"
echo "Target file: $TARGET_USER_JS"
echo ""

# Check if Firefox is running
if pgrep -x firefox >/dev/null 2>&1; then
  echo "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo "${YELLOW}⚠  WARNING: Firefox is currently running!${RESET}"
  echo "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
  echo ""
  echo "Firefox MUST be completely closed for changes to take effect."
  echo ""
  read -p "Close Firefox now and press Enter to continue (or Ctrl+C to abort)..."
  
  # Wait for Firefox to close
  while pgrep -x firefox >/dev/null 2>&1; do
    echo "Waiting for Firefox to close..."
    sleep 2
  done
  
  echo "${GREEN}✓ Firefox closed${RESET}"
  echo ""
fi

# Backup existing user.js if it exists
if [[ -f "$TARGET_USER_JS" ]]; then
  BACKUP_FILE="$TARGET_USER_JS.backup.$(date +%Y%m%d_%H%M%S)"
  echo "Backing up existing user.js to:"
  echo "  $BACKUP_FILE"
  cp "$TARGET_USER_JS" "$BACKUP_FILE"
  echo "${GREEN}✓ Backup created${RESET}"
  echo ""
fi

# Copy optimized user.js
echo "Copying optimized user.js..."
cp "$SOURCE_USER_JS" "$TARGET_USER_JS"
echo "${GREEN}✓ user.js installed${RESET}"
echo ""

# Show what was applied
echo "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo "${BLUE}Critical Optimizations Applied:${RESET}"
echo "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
grep -E "gfx\.webrender\.enable-gpu-thread|dom\.ipc\.processCount|network\.prefetch-next|gfx\.gl\.multithreaded|media\.ffvpx\.enabled" "$TARGET_USER_JS" | grep "user_pref" || true
echo ""

echo "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo "${GREEN}✓ Installation Complete!${RESET}"
echo "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
echo ""
echo "Next steps:"
echo "  1. Start Firefox normally"
echo "  2. Run: ./firefox_full_performance_hud_autotune.sh"
echo "  3. Verify all preferences show ${GREEN}✓${RESET} (green checkmarks)"
echo ""
echo "Expected improvements:"
echo "  • Eliminated GPU flush delays (WaitFlushedEvent)"
echo "  • Reduced system load average"
echo "  • Smoother scrolling and tab switching"
echo "  • Lower CPU usage"
echo ""

