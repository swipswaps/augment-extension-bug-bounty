#!/usr/bin/env bash
###############################################################################
# AUGMENT RM CLASS LATCH INSTRUMENTATION PATCHER
#
# PURPOSE:
#   Inject stack-trace capturing instrumentation into bundled extension.js
#   to detect when _cancelledByUser and _closingPromise are mutated.
#
# STRATEGY:
#   - Locate bundled RM class in extension.js
#   - Inject prototype-level setter interception AFTER class definition
#   - Capture full stack trace at mutation time
#   - Fail hard if patch cannot be applied
#
# USAGE:
#   ./patch-augment-rm-latch.sh
#
###############################################################################

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

# Find latest Augment extension directory
log_info "Locating Augment extension..."
EXTENSION_DIR="$HOME/.vscode/extensions"
AUGMENT_EXTENSION=$(find "$EXTENSION_DIR" -maxdepth 1 -type d -name "augment.vscode-augment-*" | sort -V | tail -1)

if [[ -z "$AUGMENT_EXTENSION" ]]; then
    log_error "Augment extension not found in $EXTENSION_DIR"
    exit 1
fi

log_info "Found extension: $AUGMENT_EXTENSION"

# Resolve extension.js path
EXTENSION_JS="$AUGMENT_EXTENSION/out/extension.js"

if [[ ! -f "$EXTENSION_JS" ]]; then
    log_error "extension.js not found at: $EXTENSION_JS"
    exit 1
fi

log_info "Target file: $EXTENSION_JS"

# Check if already patched (idempotent)
if grep -q "LATCH INSTRUMENTATION ACTIVE" "$EXTENSION_JS"; then
    log_warn "Instrumentation already applied. Skipping."
    exit 0
fi

# Create timestamped backup
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
BACKUP_FILE="${EXTENSION_JS}.backup-rm-latch-${TIMESTAMP}"

log_info "Creating backup: $BACKUP_FILE"
cp "$EXTENSION_JS" "$BACKUP_FILE"

# Verify RM class exists
if ! grep -q "var RM=class" "$EXTENSION_JS"; then
    log_error "RM class definition not found in extension.js"
    log_error "Expected pattern: 'var RM=class'"
    exit 1
fi

log_info "RM class found. Preparing instrumentation..."

# Create instrumentation block
INSTRUMENTATION=$(cat <<'INSTRUMENT_EOF'
;(function(){const fs=require('fs');const path=require('path');const LOG_FILE=path.resolve(process.cwd(),'augment-latch-debug.log');if(typeof RM!=='function'){console.error('[LATCH PATCH FAILURE] RM not defined');throw new Error('RM class not found for instrumentation');}function patchProperty(prop){const privateKey='__instrumented_'+prop;Object.defineProperty(RM.prototype,prop,{configurable:true,enumerable:true,get:function(){return this[privateKey];},set:function(value){const prev=this[privateKey];this[privateKey]=value;const stack=new Error().stack;const entry=['================================================================','[LATCH DETECTED]','Property: '+prop,'Timestamp: '+new Date().toISOString(),'PID: '+process.pid,'Previous: '+prev,'New: '+value,'STACK TRACE:',stack,'================================================================',''].join('\n');try{fs.appendFileSync(LOG_FILE,entry);}catch(e){}console.error(entry);}});}patchProperty('_cancelledByUser');patchProperty('_closingPromise');console.error('[LATCH INSTRUMENTATION ACTIVE] PID='+process.pid+' Timestamp='+new Date().toISOString());})();
INSTRUMENT_EOF
)

# Find the line number where RM class is defined
RM_LINE=$(grep -n "var RM=class" "$EXTENSION_JS" | head -1 | cut -d: -f1)

if [[ -z "$RM_LINE" ]]; then
    log_error "Could not determine RM class line number"
    exit 1
fi

log_info "RM class found at line: $RM_LINE"

# Insert instrumentation after RM class definition
# We need to find the end of the class definition and insert after it
# For bundled code, we'll insert at the end of the file to ensure it runs after all definitions

log_info "Injecting instrumentation..."
echo "$INSTRUMENTATION" >> "$EXTENSION_JS"

# Verify injection
if ! grep -q "LATCH INSTRUMENTATION ACTIVE" "$EXTENSION_JS"; then
    log_error "Injection verification failed"
    log_error "Restoring backup..."
    mv "$BACKUP_FILE" "$EXTENSION_JS"
    exit 1
fi

log_info "${GREEN}[PATCH APPLIED SUCCESSFULLY]${NC}"
log_info ""
log_info "Backup saved to: $BACKUP_FILE"
log_info ""
log_info "Next steps:"
log_info "  1. Reload VS Code window (Ctrl+Shift+P → 'Developer: Reload Window')"
log_info "  2. Trigger MCP client cancellation"
log_info "  3. Check ./augment-latch-debug.log for stack traces"
log_info ""
log_info "Expected output:"
log_info "  [LATCH DETECTED]"
log_info "  Property: _cancelledByUser"
log_info "  STACK TRACE:"
log_info "  <full call chain>"
log_info ""
log_info "To rollback:"
log_info "  cp \"$BACKUP_FILE\" \"$EXTENSION_JS\""

exit 0

