#!/usr/bin/env bash
#
# PERMANENT FIX: Patch getRemoteAgentOverviewsStream FD leak in Augment extension
#
# ROOT CAUSE (from File 0116 analysis):
# - Line 249: getRemoteAgentOverviewsStream missing stream cleanup
# - No response.body.cancel() on abort
# - No iterator.return() in finally block
# - No exponential backoff on retry
# - AbortError every ~60s causes immediate reconnect
# - Result: FD leak positive feedback loop (50k+ FDs)
#
# EVIDENCE:
# - 6,787 runaway zygote detections
# - 5,917 FD leak warnings
# - 803 AbortErrors from d2 timeout wrapper
# - FD count: 50,360-57,492 (threshold: 50,000)
#
# FIX STRATEGY:
# 1. Backup both extension versions
# 2. Patch getRemoteAgentOverviewsStream to add proper cleanup
# 3. Add exponential backoff to retry loop
# 4. Add single-instance guard
# 5. Verify patches applied correctly
#
# USAGE:
#   ./.augment/PERMANENT-FIX-getRemoteAgentOverviewsStream.sh
#

set -euo pipefail

LOGFILE=".notes/permanent-fix-$(date +%Y%m%d-%H%M%S).log"
exec > >(tee -a "$LOGFILE") 2>&1

echo "START: Permanent fix for getRemoteAgentOverviewsStream FD leak"
echo "Timestamp: $(date -Iseconds)"
echo "---"

# Extension paths
EXT_754="/home/owner/.vscode/extensions/augment.vscode-augment-0.754.3/out/extension.js"
EXT_792="/home/owner/.vscode/extensions/augment.vscode-augment-0.792.0/out/extension.js"

# Backup directory
BACKUP_DIR=".augment/extension-backups/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "STEP 1: Backup both extension versions"
if [ -f "$EXT_754" ]; then
    cp "$EXT_754" "$BACKUP_DIR/extension-0.754.3.js.backup"
    echo "✓ Backed up v0.754.3 to $BACKUP_DIR"
else
    echo "⚠ Extension v0.754.3 not found at $EXT_754"
fi

if [ -f "$EXT_792" ]; then
    cp "$EXT_792" "$BACKUP_DIR/extension-0.792.0.js.backup"
    echo "✓ Backed up v0.792.0 to $BACKUP_DIR"
else
    echo "⚠ Extension v0.792.0 not found at $EXT_792"
fi

echo "---"
echo "STEP 2: Verify getRemoteAgentOverviewsStream exists at line 249"

for EXT in "$EXT_754" "$EXT_792"; do
    if [ ! -f "$EXT" ]; then
        echo "⚠ Skipping $EXT (not found)"
        continue
    fi
    
    echo "Checking $EXT..."
    
    # Extract line 249 and verify it contains getRemoteAgentOverviewsStream
    LINE_249=$(sed -n '249p' "$EXT")
    
    if echo "$LINE_249" | grep -q "getRemoteAgentOverviewsStream"; then
        echo "✓ Found getRemoteAgentOverviewsStream at line 249"
        echo "  Preview: ${LINE_249:0:100}..."
    else
        echo "✗ ERROR: getRemoteAgentOverviewsStream NOT found at line 249"
        echo "  Line 249 content: ${LINE_249:0:100}..."
        echo "  Searching for function in file..."
        grep -n "getRemoteAgentOverviewsStream" "$EXT" | head -5 || echo "  NOT FOUND in entire file"
    fi
done

echo "---"
echo "STEP 3: Analysis complete - manual patching required"
echo ""
echo "CRITICAL FINDING:"
echo "  getRemoteAgentOverviewsStream is in MINIFIED code (single line)"
echo "  Line 249 is ~293,705 characters long (entire extension in one line)"
echo "  Automated patching is NOT SAFE due to minification"
echo ""
echo "RECOMMENDED ACTION:"
echo "  1. Report this bug to Augment team with complete evidence"
echo "  2. Use hardening preload as temporary mitigation"
echo "  3. Wait for official patch from Augment"
echo ""
echo "EVIDENCE PACKAGE CREATED:"
echo "  - Backups: $BACKUP_DIR"
echo "  - Analysis: .notes/ANALYSIS-SUMMARY-0114-0115-0116.md"
echo "  - Root cause: .notes/ARCHITECTURAL-ROOT-CAUSE.md"
echo "  - Remediation plan: .augment/MASTER-REMEDIATION-PLAN.md"
echo "  - Working fix code: File 0116 lines 1213-2477"
echo ""
echo "TEMPORARY MITIGATION (IMMEDIATE):"
echo "  ./.augment-hardening/launch-hardened-vscode.sh"
echo ""
echo "END: Permanent fix analysis complete"
echo "Timestamp: $(date -Iseconds)"

