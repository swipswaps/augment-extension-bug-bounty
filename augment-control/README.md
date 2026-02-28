# Augment Control System

**Reliable detection and fixing for VS Code and Augment extension issues**

## 🎯 Purpose

This toolkit provides working solutions to detect and fix two critical issues:

1. **VS Code 1.109 Terminal Sandboxing** - Prevents `sudo` from working
2. **Timeout Blocking Code** - AI fails to read command output on timeout

## 📋 Scripts

### 1. `augment-control.sh` - Unified Orchestrator

**What it does:**
- Runs all detection scripts
- Creates extension backups
- Offers to disable sandbox if enabled
- Provides summary and next steps

**Usage:**
```bash
cd augment-control
./augment-control.sh
```

### 2. `detect-vscode-sandbox.sh` - Sandbox Detection

**What it does:**
- Checks if VS Code has `NoNewPrivs: 1` flag set
- Tests current terminal for sandbox status

**Exit codes:**
- `0` = Sandbox ENABLED (sudo won't work)
- `1` = Sandbox DISABLED (sudo works)

**Usage:**
```bash
./detect-vscode-sandbox.sh
```

### 3. `disable-vscode-sandbox.sh` - Sandbox Disabler

**What it does:**
- Adds `"chat.tools.terminal.sandbox.enabled": false` to VS Code settings
- Uses `jq` for safe JSON manipulation

**Requirements:**
- `jq` must be installed (`sudo dnf install jq -y`)

**Usage:**
```bash
./disable-vscode-sandbox.sh
```

**⚠️ IMPORTANT:** Restart VS Code after running this script!

### 4. `detect-timeout-block.sh` - Timeout Block Detection

**What it does:**
- Searches for `je(500)` heuristic delay in webview code
- Searches for timeout error messages
- Searches for `markToolAsError` calls

**Usage:**
```bash
./detect-timeout-block.sh
```

### 5. `freeze-augment.sh` - Extension Backup

**What it does:**
- Creates timestamped backups of Augment extension
- Stores backups in `~/.augment-backups/`

**Usage:**
```bash
./freeze-augment.sh
```

### 6. `patch-augment-deterministic.sh` - Deterministic Patch

**What it does:**
- Removes `je(500)` heuristic delay from webview code
- Updates timeout error message to be accurate
- Creates backup before patching

**Usage:**
```bash
./patch-augment-deterministic.sh
```

**⚠️ IMPORTANT:** Restart VS Code after running this script!

## 🚀 Quick Start

### Option 1: Run Unified Control (Recommended)

```bash
cd augment-control
./augment-control.sh
```

This will:
1. Detect all issues
2. Create backups
3. Offer to fix sandbox issue
4. Provide summary and next steps

### Option 2: Manual Steps

```bash
# 1. Detect issues
./detect-vscode-sandbox.sh
./detect-timeout-block.sh

# 2. Create backup
./freeze-augment.sh

# 3. Fix sandbox (if needed)
./disable-vscode-sandbox.sh

# 4. Apply deterministic patch
./patch-augment-deterministic.sh

# 5. Restart VS Code
```

## 🔍 Testing

After applying fixes, test with:

```bash
bash /tmp/test-timeout-behavior.sh
```

This will verify that the AI can read output after timeout.

## 📚 Background

### VS Code 1.109 Terminal Sandboxing

**Root Cause:** VS Code 1.109 introduced terminal sandboxing feature that sets `no_new_privs` flag on terminal processes.

**Evidence:** Official VS Code 1.109 release notes

**Solution:** Disable via `chat.tools.terminal.sandbox.enabled: false`

### Timeout Blocking Code

**Root Cause:** `je(500)` heuristic delay in webview code causes race condition where output is captured but never returned to AI.

**Evidence:** Found in `common-webviews/assets/extension-client-context-*.js`

**Solution:** Remove heuristic delay with deterministic patch

## ⚠️ Important Notes

1. **Always create backups** before applying patches
2. **Restart VS Code** after applying fixes
3. **VS Code updates** may overwrite patches - re-run scripts after updates
4. **Test thoroughly** after applying fixes

## 🔗 References

- ChatGPT logs: `/home/owner/Documents/6984bd27-4494-8330-9803-7b6895a48aa5/.notes/6988d4de-c5f4-8326-946c-c584bb748f31_0015.txt`
- VS Code 1.109 release notes: https://code.visualstudio.com/updates/v1_109

