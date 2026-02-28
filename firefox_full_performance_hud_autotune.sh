#!/usr/bin/env bash
# ==============================================================================
# Firefox Full Performance HUD + Autotune + Authoritative Runtime Diagnostics
# WebGL / WebRender / VAAPI / MOZ_LOG / Profile-Safe
# ==============================================================================
# Version: 2.0
# Updated: 2026-02-06
# Optimized for: X11 + Mesa + xfwm4 (GPU threading contention monitoring)
# ==============================================================================
set -euo pipefail
IFS=$'\n\t'

REFRESH_INTERVAL=5
MOZILLA_DIR="$HOME/.mozilla/firefox"
PROFILES_INI="$MOZILLA_DIR/profiles.ini"
STATE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/firefox-hud"
mkdir -p "$STATE_DIR"

SUPPORT_TEXT="$STATE_DIR/about_support.txt"
MOZLOG_DUMP="$STATE_DIR/mozlog_graphics.txt"

RED=$'\e[31m'; GREEN=$'\e[32m'; YELLOW=$'\e[33m'; RESET=$'\e[0m'

# ------------------------------------------------------------------------------
# Resolve ACTIVE Firefox profile (Install-locked aware)
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

PROFILE_PATH="$(resolve_profile)"
[[ -n "$PROFILE_PATH" ]] || { echo "ERROR: Cannot resolve Firefox profile"; exit 1; }

PROFILE_DIR="$MOZILLA_DIR/$PROFILE_PATH"
USER_JS="$PROFILE_DIR/user.js"

# ------------------------------------------------------------------------------
# Enforce WebGL native OpenGL
# ------------------------------------------------------------------------------
mkdir -p "$PROFILE_DIR"
touch "$USER_JS"

grep -q 'webgl.prefer-native-gl' "$USER_JS" || cat >>"$USER_JS" <<'EOF'
user_pref("webgl.prefer-native-gl", true);
EOF

# ------------------------------------------------------------------------------
# Critical Performance Preferences (X11 + Mesa optimization)
# ------------------------------------------------------------------------------
declare -A CRITICAL_PREFS=(
  ["gfx.webrender.enable-gpu-thread"]="false"
  ["gfx.gl.multithreaded"]="false"
  ["dom.ipc.processCount"]="4"
  ["dom.ipc.processCount.web"]="4"
  ["gfx.webrender.wait-for-gpu"]="false"
  ["media.ffvpx.enabled"]="true"
  ["network.prefetch-next"]="true"
)

# ------------------------------------------------------------------------------
# Auto-apply critical preferences to user.js if missing
# ------------------------------------------------------------------------------
apply_critical_prefs() {
  local needs_update=0

  for pref in "${!CRITICAL_PREFS[@]}"; do
    expected="${CRITICAL_PREFS[$pref]}"
    if ! grep -q "user_pref(\"$pref\"" "$USER_JS" 2>/dev/null; then
      echo "user_pref(\"$pref\", $expected);" >> "$USER_JS"
      needs_update=1
    fi
  done

  if [[ $needs_update -eq 1 ]]; then
    echo "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo "${YELLOW}⚠  CRITICAL: user.js was updated with missing preferences${RESET}"
    echo "${YELLOW}⚠  You MUST restart Firefox for changes to take effect${RESET}"
    echo "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo ""
    read -p "Press Enter to continue monitoring (or Ctrl+C to restart Firefox now)..."
  fi
}

apply_critical_prefs

# ------------------------------------------------------------------------------
# Check if Firefox is already running (use real display)
# ------------------------------------------------------------------------------
if ! pgrep -x firefox >/dev/null 2>&1; then
  echo "${YELLOW}WARNING: Firefox is not running. Start Firefox first.${RESET}"
  echo "This HUD monitors a running Firefox instance."
  echo ""
  echo "To start Firefox with MOZ_LOG enabled:"
  echo "  MOZ_LOG=\"Graphics:5\" MOZ_LOG_FILE=\"$MOZLOG_DUMP\" firefox &"
  echo ""
  read -p "Press Enter to continue monitoring (or Ctrl+C to exit)..."
fi

# ------------------------------------------------------------------------------
# Detect about:support data (if available)
# ------------------------------------------------------------------------------
# Try to find about:support JSON from Firefox profile
SUPPORT_JSON="$PROFILE_DIR/datareporting/archived"
if [[ -d "$SUPPORT_JSON" ]]; then
  # Firefox stores telemetry data here, but about:support is runtime-only
  # We'll extract what we can from prefs.js and system
  :
fi

# ------------------------------------------------------------------------------
# HUD Loop
# ------------------------------------------------------------------------------
while true; do
  clear
  echo "=============================================="
  echo "Firefox Performance HUD (Authoritative)"
  echo "Profile : $PROFILE_PATH"
  echo "user.js : $USER_JS"
  echo "=============================================="

  echo
  echo "System Graphics Info:"
  echo "  Display: ${DISPLAY:-<not set>}"
  echo "  Session: ${XDG_SESSION_TYPE:-<not set>}"

  if command -v glxinfo >/dev/null 2>&1; then
    echo "  OpenGL Renderer: $(glxinfo 2>/dev/null | grep -m1 "OpenGL renderer" | cut -d: -f2 | xargs || echo '<glxinfo failed>')"
    echo "  OpenGL Version: $(glxinfo 2>/dev/null | grep -m1 "OpenGL version" | cut -d: -f2 | xargs || echo '<glxinfo failed>')"
  else
    echo "  ${YELLOW}glxinfo not available (install mesa-demos)${RESET}"
  fi

  if command -v vainfo >/dev/null 2>&1; then
    echo "  VA-API: $(vainfo 2>&1 | grep -m1 "Driver version" | cut -d: -f2 | xargs || echo '<not available>')"
  else
    echo "  ${YELLOW}vainfo not available (install libva-utils)${RESET}"
  fi

  echo
  echo "=============================================="
  echo "CRITICAL PREFERENCES (X11+Mesa Optimization)"
  echo "=============================================="

  # Check if Firefox is running to read prefs
  has_issues=0
  if pgrep -x firefox >/dev/null 2>&1; then
    PREFS_JS="$PROFILE_DIR/prefs.js"
    if [[ -f "$PREFS_JS" ]]; then
      for pref in "${!CRITICAL_PREFS[@]}"; do
        expected="${CRITICAL_PREFS[$pref]}"
        actual=$(grep -oP "user_pref\(\"$pref\", \K[^)]*" "$PREFS_JS" 2>/dev/null || echo "NOT_SET")

        if [[ "$actual" == "$expected" ]]; then
          echo "${GREEN}✓${RESET} $pref = $actual"
        elif [[ "$actual" == "NOT_SET" ]]; then
          echo "${YELLOW}⚠${RESET} $pref = ${YELLOW}NOT SET${RESET} (expected: $expected)"
          has_issues=1
        else
          echo "${RED}✗${RESET} $pref = $actual (expected: $expected)"
          has_issues=1
        fi
      done

      if [[ $has_issues -eq 1 ]]; then
        echo ""
        echo "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
        echo "${RED}⚠  ACTION REQUIRED: Preferences are not applied!${RESET}"
        echo "${RED}⚠  Firefox must be RESTARTED to apply user.js changes${RESET}"
        echo "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
        echo ""
        echo "Steps to fix:"
        echo "  1. Close ALL Firefox windows"
        echo "  2. Run: killall firefox"
        echo "  3. Start Firefox normally"
        echo "  4. Verify preferences show ${GREEN}✓${RESET} in this HUD"
      fi
    else
      echo "${YELLOW}prefs.js not found (Firefox not started yet?)${RESET}"
    fi
  else
    echo "${YELLOW}Firefox not running - cannot check runtime prefs${RESET}"
    echo "Start Firefox to see live preference values"
  fi

  echo
  echo "=============================================="
  echo "Firefox Processes:"
  echo "=============================================="
  if pgrep -x firefox >/dev/null 2>&1; then
    echo "  Total processes: $(pgrep -x firefox | wc -l)"
    echo "  CPU usage:"
    ps aux | grep -E "firefox|PID" | grep -v grep | head -n 6
  else
    echo "${YELLOW}Firefox not running${RESET}"
  fi

  echo
  echo "=============================================="
  echo "MOZ_LOG (GPU delays - last 10 lines):"
  echo "=============================================="
  if [[ -s "$MOZLOG_DUMP" ]]; then
    if grep -qi "wait\|delay\|flush" "$MOZLOG_DUMP" 2>/dev/null; then
      grep -i "wait\|delay\|flush" "$MOZLOG_DUMP" | tail -n 10
    else
      echo "${GREEN}✓ No GPU delays detected${RESET}"
    fi
  else
    echo "${YELLOW}MOZ_LOG not available${RESET}"
    echo "Start Firefox with: MOZ_LOG=\"Graphics:5\" MOZ_LOG_FILE=\"$MOZLOG_DUMP\" firefox"
  fi

  echo
  echo "=============================================="
  echo "System Load:"
  echo "=============================================="
  uptime
  echo ""
  echo "Memory:"
  free -h | grep -E "Mem:|Swap:"

  echo
  echo "Press Ctrl+C to exit | Refresh: ${REFRESH_INTERVAL}s"
  sleep "$REFRESH_INTERVAL"
done
