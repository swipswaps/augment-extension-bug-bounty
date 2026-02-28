#!/usr/bin/env bash
# CORRECT Source Map Extraction - Extracts ACTUAL readable source code
set -euo pipefail

EXT_DIR="$HOME/.vscode/extensions/augment.vscode-augment-0.779.0/out"
MAP_FILE="$EXT_DIR/extension.js.map"
JS_FILE="$EXT_DIR/extension.js"
OUTPUT_DIR="$HOME/augment-source-extracted"

echo "=== Augment Source Code Extraction (REAL VERSION) ==="
echo ""
echo "Extension dir: $EXT_DIR"
echo "Source map: $MAP_FILE"
echo "Output dir: $OUTPUT_DIR"
echo ""

if [ ! -f "$MAP_FILE" ]; then
  echo "ERROR: Source map not found at $MAP_FILE"
  exit 1
fi

mkdir -p "$OUTPUT_DIR"

echo "[*] Extracting original sources from source map..."
echo ""

# Use Node.js to parse source map and extract all source files
MAP_FILE="$MAP_FILE" OUTPUT_DIR="$OUTPUT_DIR" node <<'EOF'
const fs = require('fs');
const path = require('path');

const mapFile = process.env.MAP_FILE;
const outDir = process.env.OUTPUT_DIR;

console.log(`Reading source map: ${mapFile}`);
const map = JSON.parse(fs.readFileSync(mapFile, 'utf8'));

console.log(`Found ${map.sources.length} source files`);
console.log(`Extracting to: ${outDir}`);

let extracted = 0;
let skipped = 0;

map.sources.forEach((src, i) => {
    const content = map.sourcesContent[i];
    if (!content) {
        skipped++;
        return;
    }

    // Clean webpack:/// prefix and absolute paths
    let clean = src.replace(/^webpack:\/\/\//, '');

    // Remove leading slashes and convert absolute paths to relative
    clean = clean.replace(/^\/+/, '');

    // Replace problematic path separators
    clean = clean.replace(/\.\.\//g, 'parent/');

    const filePath = path.join(outDir, clean);

    // Create directory structure
    fs.mkdirSync(path.dirname(filePath), { recursive: true });
    
    // Write source file
    fs.writeFileSync(filePath, content);
    extracted++;
    
    if (extracted % 100 === 0) {
        console.log(`  Extracted ${extracted} files...`);
    }
});

console.log("");
console.log(`Extraction complete:`);
console.log(`  Extracted: ${extracted} files`);
console.log(`  Skipped: ${skipped} files (no content)`);
EOF

echo ""
echo "=== Source extraction complete ==="
echo ""
echo "Now searching for tool execution code..."
echo ""

# Search for Promise.race patterns
echo "1. Searching for Promise.race patterns:"
grep -rn "Promise\.race" "$OUTPUT_DIR" 2>/dev/null | grep -i "tool\|timeout\|cancel" | head -20

echo ""
echo "2. Searching for timeout implementations:"
grep -rn "timeout" "$OUTPUT_DIR" 2>/dev/null | grep -i "promise\|race\|tool" | head -20

echo ""
echo "3. Searching for callTool implementations:"
grep -rn "callTool" "$OUTPUT_DIR" 2>/dev/null | head -20

echo ""
echo "=== Extraction complete ==="
echo "Extracted source code is in: $OUTPUT_DIR"
echo ""
echo "To search manually:"
echo "  cd $OUTPUT_DIR"
echo "  grep -rn 'Promise.race' ."
echo "  grep -rn 'callTool' ."

