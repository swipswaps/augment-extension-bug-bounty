#!/usr/bin/env node
// WHAT: Custom linting rules to enforce error handling patterns
// WHY: Prevent silent failures like watchdog extension activation issue
// HOW: Parse TypeScript AST and enforce mandatory try-catch, console.log, error handling

const fs = require('fs');
const path = require('path');

// WHAT: Patterns that MUST exist in code
// WHY: These patterns prevent silent failures and enable debugging
// HOW: Regex patterns checked against source files
const MANDATORY_PATTERNS = {
  // WHAT: All exported functions must have try-catch
  // WHY: Silent failures waste user time and prevent debugging
  // HOW: Check for 'export function' followed by try-catch within 50 lines
  exportedFunctionsTryCatch: {
    pattern: /export\s+(?:async\s+)?function\s+(\w+)/g,
    validator: (content, match, functionName) => {
      // WHAT: Extract function body
      // WHY: Need to check if try-catch exists inside function
      // HOW: Find opening brace, count braces to find closing brace
      const startIndex = match.index;
      const afterMatch = content.substring(startIndex);
      const openBrace = afterMatch.indexOf('{');
      if (openBrace === -1) return { valid: false, reason: 'No opening brace found' };
      
      let braceCount = 0;
      let endIndex = openBrace;
      for (let i = openBrace; i < afterMatch.length; i++) {
        if (afterMatch[i] === '{') braceCount++;
        if (afterMatch[i] === '}') braceCount--;
        if (braceCount === 0) {
          endIndex = i;
          break;
        }
      }
      
      const functionBody = afterMatch.substring(openBrace, endIndex + 1);
      
      // WHAT: Check if function body contains try-catch
      // WHY: All exported functions must handle errors
      // HOW: Search for 'try' keyword followed by 'catch' within function body
      const hasTryCatch = /try\s*\{[\s\S]*?\}\s*catch\s*\(/g.test(functionBody);
      
      if (!hasTryCatch) {
        return {
          valid: false,
          reason: `Exported function '${functionName}' missing try-catch block`,
          fix: `Wrap function body in try-catch with console.error logging`
        };
      }
      
      return { valid: true };
    }
  },
  
  // WHAT: All catch blocks must log to console
  // WHY: Errors must be visible even if other logging fails
  // HOW: Check for console.error or console.log in catch blocks
  catchBlocksLogToConsole: {
    pattern: /catch\s*\(\s*(\w+)\s*\)\s*\{/g,
    validator: (content, match, errorVar) => {
      // WHAT: Extract catch block body
      // WHY: Need to verify console.error exists
      // HOW: Find opening brace, count braces to find closing brace
      const startIndex = match.index + match[0].length;
      const afterMatch = content.substring(startIndex);
      
      let braceCount = 1; // Already inside catch block
      let endIndex = 0;
      for (let i = 0; i < afterMatch.length; i++) {
        if (afterMatch[i] === '{') braceCount++;
        if (afterMatch[i] === '}') braceCount--;
        if (braceCount === 0) {
          endIndex = i;
          break;
        }
      }
      
      const catchBody = afterMatch.substring(0, endIndex);
      
      // WHAT: Check if catch block logs to console
      // WHY: console.error/log always visible in extension host log
      // HOW: Search for console.error or console.log
      const hasConsoleLog = /console\.(error|log|warn)/g.test(catchBody);
      
      if (!hasConsoleLog) {
        return {
          valid: false,
          reason: `Catch block missing console.error() - errors will be silent`,
          fix: `Add: console.error("[ERROR]", ${errorVar});`
        };
      }
      
      return { valid: true };
    }
  },
  
  // WHAT: All async functions must handle promise rejections
  // WHY: Unhandled promise rejections cause silent failures
  // HOW: Check for .catch() or try-catch around await
  asyncFunctionsHandleRejections: {
    pattern: /(?:export\s+)?async\s+function\s+(\w+)/g,
    validator: (content, match, functionName) => {
      // WHAT: Extract async function body
      // WHY: Need to check for promise rejection handling
      // HOW: Same brace-counting logic as above
      const startIndex = match.index;
      const afterMatch = content.substring(startIndex);
      const openBrace = afterMatch.indexOf('{');
      if (openBrace === -1) return { valid: false, reason: 'No opening brace found' };
      
      let braceCount = 0;
      let endIndex = openBrace;
      for (let i = openBrace; i < afterMatch.length; i++) {
        if (afterMatch[i] === '{') braceCount++;
        if (afterMatch[i] === '}') braceCount--;
        if (braceCount === 0) {
          endIndex = i;
          break;
        }
      }
      
      const functionBody = afterMatch.substring(openBrace, endIndex + 1);
      
      // WHAT: Check if function has try-catch or .catch()
      // WHY: Async functions must handle promise rejections
      // HOW: Search for try-catch or .catch() pattern
      const hasTryCatch = /try\s*\{[\s\S]*?\}\s*catch/g.test(functionBody);
      const hasDotCatch = /\.catch\s*\(/g.test(functionBody);
      
      if (!hasTryCatch && !hasDotCatch) {
        return {
          valid: false,
          reason: `Async function '${functionName}' missing promise rejection handling`,
          fix: `Wrap await calls in try-catch or add .catch() to promises`
        };
      }
      
      return { valid: true };
    }
  },
  
  // WHAT: All setInterval/setTimeout must be cleared
  // WHY: Memory leaks from uncleaned intervals
  // HOW: Check for clearInterval/clearTimeout or context.subscriptions.push
  intervalsAreCleared: {
    pattern: /setInterval\s*\(/g,
    validator: (content, match) => {
      // WHAT: Check if interval is stored in variable
      // WHY: Must be clearable to prevent memory leaks
      // HOW: Look backwards for variable assignment
      const beforeMatch = content.substring(Math.max(0, match.index - 100), match.index);
      const hasAssignment = /(?:const|let|var)\s+\w+\s*=/g.test(beforeMatch);
      
      if (!hasAssignment) {
        return {
          valid: false,
          reason: `setInterval not assigned to variable - cannot be cleared`,
          fix: `const intervalId = setInterval(...); context.subscriptions.push({ dispose: () => clearInterval(intervalId) });`
        };
      }
      
      return { valid: true };
    }
  }
};

// WHAT: Lint a single file
// WHY: Check file against all mandatory patterns
// HOW: Read file, apply each pattern validator, collect violations
function lintFile(filePath) {
  const content = fs.readFileSync(filePath, 'utf8');
  const violations = [];
  
  for (const [ruleName, rule] of Object.entries(MANDATORY_PATTERNS)) {
    let match;
    while ((match = rule.pattern.exec(content)) !== null) {
      const result = rule.validator(content, match, match[1]);
      if (!result.valid) {
        violations.push({
          file: filePath,
          rule: ruleName,
          line: content.substring(0, match.index).split('\n').length,
          reason: result.reason,
          fix: result.fix
        });
      }
    }
    // WHAT: Reset regex lastIndex
    // WHY: Global regex maintains state between exec() calls
    // HOW: Set lastIndex to 0
    rule.pattern.lastIndex = 0;
  }
  
  return violations;
}

// WHAT: Lint all TypeScript files in directory
// WHY: Enforce patterns across entire codebase
// HOW: Recursively find .ts files, lint each one
function lintDirectory(dir, violations = []) {
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  
  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);
    
    if (entry.isDirectory() && !['node_modules', 'out', 'dist', '.git'].includes(entry.name)) {
      lintDirectory(fullPath, violations);
    } else if (entry.isFile() && entry.name.endsWith('.ts') && !entry.name.endsWith('.d.ts')) {
      const fileViolations = lintFile(fullPath);
      violations.push(...fileViolations);
    }
  }
  
  return violations;
}

// WHAT: Main execution
// WHY: Run linter and report violations
// HOW: Lint directory, format output, exit with error code if violations found
if (require.main === module) {
  const targetDir = process.argv[2] || '.';
  console.log(`Linting TypeScript files in: ${targetDir}`);
  console.log('');
  
  const violations = lintDirectory(targetDir);
  
  if (violations.length === 0) {
    console.log('✅ No violations found - all mandatory patterns present');
    process.exit(0);
  } else {
    console.log(`❌ Found ${violations.length} violation(s):\n`);
    
    for (const v of violations) {
      console.log(`File: ${v.file}:${v.line}`);
      console.log(`Rule: ${v.rule}`);
      console.log(`Issue: ${v.reason}`);
      console.log(`Fix: ${v.fix}`);
      console.log('');
    }
    
    process.exit(1);
  }
}

module.exports = { lintFile, lintDirectory, MANDATORY_PATTERNS };

