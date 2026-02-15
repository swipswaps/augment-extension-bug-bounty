#!/usr/bin/env bash
# Search for all instances of blocking code patterns in VS Code and Augment extension
# This script works on both webpack-bundled and line-based versions

set -euo pipefail

echo "╔════════════════════════════════════════════════════════════════════════════════╗"
echo "║                    BLOCKING CODE PATTERN SEARCH                                ║"
echo "║                                                                                ║"
echo "║  Searches VS Code and Augment extension for code patterns that block          ║"
echo "║  the AI from reading command output when timeouts occur.                      ║"
echo "╚════════════════════════════════════════════════════════════════════════════════╝"
echo ""

# Find all Augment extension versions
AUGMENT_EXTENSIONS=$(find ~/.vscode/extensions -maxdepth 1 -type d -name "augment.vscode-augment-*" 2>/dev/null || true)

if [ -z "$AUGMENT_EXTENSIONS" ]; then
    echo "❌ ERROR: No Augment extensions found in ~/.vscode/extensions"
    exit 1
fi

echo "📦 Found Augment extension(s):"
echo "$AUGMENT_EXTENSIONS" | while read -r ext; do
    echo "   - $(basename "$ext")"
done
echo ""

# Pattern definitions
declare -A PATTERNS=(
    ["cancelToolRun_no_output"]='async cancelToolRun\(.*?\).*?return.*?[!01]'
    ["abort_before_output"]='abortController\.abort\(\)'
    ["timeout_error_message"]='Tool call was cancelled due to timeout'
    ["timeout_error_message_alt"]='timed out before any output'
    ["heuristic_delay"]='yield\* je\(500\)'
    ["ctrl_c_send"]='sendText\("\\u0003"'
    ["race_condition"]='Promise\.race|FE\(\{.*?callTool.*?cancel'
)

echo "🔍 Searching for blocking code patterns..."
echo ""

for ext_dir in $AUGMENT_EXTENSIONS; do
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo "Extension: $(basename "$ext_dir")"
    echo "════════════════════════════════════════════════════════════════════════════════"
    echo ""
    
    # Check if webpack-bundled or line-based
    EXTENSION_JS="$ext_dir/out/extension.js"
    if [ ! -f "$EXTENSION_JS" ]; then
        echo "⚠️  extension.js not found, skipping"
        continue
    fi
    
    FILE_SIZE=$(stat -f%z "$EXTENSION_JS" 2>/dev/null || stat -c%s "$EXTENSION_JS" 2>/dev/null)
    LINE_COUNT=$(wc -l < "$EXTENSION_JS")
    
    echo "📄 extension.js: $LINE_COUNT lines, $(numfmt --to=iec-i --suffix=B $FILE_SIZE 2>/dev/null || echo "$FILE_SIZE bytes")"
    
    if [ "$LINE_COUNT" -lt 10000 ]; then
        echo "   Type: WEBPACK-BUNDLED (minified)"
    else
        echo "   Type: LINE-BASED (readable)"
    fi
    echo ""
    
    # Search for each pattern
    for pattern_name in "${!PATTERNS[@]}"; do
        pattern="${PATTERNS[$pattern_name]}"
        echo "🔎 Pattern: $pattern_name"
        
        # Use grep with Perl regex for better pattern matching
        matches=$(grep -oP "$pattern" "$EXTENSION_JS" 2>/dev/null | head -5 || true)
        
        if [ -n "$matches" ]; then
            echo "   ✅ FOUND:"
            echo "$matches" | while IFS= read -r match; do
                # Truncate long matches
                if [ ${#match} -gt 100 ]; then
                    echo "      ${match:0:100}..."
                else
                    echo "      $match"
                fi
            done
        else
            # Try simpler grep for literal strings
            case "$pattern_name" in
                timeout_error_message*)
                    simple_match=$(grep -F "Tool call was cancelled due to timeout" "$EXTENSION_JS" 2>/dev/null || true)
                    ;;
                ctrl_c_send)
                    simple_match=$(grep -F 'sendText("\u0003"' "$EXTENSION_JS" 2>/dev/null || grep -F "sendText('\\u0003'" "$EXTENSION_JS" 2>/dev/null || true)
                    ;;
                *)
                    simple_match=""
                    ;;
            esac
            
            if [ -n "$simple_match" ]; then
                echo "   ✅ FOUND (literal match)"
            else
                echo "   ❌ NOT FOUND"
            fi
        fi
        echo ""
    done
    
    # Search webview files
    WEBVIEW_FILES=$(find "$ext_dir/common-webviews" -name "*.js" 2>/dev/null || true)
    if [ -n "$WEBVIEW_FILES" ]; then
        echo "────────────────────────────────────────────────────────────────────────────────"
        echo "Webview JavaScript files:"
        echo "────────────────────────────────────────────────────────────────────────────────"
        echo ""
        
        echo "$WEBVIEW_FILES" | while IFS= read -r webview_file; do
            echo "📄 $(basename "$webview_file")"
            
            # Check for timeout error message
            if grep -qF "Tool call was cancelled due to timeout" "$webview_file" 2>/dev/null; then
                echo "   ✅ Contains timeout error message"
            fi
            
            # Check for race condition
            if grep -qE "Promise\.race|FE\(\{" "$webview_file" 2>/dev/null; then
                echo "   ✅ Contains race condition pattern"
            fi
            
            echo ""
        done
    fi
    
    echo ""
done

echo "════════════════════════════════════════════════════════════════════════════════"
echo "✅ SEARCH COMPLETE"
echo "════════════════════════════════════════════════════════════════════════════════"

