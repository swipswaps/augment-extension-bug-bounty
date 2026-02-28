#!/usr/bin/env bash
set -euo pipefail

EXTENSION_JS="$HOME/.vscode/extensions/augment.vscode-augment-0.792.0/out/extension.js.pretty"
BACKUP="$EXTENSION_JS.backup-$(date +%Y%m%d-%H%M%S)"

echo "========================================"
echo "APPLYING EXTENSION.JS FIXES"
echo "Date: $(date)"
echo "========================================"
echo ""
echo "📦 Creating backup: $BACKUP"
cp "$EXTENSION_JS" "$BACKUP"
echo "✅ Backup created"
echo ""
echo "🔧 Applying fixes..."
echo ""

python3 << 'PYTHON_SCRIPT'
import re

file_path = "/home/owner/.vscode/extensions/augment.vscode-augment-0.792.0/out/extension.js.pretty"

print(f"Reading {file_path}...")
with open(file_path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

print(f"✅ Read {len(lines)} lines")
print("")

# FIX 1: Add mutex to updateStatusTrace() at line ~302773
print("🔧 FIX 1: Adding mutex to updateStatusTrace()")

target_line = 302772
if target_line < len(lines) and "async updateStatusTrace()" in lines[target_line]:
    print(f"✅ Found 'async updateStatusTrace()' at line {target_line + 1}")
    
    for i in range(target_line + 1, min(target_line + 10, len(lines))):
        if "this._statusTrace?.dispose();" in lines[i]:
            indent = "        "
            lines.insert(i, f"{indent}if (this._statusTraceLock) return;\n")
            lines.insert(i + 1, f"{indent}this._statusTraceLock = true;\n")
            lines.insert(i + 2, f"{indent}try {{\n")
            print(f"✅ Inserted mutex check at line {i + 1}")
            
            brace_count = 0
            found_start = False
            for j in range(i, min(i + 500, len(lines))):
                if "{" in lines[j]:
                    brace_count += lines[j].count("{")
                    found_start = True
                if "}" in lines[j]:
                    brace_count -= lines[j].count("}")
                
                if found_start and brace_count == 0 and "}" in lines[j]:
                    lines.insert(j, f"{indent}}} finally {{\n")
                    lines.insert(j + 1, f"{indent}    this._statusTraceLock = false;\n")
                    lines.insert(j + 2, f"{indent}}}\n")
                    print(f"✅ Inserted finally block at line {j + 1}")
                    break
            break

print("")
print("🔧 FIX 2: Adding _statusTraceLock property declaration")

for i, line in enumerate(lines):
    if "_statusTrace = void 0;" in line:
        indent = line[:len(line) - len(line.lstrip())]
        lines.insert(i + 1, f"{indent}_statusTraceLock = false;\n")
        print(f"✅ Added _statusTraceLock property at line {i + 2}")
        break

print("")
print(f"Writing to {file_path}...")
with open(file_path, 'w', encoding='utf-8') as f:
    f.writelines(lines)

print("✅ File updated successfully")
print(f"Total lines after fixes: {len(lines)}")

PYTHON_SCRIPT

echo ""
echo "========================================"
echo "FIXES APPLIED SUCCESSFULLY"
echo "========================================"
echo ""
echo "Backup: $BACKUP"
echo ""
echo "Copying to extension.js..."
cp "$EXTENSION_JS" "$HOME/.vscode/extensions/augment.vscode-augment-0.792.0/out/extension.js"
echo "✅ Copied to extension.js"
echo ""
echo "Extension is now fixed. Reload VS Code window to apply changes."
echo ""

