#!/bin/bash
# RULE 9 Code-Level Fix Application Script
# Applies RULE 9 enforcement to beautified extension.js

set -e

EXTENSION_FILE="/home/owner/.vscode/extensions/augment.vscode-augment-0.754.3/out/extension.beautified.js"
BACKUP_FILE="${EXTENSION_FILE}.backup-rule9-$(date +%Y%m%d-%H%M%S)"

echo "========================================="
echo "RULE 9 Code-Level Fix Application"
echo "========================================="
echo ""

# Check if beautified file exists
if [ ! -f "$EXTENSION_FILE" ]; then
    echo "❌ Error: Beautified extension file not found at $EXTENSION_FILE"
    echo "Please run: js-beautify /home/owner/.vscode/extensions/augment.vscode-augment-0.754.3/out/extension.js -o $EXTENSION_FILE"
    exit 1
fi

# Create backup
echo "Creating backup: $BACKUP_FILE"
cp "$EXTENSION_FILE" "$BACKUP_FILE"
echo "✓ Backup created"
echo ""

# Check if fix already applied
if grep -q "RULE 9 ENFORCEMENT" "$EXTENSION_FILE"; then
    echo "⊘ RULE 9 fix already applied"
    exit 0
fi

echo "Applying RULE 9 fix..."
echo ""

# Create the fix using a Python script for complex multi-line replacement
python3 << 'PYTHON_SCRIPT'
import re

file_path = "/home/owner/.vscode/extensions/augment.vscode-augment-0.754.3/out/extension.beautified.js"

with open(file_path, 'r') as f:
    content = f.read()

# Find and replace the catch block
old_pattern = r'''            } catch \(f\) {
                if \(this\._cancelledByUser\) return nt\("Cancelled by user\."\);
                let p = f instanceof Error \? f\.message : String\(f\);
                return this\._logger\.error\(`MCP tool call failed: \$\{p\}`\), nt\(`Tool execution failed: \$\{p\}`, t\)
            } finally {
                this\._runningTool = void 0
            }'''

new_code = '''            } catch (f) {
                if (this._cancelledByUser) {
                    // RULE 9 ENFORCEMENT: Check if output was captured before returning error
                    if (c && c.content && Array.isArray(c.content) && c.content.length > 0) {
                        this._logger.info(`RULE 9: Returning captured output despite cancellation (${c.content.length} items)`);
                        // Process the captured output normally (continue to normal flow after catch)
                        // Set a flag to skip the error return
                        this._rule9OutputCaptured = true;
                    } else {
                        return nt("Cancelled by user.");
                    }
                }
                if (!this._rule9OutputCaptured) {
                    let p = f instanceof Error ? f.message : String(f);
                    return this._logger.error(`MCP tool call failed: ${p}`), nt(`Tool execution failed: ${p}`, t)
                }
                // Reset flag
                this._rule9OutputCaptured = false;
            } finally {
                this._runningTool = void 0
            }'''

# Perform replacement
content = re.sub(old_pattern, new_code, content, flags=re.MULTILINE)

with open(file_path, 'w') as f:
    f.write(content)

print("✓ RULE 9 fix applied successfully")
PYTHON_SCRIPT

echo ""
echo "Verifying fix..."
if grep -q "RULE 9 ENFORCEMENT" "$EXTENSION_FILE"; then
    echo "✓ Fix verified"
else
    echo "❌ Fix verification failed"
    echo "Restoring backup..."
    cp "$BACKUP_FILE" "$EXTENSION_FILE"
    exit 1
fi

echo ""
echo "========================================="
echo "RULE 9 fix applied successfully!"
echo "========================================="
echo ""
echo "Next steps:"
echo "1. Minify the beautified file back to extension.js"
echo "2. Reload VS Code window"
echo "3. Test with: echo \"START: test\" && sleep 2 && echo \"Line 1\" && echo \"END: test\""
echo ""
echo "To rollback: cp $BACKUP_FILE $EXTENSION_FILE"

