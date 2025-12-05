# Query Repair & Refinement System Explained

## Overview

The system has **TWO main stages** of query processing:

1. **Query Repair** - Fixes typos and broken words (happens FIRST)
2. **Query Refinement** - Enhances query with memory and LLM rewriting (happens SECOND)

## Complete Flow

```
User Query
    ↓
[1] Query Repair (repairQuery)
    → Fixes typos: "nike shos" → "nike shoes"
    → Merges broken words: "su per man" → "superman"
    ↓
[2] Query Refinement (refineQuery)
    → Step 2a: Memory Enhancement (buildRefinedQuery)
       → Adds brand, category, gender from session memory
    → Step 2b: LLM Rewrite (llmRewrite)
       → Optimizes for search engines
    ↓
[3] Provider Search
    → Query Optimization (ProviderManager)
       → Removes price constraints, improves gender queries
    → Backend Filtering
       → Applies price, gender, etc. filters
    ↓
Results
```

---

## Stage 1: Query Repair (`repairQuery`)

**File:** `node/src/services/queryRepair.ts`

### Purpose
Fixes typos and merges broken words **BEFORE** any search happens.

### How It Works

1. **Uses LLM (GPT-4o-mini)** to understand intent
2. **Domain-aware** - knows if it's shopping, hotels, movies, etc.
3. **Fixes common issues:**
   - Typos: `"nike shos"` → `"nike shoes"`
   - Broken words: `"su per man"` → `"superman"`
   - Merged words: `"wicke dfor"` → `"wicked for"`
   - Brand names: `"hiltn htels"` → `"hilton hotels"`

### Example

```typescript
Input:  "nike shos for men"
Output: "nike shoes for men"

Input:  "wicke dfor good movie"
Output: "wicked for good movie"
```

### Key Rules
- ✅ Fixes typos
- ✅ Merges broken words
- ✅ Preserves original intent
- ❌ Does NOT add extra words
- ❌ Does NOT simplify query

### When It Runs
- **ALWAYS** first, before any search
- Runs in `productSearch.ts`, `hotelSearch.ts`, etc.

---

## Stage 2: Query Refinement (`refineQuery`)

**File:** `node/src/refinement/refineQuery.ts`

### Purpose
Enhances the repaired query with **memory context** and **LLM optimization**.

### Two-Step Process

#### Step 2a: Memory Enhancement (`buildRefinedQuery`)

**File:** `node/src/refinement/buildQuery.ts`

**What it does:**
- Adds context from **session memory** (previous queries)
- Adds brand, category, gender if user mentioned them before
- Adds location for hotels/restaurants
- Adds intent-specific attributes (running, wide fit, etc.)

**Example:**

```typescript
// User's previous query: "nike shoes"
// Session memory: { brand: "nike", category: "shoes" }

// Current query: "for men"
// Memory-enhanced: "nike shoes for men"
```

**What gets added:**
- ✅ Brand (if in session memory)
- ✅ Category (if in session memory)
- ✅ Gender (if in session memory)
- ✅ City (for hotels/restaurants)
- ✅ Purpose (running, hiking, etc.)
- ❌ Price (only if explicitly mentioned in current query)

#### Step 2b: LLM Rewrite (`llmRewrite`)

**File:** `node/src/refinement/llmRewrite.ts`

**What it does:**
- Uses **LLM (GPT-4o-mini)** to optimize query for search engines
- Makes query more specific and search-friendly
- Removes filler words
- Ensures proper format

**Example:**

```typescript
Input:  "nike shoes for men"
Output: "nike men's running shoes"  // More specific, better for search

Input:  "rayban glasses"
Output: "rayban unisex polarized sunglasses best price"
```

**Key Rules:**
- ✅ Includes product type/category
- ✅ Includes brand if present
- ✅ Includes purpose ("for running")
- ✅ Includes gender
- ❌ Does NOT add price unless explicitly mentioned
- ❌ Removes filler words

---

## Complete Example Flow

### Example 1: Shopping Query

```
User: "nike shos for men under 200"

[1] Query Repair:
    "nike shos for men under 200"
    → "nike shoes for men under 200"  (fixed typo)

[2] Query Refinement:
    Step 2a (Memory): 
      Session: { brand: "nike", category: "shoes" }
      → "nike shoes for men under 200"  (already has brand/category)
    
    Step 2b (LLM Rewrite):
      → "nike men's running shoes under $200"  (more specific)

[3] Provider Search:
    Query Optimization:
      → "nike men's running shoes"  (price removed, filtered on backend)
    
    Backend Filtering:
      → Removes items over $200
```

### Example 2: Hotel Query

```
User: "hotels near airport slc"

[1] Query Repair:
    "hotels near airport slc"
    → "hotels near airport slc"  (no typos, no change)

[2] Query Refinement:
    Step 2a (Memory):
      Session: { city: "Salt Lake City" }
      → "hotels near Salt Lake City airport slc"
    
    Step 2b (LLM Rewrite):
      → "hotels near Salt Lake City airport"  (cleaned up)

[3] Provider Search:
    Query Optimization:
      → "hotels near Salt Lake City airport"  (airport code expanded)
```

---

## Where Each Function is Used

### `repairQuery` (Query Repair)
- ✅ `productSearch.ts` - Line 365
- ✅ `hotelSearch.ts` - Used for hotels
- ✅ All search services - First step

### `refineQuery` (Query Refinement)
- ✅ `agent.ts` - Line 153 (main refinement)
- ✅ `productSearch.ts` - Line 383 (retry with refined query)
- ✅ Used for shopping, hotels, restaurants, flights

### `buildRefinedQuery` (Memory Enhancement)
- ✅ Called by `refineQuery` - Step 2a
- ✅ Uses session memory from `sessionMemory.ts`

### `llmRewrite` (LLM Optimization)
- ✅ Called by `refineQuery` - Step 2b
- ✅ Final optimization step

---

## Old vs New System

### Old System (`llmQueryRefiner.ts`)
- Simple LLM refinement
- Still used in some places (line 639 in agent.ts)
- Less sophisticated

### New System (`refinement/refineQuery.ts`)
- **Memory-aware** (uses session context)
- **Two-step process** (memory + LLM)
- **More sophisticated**
- **Primary system** used in most places

---

## Key Differences

| Function | Purpose | When | Input | Output |
|----------|---------|------|-------|--------|
| `repairQuery` | Fix typos | First | Raw query | Fixed query |
| `buildRefinedQuery` | Add memory | Second (step 1) | Repaired query | Memory-enhanced query |
| `llmRewrite` | Optimize | Second (step 2) | Memory-enhanced query | Optimized query |
| `refineQuery` | Complete refinement | Second (both steps) | Repaired query | Fully refined query |

---

## Summary

1. **Query Repair** = Fix typos/broken words (always first)
2. **Query Refinement** = Enhance with memory + LLM (always second)
3. **Provider Optimization** = Remove price constraints, improve queries (in provider)
4. **Backend Filtering** = Apply price/gender filters (after search)

All working together to give you the best search results! 🎯

