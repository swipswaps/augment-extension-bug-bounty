# Rollback Instructions

**Report ID**: `174ab568-83ed-4b09-9ac9-dce2f07c6fcf`  
**Date**: 2026-02-10

---

## Quick Rollback

To restore the original extension.js (before RULE 9 fix):

```bash
# Restore from the backup taken immediately before RULE 9 fix
cp /home/owner/.vscode/extensions/augment.vscode-augment-0.754.3/out/extension.js.backup-before-rule9-20260210-103159 \
   /home/owner/.vscode/extensions/augment.vscode-augment-0.754.3/out/extension.js

# Reload VS Code
# Ctrl+Shift+P → "Developer: Reload Window"
```

---

## Available Backups

### RULE 9 Fix Backups (2026-02-10)

**Most recent backup before RULE 9 fix**:
- **File**: `extension.js.backup-before-rule9-20260210-103159`
- **Size**: 8.0 MB (2,755 lines, minified)
- **Status**: Original extension with Bugs 1, 2, 3 fixes applied
- **Use for**: Rollback to pre-RULE-9 state

**Other RULE 9-related backups**:
- `extension.js.backup-rule9-20260210-101705` - Earlier RULE 9 attempt
- `extension.beautified.js.backup-rule9-20260210-103113` - Beautified version before fix

### Earlier Backups (2026-02-08 to 2026-02-10)

**All fixes applied** (Bugs 1, 2, 3):
- **File**: `extension.js.bak-20260209-all-fixes`
- **Size**: 8.0 MB (2,755 lines, minified)
- **Status**: Has Bugs 1, 2, 3 fixes, NO RULE 9 fix
- **Use for**: Rollback to state with only Bugs 1, 2, 3 fixed

**Original extension** (no fixes):
- **File**: `extension.js.bak-20260208-180319`
- **Size**: 8.0 MB (2,755 lines, minified)
- **Status**: Original extension from Augment (all bugs present)
- **Use for**: Complete rollback to factory state

---

## Rollback Scenarios

### Scenario 1: RULE 9 Fix Causes Issues

**Symptom**: Extension crashes, errors in console, unexpected behavior

**Solution**:
```bash
# Restore to state with Bugs 1, 2, 3 fixes but NO RULE 9 fix
cp /home/owner/.vscode/extensions/augment.vscode-augment-0.754.3/out/extension.js.backup-before-rule9-20260210-103159 \
   /home/owner/.vscode/extensions/augment.vscode-augment-0.754.3/out/extension.js

# Reload VS Code
```

### Scenario 2: All Fixes Cause Issues

**Symptom**: Extension completely broken, want to start fresh

**Solution**:
```bash
# Restore to original factory state
cp /home/owner/.vscode/extensions/augment.vscode-augment-0.754.3/out/extension.js.bak-20260208-180319 \
   /home/owner/.vscode/extensions/augment.vscode-augment-0.754.3/out/extension.js

# Reload VS Code
```

### Scenario 3: Extension Update Overwrites Fixes

**Symptom**: Augment releases new version, overwrites your fixes

**Solution**:
```bash
# Re-apply all fixes using automated scripts
cd augment-extension-bug-bounty/fixes

# Apply Bugs 1, 2, 3 fixes
./apply-all-fixes.sh

# Apply RULE 9 fix
./apply-rule9-fix.sh

# Reload VS Code
```

---

## Verification After Rollback

### Verify RULE 9 Fix is Removed

```bash
# Should return nothing if RULE 9 fix is removed
grep "RULE 9 ENFORCEMENT" /home/owner/.vscode/extensions/augment.vscode-augment-0.754.3/out/extension.js
```

### Verify File Size

```bash
# Check current extension.js
ls -lh /home/owner/.vscode/extensions/augment.vscode-augment-0.754.3/out/extension.js

# Expected sizes:
# - With RULE 9 fix: 13 MB (293,719 lines, beautified)
# - Without RULE 9 fix: 8.0 MB (2,755 lines, minified)
```

### Verify Line Count

```bash
wc -l /home/owner/.vscode/extensions/augment.vscode-augment-0.754.3/out/extension.js

# Expected:
# - With RULE 9 fix: 293,719 lines
# - Without RULE 9 fix: 2,755 lines
```

---

## Backup Management

### List All Backups

```bash
ls -lh /home/owner/.vscode/extensions/augment.vscode-augment-0.754.3/out/extension.js* | grep -E "backup|bak"
```

### Create New Backup

```bash
cp /home/owner/.vscode/extensions/augment.vscode-augment-0.754.3/out/extension.js \
   /home/owner/.vscode/extensions/augment.vscode-augment-0.754.3/out/extension.js.backup-$(date +%Y%m%d-%H%M%S)
```

### Clean Old Backups (Optional)

```bash
# Remove backups older than 30 days
find /home/owner/.vscode/extensions/augment.vscode-augment-0.754.3/out/ -name "extension.js.backup-*" -mtime +30 -delete
```

---

## Emergency Recovery

If VS Code won't start or extension is completely broken:

1. **Rename broken extension.js**:
   ```bash
   mv /home/owner/.vscode/extensions/augment.vscode-augment-0.754.3/out/extension.js \
      /home/owner/.vscode/extensions/augment.vscode-augment-0.754.3/out/extension.js.broken
   ```

2. **Restore from backup**:
   ```bash
   cp /home/owner/.vscode/extensions/augment.vscode-augment-0.754.3/out/extension.js.bak-20260208-180319 \
      /home/owner/.vscode/extensions/augment.vscode-augment-0.754.3/out/extension.js
   ```

3. **Restart VS Code**

4. **Reinstall extension** (if still broken):
   - Uninstall Augment extension
   - Reinstall from VS Code marketplace
   - Re-apply fixes if needed

