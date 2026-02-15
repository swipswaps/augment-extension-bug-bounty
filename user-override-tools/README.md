# User Override Tools

**Purpose**: Workaround scripts to use when AI tools stop working due to the timeout bug.

---

## 🚨 When to Use These Tools

Use these tools when:
- AI claims "no output was captured" but you can see output in the terminal
- AI stops working after a timeout error
- AI asks you to manually run commands
- VS Code update wiped out fixes and you can't reapply them (webpack-bundled version)

---

## 📋 Available Tools

### 1. `manual-output-reader.sh`

**Purpose**: Read terminal output when AI claims "no output"

**Usage**:
```bash
./manual-output-reader.sh <terminal_id>
```

**Example**:
```bash
./manual-output-reader.sh 123456
```

**What it does**:
- Searches VS Code terminal buffers for output
- Checks Augment extension logs
- Displays the actual output that the AI missed
- Provides manual steps if automatic search fails

**When to use**:
- AI says "no output was captured"
- You can see output in the terminal
- You want to prove the output exists

---

### 2. `force-continue.sh`

**Purpose**: Run commands outside VS Code and force AI to acknowledge output

**Usage**:
```bash
./force-continue.sh <command>
```

**Example**:
```bash
./force-continue.sh "npm test"
```

**What it does**:
- Runs the command in a regular bash shell (not VS Code terminal)
- Captures ALL output to a file
- Displays the output
- Provides formatted text to paste into chat
- Forces AI to acknowledge the output and continue

**When to use**:
- AI keeps claiming "no output"
- You want to bypass the VS Code terminal entirely
- You need proof that the command works
- You want to force AI to continue working

---

### 3. `disable-terminal-sandbox.sh`

**Purpose**: Disable VS Code 1.109+ terminal sandboxing

**Usage**:
```bash
./disable-terminal-sandbox.sh
```

**What it does**:
- Adds `"chat.tools.terminal.sandbox.enabled": false` to VS Code settings
- Restores `sudo` functionality
- Removes `no_new_privs` restriction

**When to use**:
- `sudo` commands fail with "no new privileges" error
- You upgraded to VS Code 1.109 or later
- You need to run privileged commands

---

## 🔧 Installation

Make all scripts executable:
```bash
chmod +x augment-extension-bug-bounty/user-override-tools/*.sh
```

---

## 💡 Workflow Example

### Scenario: AI claims "no output" after timeout

**Step 1**: Try to continue normally
```
You: "The command completed successfully. Please read the output above and continue."
```

**Step 2**: If AI still claims "no output", use force-continue.sh
```bash
cd augment-extension-bug-bounty/user-override-tools
./force-continue.sh "npm test"
```

**Step 3**: Copy the formatted output and paste into chat
```
The command completed successfully. Here is the ACTUAL output:

```
[output here]
```

Exit code: 0

Please read this output and continue with the task. Do NOT claim 'no output'
was captured. The output is shown above.
```

**Step 4**: AI should now acknowledge the output and continue

---

## 🎯 Success Criteria

These tools are successful if:
- ✅ You can continue working when AI stops
- ✅ You can prove output exists when AI claims it doesn't
- ✅ You can bypass VS Code terminal issues
- ✅ You can restore `sudo` functionality

---

## ⚠️ Limitations

These are **workarounds**, not fixes:
- They require manual intervention
- They don't fix the root cause
- They add extra steps to your workflow
- They're needed until Augment Code fixes the bug

**For a permanent fix**: Submit the bug report package to Augment Code team.

---

## 📚 Related Documentation

- `../SUBMIT_TO_AUGMENT_TEAM.md` - How to submit bug report
- `../BUG_REPORT_AUGMENT_TEAM.md` - Complete technical analysis
- `../QUICK_REPRODUCTION_GUIDE.md` - 30-second reproduction
- `../auto-fix-after-update.sh` - Auto-fix script for line-based versions

