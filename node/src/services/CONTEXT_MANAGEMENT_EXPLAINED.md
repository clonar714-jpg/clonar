# Context Management Problem & Solution

## The Problem You Identified

### Scenario:
1. **Previous query:** "nike running shoes" (user bought them)
2. **Session memory:** `{ brand: "nike", category: "shoes", intentSpecific: { running: true } }`
3. **Current query:** "nike shoes" (user wants casual wear, NOT running)
4. **Problem:** System adds "running" from memory → Wrong results! ❌

### Current Code Issue

**File:** `node/src/refinement/buildQuery.ts` (lines 48-61)

```typescript
// ❌ PROBLEM: This blindly adds "running" from memory
if (s.intentSpecific.running && !refined.includes("running")) {
  refined += " running";  // ← Adds "running" even if user wants casual!
}
```

**Result:**
```
User: "nike shoes"
Memory: { running: true }
Output: "nike shoes running"  ❌ WRONG!
```

---

## How Professional Systems Handle This

### ChatGPT & Perplexity Approach

They use **LLM-based intent detection** to decide when to use context vs ignore it:

1. **Detect Intent Change**
   - LLM analyzes: "Does the user want something DIFFERENT from previous query?"
   - If yes → Ignore conflicting context
   - If no → Use context

2. **Semantic Understanding**
   - "nike shoes" (general) vs "nike running shoes" (specific)
   - If current query is MORE GENERAL → Don't add specific attributes
   - If current query is MORE SPECIFIC → Use context

3. **Explicit vs Implicit**
   - If user explicitly says "casual" → Clear intent change, ignore "running"
   - If user says just "nike shoes" → Ambiguous, but don't assume "running"

### Example from Professional Systems

**ChatGPT/Perplexity behavior:**

```
Previous: "nike running shoes"
Current: "nike shoes"

ChatGPT/Perplexity thinks:
- User said "nike shoes" (general)
- Previous was "running" (specific)
- User might want something different
- Don't add "running" automatically
- Search for general "nike shoes"
```

**But if:**

```
Previous: "nike running shoes"
Current: "nike running shoes for men"

ChatGPT/Perplexity thinks:
- User is refining the SAME intent (running shoes)
- Add "men" from context if available
- Keep "running" because it's in current query
```

---

## The Solution

### Option 1: LLM-Based Intent Detection (Professional Approach)

Add an LLM check BEFORE adding context:

```typescript
async function shouldUseContext(
  currentQuery: string,
  previousContext: SessionState
): Promise<boolean> {
  // Use LLM to detect if user wants something different
  const prompt = `
User's previous query was about: ${previousContext.intentSpecific?.running ? 'running shoes' : 'general'}
Current query: "${currentQuery}"

Does the user want something DIFFERENT from previous query?
- If current query is MORE GENERAL (e.g., "nike shoes" vs "nike running shoes") → return "no"
- If current query is MORE SPECIFIC (e.g., "nike running shoes for men" vs "nike running shoes") → return "yes"
- If user explicitly mentions different purpose (e.g., "casual", "dress") → return "no"

Return only "yes" or "no".
`;

  const response = await llm.call(prompt);
  return response.toLowerCase().includes("yes");
}
```

### Option 2: Heuristic-Based (Simpler)

Check if current query is more general than previous:

```typescript
function shouldUseContext(currentQuery: string, previousContext: SessionState): boolean {
  const current = currentQuery.toLowerCase();
  const previous = previousContext.lastQuery?.toLowerCase() || "";
  
  // If current query is MORE GENERAL, don't add specific attributes
  if (previous.includes("running") && !current.includes("running")) {
    // Previous was specific (running), current is general
    // Don't add "running" unless user explicitly mentions it
    return false;
  }
  
  // If current query is MORE SPECIFIC, use context
  if (current.includes("running") || current.includes("casual") || current.includes("dress")) {
    // User is being specific, use their current query
    return false; // Don't add from memory, user is explicit
  }
  
  // If current query is same level of specificity, use context
  return true;
}
```

### Option 3: Only Add Context for Refinements (Safest)

Only add context when user is clearly REFINING, not changing:

```typescript
// Only add "running" if:
// 1. User's current query already mentions "running" (refining)
// 2. OR user's query is very vague and needs context

if (s.intentSpecific.running) {
  // Only add if user is refining (query already has "running")
  // OR if query is very vague (just "nike" or "shoes")
  const isRefining = refined.includes("running");
  const isVeryVague = refined.split(" ").length <= 2;
  
  if (isRefining || isVeryVague) {
    refined += " running";
  }
  // Otherwise, user might want something different - don't add
}
```

---

## Recommended Fix

**Best approach:** Combine Option 2 (heuristic) + Option 3 (safety check)

```typescript
// In buildRefinedQuery function:

// Intent-specific attributes - ONLY add if user is refining, not changing
if (s.intentSpecific) {
  const currentQuery = refined.toLowerCase();
  const previousQuery = s.lastQuery?.toLowerCase() || "";
  
  // Check if user is REFINING (same intent) vs CHANGING (different intent)
  const isRefining = 
    // User explicitly mentions the same attribute
    (s.intentSpecific.running && currentQuery.includes("running")) ||
    // OR user's query is very vague (needs context)
    (currentQuery.split(" ").length <= 2 && !currentQuery.includes("casual") && !currentQuery.includes("dress"));
  
  // Check if user explicitly wants something DIFFERENT
  const wantsDifferent = 
    currentQuery.includes("casual") || 
    currentQuery.includes("dress") || 
    currentQuery.includes("lifestyle") ||
    (previousQuery.includes("running") && !currentQuery.includes("running") && currentQuery.split(" ").length > 2);
  
  if (isRefining && !wantsDifferent) {
    // Safe to add context
    if (s.intentSpecific.running && !refined.includes("running")) {
      refined += " running";
    }
    // ... other attributes
  }
  // Otherwise, don't add - user might want something different
}
```

---

## Summary

### Current Problem
- System blindly adds "running" from memory
- Doesn't detect when user wants something different
- Results in wrong search results

### Professional Solution
- **Detect intent change** (LLM or heuristics)
- **Only add context when refining**, not when changing
- **Respect user's explicit intent** (if they say "casual", ignore "running")

### Key Principle
> **"When in doubt, don't add context. Let the user be explicit."**

This is safer and matches how ChatGPT/Perplexity work - they're conservative about adding context unless they're confident the user wants it.

