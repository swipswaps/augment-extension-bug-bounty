#!/usr/bin/env bash
set -euo pipefail

# PROBLEM: FD breakdown shows "47921 owner" as top entry
# ROOT CAUSE: awk '{print $5}' gets column 5, but lsof output has variable columns
# EXAMPLE: "8240 code 123893 ThreadPoo owner" → column 5 is "owner", not FD type
# CORRECT: FD type is in different column depending on output format

LOGFILE=".notes/diagnose-fd-$(date +%Y%m%d-%H%M%S).log"
mkdir -p .notes
exec > >(tee -a "$LOGFILE") 2>&1

echo "START: diagnose-fd-breakdown-issue"
echo ""

echo "═══════════════════════════════════════════════════════════════════"
echo "PROBLEM: FD breakdown shows 'owner' instead of FD type"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

echo "USER SHOWED THIS OUTPUT:"
echo "  FD breakdown by type:"
echo "    47921 owner    ← WRONG (should be REG/unix/pipe)"
echo "     2594 REG      ← CORRECT"
echo "      219 a_inode  ← CORRECT"
echo ""

echo "═══════════════════════════════════════════════════════════════════"
echo "ROOT CAUSE ANALYSIS"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

echo "STEP 1: Check actual lsof output format"
echo ""

lsof 2>/dev/null | grep code | head -5
echo ""

echo "STEP 2: Identify column positions"
echo ""
echo "LSOF OUTPUT FORMAT:"
echo "  COMMAND    PID  USER   FD      TYPE             DEVICE SIZE/OFF       NODE NAME"
echo "  code     12345 owner  4u      REG              253,0    12345      67890 /path/to/file"
echo "           \$1    \$2    \$3     \$4      \$5               \$6       \$7        \$8    \$9"
echo ""

echo "CURRENT CODE (BROKEN):"
echo "  lsof | grep code | awk '{print \$5}' | sort | uniq -c | sort -rn"
echo "  GETS: Column 5 = TYPE (REG/unix/pipe) ← SHOULD BE CORRECT"
echo ""

echo "STEP 3: Test current code"
echo ""
CURRENT_OUTPUT=$(lsof 2>/dev/null | grep code | awk '{print $5}' | sort | uniq -c | sort -rn | head -5)
echo "CURRENT OUTPUT:"
echo "$CURRENT_OUTPUT"
echo ""

# CHECK: Does it show "owner"?
if echo "$CURRENT_OUTPUT" | grep -q "owner"; then
    echo "❌ BROKEN: Shows 'owner' instead of FD type"
    echo ""
    
    echo "DIAGNOSIS: lsof output format varies"
    echo "  Some lines have different column counts"
    echo "  Example: 'code 123893 ThreadPoo owner' has only 4 columns"
    echo "  Column 5 doesn't exist → awk returns empty or wrong value"
    echo ""
    
    echo "STEP 4: Check what's in column 4"
    echo ""
    COL4_OUTPUT=$(lsof 2>/dev/null | grep code | awk '{print $4}' | sort | uniq -c | sort -rn | head -10)
    echo "COLUMN 4 OUTPUT:"
    echo "$COL4_OUTPUT"
    echo ""
    
    if echo "$COL4_OUTPUT" | grep -qE "REG|unix|pipe|CHR"; then
        echo "✅ FOUND: Column 4 contains FD types"
        echo ""
        echo "FIX: Use column 4 instead of column 5"
        echo "  OLD: awk '{print \$5}'"
        echo "  NEW: awk '{print \$4}'"
    else
        echo "STEP 5: Check full line format"
        echo ""
        lsof 2>/dev/null | grep code | head -3 | while read line; do
            echo "LINE: $line"
            echo "  COL1: $(echo $line | awk '{print $1}')"
            echo "  COL2: $(echo $line | awk '{print $2}')"
            echo "  COL3: $(echo $line | awk '{print $3}')"
            echo "  COL4: $(echo $line | awk '{print $4}')"
            echo "  COL5: $(echo $line | awk '{print $5}')"
            echo ""
        done
    fi
else
    echo "✅ WORKING: Shows FD types correctly"
fi
echo ""

echo "═══════════════════════════════════════════════════════════════════"
echo "PROBLEM 2: Top FD consumers shows 'owner' in type column"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

echo "USER SHOWED THIS OUTPUT:"
echo "  Top FD consumers (count, process, PID, FD#, type):"
echo "    8240 code 123893 ThreadPoo owner  ← 'owner' should be FD type"
echo ""

echo "CURRENT CODE:"
echo "  lsof | grep code | awk '{print \$1, \$2, \$4, \$5}' | sort | uniq -c | sort -rn"
echo "  GETS: \$1=COMMAND, \$2=PID, \$4=FD, \$5=TYPE"
echo ""

echo "STEP 6: Test current code"
echo ""
TOP_FD=$(lsof 2>/dev/null | grep code | awk '{print $1, $2, $4, $5}' | sort | uniq -c | sort -rn | head -5)
echo "TOP FD OUTPUT:"
echo "$TOP_FD"
echo ""

if echo "$TOP_FD" | grep -q "owner"; then
    echo "❌ BROKEN: Shows 'owner' in type column"
    echo ""
    
    echo "ROOT CAUSE: lsof output without header has different format"
    echo "  When grepping, we lose the header line"
    echo "  Some processes have short names that shift columns"
    echo ""
    
    echo "STEP 7: Check lsof with -F (field output)"
    echo ""
    echo "ALTERNATIVE: Use lsof -F for parseable output"
    echo "  lsof -F pcft (p=PID, c=command, f=FD, t=type)"
    echo ""
    
    lsof -F pcft 2>/dev/null | grep -A3 "^ccode" | head -20
    echo ""
    
    echo "PROBLEM: -F output is hard to parse (one field per line)"
    echo ""
    
    echo "BETTER FIX: Use lsof with -n (no hostname lookup) and parse carefully"
    echo "  lsof -n | grep code | awk 'NF>=5 {print \$1, \$2, \$4, \$5}'"
    echo "  NF>=5 ensures line has at least 5 fields before accessing \$5"
    echo ""
    
    FIXED_OUTPUT=$(lsof -n 2>/dev/null | grep code | awk 'NF>=5 {print $1, $2, $4, $5}' | sort | uniq -c | sort -rn | head -5)
    echo "FIXED OUTPUT:"
    echo "$FIXED_OUTPUT"
    echo ""
    
    if echo "$FIXED_OUTPUT" | grep -qE "REG|unix|pipe|CHR"; then
        echo "✅ FIX WORKS: Now shows FD types correctly"
    else
        echo "❌ FIX FAILED: Still not showing FD types"
    fi
fi
echo ""

echo "═══════════════════════════════════════════════════════════════════"
echo "SOLUTION"
echo "═══════════════════════════════════════════════════════════════════"
echo ""

echo "CHANGE 1: Fix FD breakdown by type"
echo "  OLD: lsof | grep code | awk '{print \$5}' | sort | uniq -c | sort -rn"
echo "  NEW: lsof -n | grep code | awk 'NF>=5 {print \$5}' | sort | uniq -c | sort -rn"
echo "  REASON: NF>=5 ensures line has at least 5 fields, -n speeds up lsof"
echo ""

echo "CHANGE 2: Fix top FD consumers"
echo "  OLD: lsof | grep code | awk '{print \$1, \$2, \$4, \$5}' | sort | uniq -c | sort -rn"
echo "  NEW: lsof -n | grep code | awk 'NF>=5 {print \$1, \$2, \$4, \$5}' | sort | uniq -c | sort -rn"
echo "  REASON: NF>=5 filters out malformed lines, -n speeds up lsof"
echo ""

echo "VERIFICATION:"
echo ""
echo "FD breakdown by type (FIXED):"
lsof -n 2>/dev/null | grep code | awk 'NF>=5 {print $5}' | sort | uniq -c | sort -rn | head -10
echo ""

echo "Top FD consumers (FIXED):"
lsof -n 2>/dev/null | grep code | awk 'NF>=5 {print $1, $2, $4, $5}' | sort | uniq -c | sort -rn | head -10
echo ""

echo "END: diagnose-fd-breakdown-issue"

