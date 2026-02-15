#!/bin/bash

WEBVIEW_FILE="/home/owner/.vscode/extensions/augment.vscode-augment-0.754.3/common-webviews/assets/extension-client-context-CN64fWtK.js"

# Create backup
cp "$WEBVIEW_FILE" "${WEBVIEW_FILE}.backup-$(date +%Y%m%d-%H%M%S)"

# Apply ChatGPT's deterministic fix - remove 500ms heuristic
# Replace lines 44331-44350 with deterministic version

# Use Python for precise multi-line replacement
python3 << 'PYTHON_EOF'
import re

file_path = "/home/owner/.vscode/extensions/augment.vscode-augment-0.754.3/common-webviews/assets/extension-client-context-CN64fWtK.js"

with open(file_path, 'r') as f:
    content = f.read()

# Old pattern (with 500ms heuristic)
old_pattern = r'''            if \(g\) \{
                const m = yield\* O\(\);
                // TIMEOUT FIX: Wait for cancelToolRun to complete and get output
                yield\* w\(\[m, m\.cancelToolRun\], n, o\);
                // Wait 500ms for extension to read output
                yield\* je\(500\);
                // Check if we got output from the cancelled process
                const toolState = yield\* Ln\.effect\(n, o\);
                if \(toolState\.result\) \{
                    // Got output - use GS \(markToolAsCompleted\)
                    yield\* E\(GS\(n, o, toolState\.result\)\);
                    return;
                \}
                // No output - use Qs \(markToolAsError\)
                yield\* E\(Qs\(n, o, \{
                    isError: !0,
                    text: "Tool call timed out\. No output was captured\."
                \}\)\);
                return;
            \}'''

# New pattern (deterministic, no 500ms wait)
new_pattern = '''            if (g) {
                const m = yield* O();
                // DETERMINISTIC FIX: Await cancelToolRun and capture returned payload
                const cancelResult = yield* w([m, m.cancelToolRun], n, o);
                // If extension host returns structured result, use it
                if (cancelResult && cancelResult.result) {
                    yield* E(GS(n, o, cancelResult.result));
                    return;
                }
                // Fallback: read state synchronously after cancel completes
                const toolState = yield* Ln.effect(n, o);
                if (toolState && toolState.result) {
                    yield* E(GS(n, o, toolState.result));
                    return;
                }
                // Only if absolutely no output exists, mark as timeout error
                yield* E(Qs(n, o, {
                    isError: !0,
                    text: "Tool call timed out before any output was captured."
                }));
                return;
            }'''

# Apply replacement
content_new = re.sub(old_pattern, new_pattern, content)

if content_new == content:
    print("ERROR: Pattern not found - no changes made")
    exit(1)

with open(file_path, 'w') as f:
    f.write(content_new)

print("SUCCESS: Deterministic fix applied")
PYTHON_EOF

echo "Deterministic fix applied successfully"
