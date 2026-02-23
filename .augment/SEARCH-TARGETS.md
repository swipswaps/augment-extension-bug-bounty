# EXACT SEARCH TARGETS IN extension.js

## File Location
```
~/.vscode/extensions/augment.vscode-augment-0.792.0/out/extension.js
```

## 🎯 Search Target #1: Timeout Wrapper (d2)

**Search for:**
```
function d2
```

**Or:**
```
setTimeout(()=>n(
```

**What you're looking for:**
```javascript
async function d2(e,t){
  return await new Promise((r,n)=>{
    let i=setTimeout(()=>n(new Error(...)),t);
    ...
  })
}
```

**What to verify:**
- [ ] Does it `clearTimeout` on resolve?
- [ ] Does it use `AbortController`?
- [ ] Does it dispose stream/body?
- [ ] Does it await cancellation?

**If NOT → This is your primary timeout trigger**

---

## 🎯 Search Target #2: Streaming Path

**Search for:**
```
getRemoteAgentOverviewsStream
```

**Then find:**
```
for await
```

**What you're looking for:**
```javascript
async*getRemoteAgentOverviewsStream(t,r){
  let n=await this.clientConfig.getConfig(),
      i={last_update_timestamp:t},
      o=await this.callApiStream(...);
  for await(let s of o)yield s  // ← NO CLEANUP!
}
```

**What to verify:**
- [ ] Is there a `finally` block?
- [ ] Is `stream.destroy()` called?
- [ ] Is `stream.return()` called?
- [ ] Is `AbortSignal` handled properly?

**If NOT → Every AbortError leaks a socket**

**Correct pattern:**
```javascript
async*getRemoteAgentOverviewsStream(t,r){
  let n=await this.clientConfig.getConfig(),
      i={last_update_timestamp:t},
      o=await this.callApiStream(...);
  try{
    for await(let s of o)yield s
  }finally{
    if(o&&typeof o.return==='function'){try{await o.return()}catch{}}
    if(o&&typeof o.destroy==='function'){try{o.destroy()}catch{}}
    if(o&&o.body&&typeof o.body.cancel==='function'){try{await o.body.cancel()}catch{}}
  }
}
```

---

## 🎯 Search Target #3: Completion Path

**Search for:**
```
fetch(
```

**And:**
```
stream:!1
```

**What you're looking for:**
Chat completion calls (line 64:4481 area)

**What to verify:**
- [ ] Is `res.body.cancel()` called?
- [ ] Is `res.arrayBuffer()` or `res.text()` fully awaited?
- [ ] Is there a `finally` around fetch?

**If response body is not consumed or canceled, undici keeps socket alive**

**Correct pattern:**
```javascript
const res = await fetch(url, { signal });

try {
  const data = await res.json();
  return data;
} finally {
  if (res.body && !res.bodyUsed) {
    try { await res.body.cancel(); } catch {}
  }
}
```

---

## 📊 Evidence from Logs

### Chat Completion Leak (Line 64:4481)
```
[truncation_cause_detected] Augment chat input completion API calls 
causing file descriptor leak and output truncation
STACK: SBe @ extension.js:64:4481
```

### Streaming Leak (Line 64:59334)
```
AbortError: This operation was aborted
Occurrences: 490
Repeats every ~60s
Call chain: d2@64:59334 → callApiStream@250:8939 → 
callApiStream@252:479212 → getRemoteAgentOverviewsStream@252:493
```

---

## 🔧 Quick Fix Commands

### Search in extension.js
```bash
# Find timeout wrapper
grep -n "function d2" ~/.vscode/extensions/augment.vscode-augment-0.792.0/out/extension.js

# Find streaming function
grep -n "getRemoteAgentOverviewsStream" ~/.vscode/extensions/augment.vscode-augment-0.792.0/out/extension.js

# Find fetch calls
grep -n "fetch(" ~/.vscode/extensions/augment.vscode-augment-0.792.0/out/extension.js | head -20

# Count for await loops
grep -c "for await" ~/.vscode/extensions/augment.vscode-augment-0.792.0/out/extension.js
```

### Extract context around line numbers
```bash
# Line 64:4481 (chat completion)
sed -n '64p' ~/.vscode/extensions/augment.vscode-augment-0.792.0/out/extension.js | \
  cut -c 4470-4500

# Line 64:59334 (timeout wrapper)
sed -n '64p' ~/.vscode/extensions/augment.vscode-augment-0.792.0/out/extension.js | \
  cut -c 59320-59350
```

---

## ✅ Expected Results After Fix

- **FD count**: 54,938 → ~8,000
- **AbortError frequency**: 490 occurrences → 0 (or harmless)
- **Truncation**: Eliminated
- **Tool calls**: Work after errors
- **System**: Stable

---

## 🚨 Why This Matters

**Primary trigger:** Timeout-based AbortError in undici transport

**Secondary amplifiers:**
- Retry loop
- Missing stream cleanup
- Missing body disposal
- Non-resetting close latch

**You have TWO leak vectors:**
1. Streaming API (getRemoteAgentOverviewsStream)
2. Completion API (chat input completion)

Both must be fixed for complete resolution.

