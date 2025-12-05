# Complete Flow: From Query to Response

## Overview

This document describes the **complete flow** of what happens when a user sends a query to the backend, from the moment it arrives until the response is sent back.

---

## 🚀 Complete Flow Diagram

```
User Query
    ↓
[1] Request Validation
    ↓
[2] LLM Answer Generation (ALWAYS FIRST)
    ↓
[3] Intent Detection & Routing
    ↓
[4] Query Enhancement (Memory + Context)
    ↓
[5] Query Refinement (Repair + Memory + LLM)
    ↓
[6] Search (Products/Hotels/etc.)
    ↓
[7] Filtering Pipeline
    ├─ Lexical Filters
    ├─ Location Filters
    ├─ Attribute Filters
    ↓
[8] Reranking
    ↓
[9] LLM Correction
    ↓
[10] Description Generation (ONLY for final results)
    ↓
[11] Memory Filtering
    ↓
[12] Follow-up Suggestions
    ↓
[13] Response Building
    ↓
[14] Session Memory Update
    ↓
Response Sent to Frontend
```

---

## 📋 Detailed Step-by-Step Flow

### Step 1: Request Validation
**File:** `node/src/routes/agent.ts` (line 42-49)

**What happens:**
- Extract query from request body
- Validate query exists and is a string
- Extract session info (sessionId, conversationId, userId)
- Extract conversation history and context

**Input:**
```json
{
  "query": "nike shoes for men under $200",
  "conversationHistory": [...],
  "sessionId": "user123",
  "conversationId": "conv456"
}
```

**Output:**
- `cleanQuery`: Validated and trimmed query
- Session identifiers
- Conversation context

---

### Step 2: LLM Answer Generation (ALWAYS FIRST)
**File:** `node/src/routes/agent.ts` (line 60-76)
**Service:** `node/src/services/llmAnswer.ts`

**What happens:**
- **ALWAYS** generates LLM answer first (Perplexity-style)
- Uses conversation history for context
- Generates comprehensive answer with sources
- This answer is used later for card correction

**Why first?**
- Provides context for intent detection
- Used for card relevance checking
- Ensures answer is always available

**Output:**
- `llmAnswer`: Generated answer text
- `answerData`: Full answer with sources, locations, etc.

---

### Step 3: Intent Detection & Routing
**File:** `node/src/routes/agent.ts` (line 78-94)
**Service:** `node/src/followup/router.ts`

**What happens:**
1. **Semantic Intent Detection** (`detectSemanticIntent`)
   - Fast keyword router
   - LLM classifier
   - Embedding fallback
   - Detects: shopping, hotels, restaurants, flights, places, movies, answer

2. **Follow-up Intent Detection** (if follow-up query)
   - Checks if query is refining previous intent
   - Detects context switches

3. **Card Analyzer** (`analyzeCardNeed`)
   - Extracts entities (brand, category, price, city)
   - Hard types the query (shopping, hotel, etc.)

4. **Final Routing Decision**
   - Combines all signals
   - Determines final intent and card type

**Output:**
```typescript
{
  finalIntent: "shopping",
  finalCardType: "shopping",
  brand: "nike",
  category: "shoes",
  price: "200",
  city: null
}
```

---

### Step 4: Query Enhancement (Memory + Context)
**File:** `node/src/routes/agent.ts` (line 103-149)

**What happens:**
1. **Check if enhancement needed**
   - Only for shopping/travel/movies intents
   - NOT for answer/general queries

2. **Context Merging** (if follow-up query)
   - Merges brand, category, price, city from parent query
   - Only if not already in current query

3. **Memory Enhancement** (via `buildRefinedQuery`)
   - Adds brand, category, gender from session memory
   - Adds location for hotels/restaurants
   - **Smart context management**: Only adds if refining, not changing

**Example:**
```
Query: "for men"
Previous: "nike shoes"
Memory: { brand: "nike", category: "shoes" }
Enhanced: "nike shoes for men"
```

---

### Step 5: Query Refinement (Repair + Memory + LLM)
**File:** `node/src/routes/agent.ts` (line 153-155)
**Services:** 
- `node/src/services/queryRepair.ts`
- `node/src/refinement/refineQuery.ts`

**What happens:**

#### 5a. Query Repair (`repairQuery`)
- Fixes typos: "nike shos" → "nike shoes"
- Merges broken words: "su per man" → "superman"
- Domain-aware (shopping, hotels, etc.)

#### 5b. Query Refinement (`refineQuery`)
- **Memory Enhancement** (`buildRefinedQuery`)
  - Adds context from session memory
  - Smart: Only adds if refining, not changing
  
- **LLM Rewrite** (`llmRewrite`)
  - Optimizes query for search engines
  - Makes query more specific
  - Removes filler words

**Example:**
```
Original: "nike shos for men"
Repaired: "nike shoes for men"
Memory-enhanced: "nike shoes for men" (already has brand/category)
LLM-rewritten: "nike men's running shoes"
```

---

### Step 6: Search (Products/Hotels/etc.)
**File:** `node/src/routes/agent.ts` (line 157-255)
**Services:**
- `node/src/services/productSearch.ts`
- `node/src/services/hotelSearch.ts`
- etc.

**What happens:**

#### For Shopping:
1. **Query Repair** (in `searchProducts`)
2. **Provider Search** (via `ProviderManager`)
   - Query optimization (removes price constraints)
   - Searches SerpAPI (or other providers)
   - Backend filtering (price, gender, etc.)
3. **Retry Logic** (if < 3 results)
   - Tries refined query
   - Tries fallback providers

#### For Hotels:
1. **Query Repair** (in `searchHotels`)
2. **SerpAPI Hotel Search**
3. **Geocoding** (if coordinates missing)
4. **Retry Logic** (if < 3 results)

**Output:**
- Raw results (15-20 items typically)
- NO descriptions generated yet (performance optimization)

---

### Step 7: Filtering Pipeline
**File:** `node/src/routes/agent.ts` (line 167-194)

**What happens (in order):**

#### 7a. Lexical Filters (`applyLexicalFilters`)
- **Price filters**: "under $200" → filters by price
- **Gender filters**: "for men" → filters by gender
- **Category filters**: "shoes" → filters by category
- Hard filters (removes items that don't match)

#### 7b. Location Filters (`filterHotelsByLocation`, etc.)
- **Area extraction**: "downtown", "airport", "beach"
- **Location matching**: Filters by address/location text
- Only for hotels, restaurants, places

#### 7c. Attribute Filters (`applyAttributeFilters`)
- **Semantic matching**: "wide fit", "waterproof", "polarized"
- Uses embeddings for similarity
- Soft filters (scores and sorts)

**Output:**
- Filtered results (typically 5-10 items after filtering)

---

### Step 8: Reranking
**File:** `node/src/routes/agent.ts` (line 172, 192, etc.)
**Service:** `node/src/reranker/cardReranker.ts`

**What happens:**
- Uses embeddings to score relevance
- Combines multiple signals:
  - Semantic similarity (55%)
  - Brand match (20%)
  - Category match (15%)
  - Price match (10%)
- Sorts by final score

**Output:**
- Reranked results (most relevant first)

---

### Step 9: LLM Correction
**File:** `node/src/routes/agent.ts` (line 174, 194, etc.)
**Service:** `node/src/correctors/llmCardCorrector.ts`

**What happens:**
- LLM checks if cards match the answer summary
- Removes irrelevant items
- Validates price, gender, category constraints
- Only removes if clearly wrong (conservative)

**Output:**
- Corrected results (irrelevant items removed)

---

### Step 10: Description Generation (ONLY for Final Results)
**File:** `node/src/routes/agent.ts` (line 176-178, 200-202)
**Services:**
- `node/src/services/productSearch.ts` → `enrichProductsWithDescriptions`
- `node/src/services/hotelSearch.ts` → `enrichHotelsWithThemesAndDescriptions`

**What happens:**
- **ONLY** generates descriptions for final displayed results
- **NOT** for all fetched results (performance optimization)
- Uses batching (5 items at a time) to avoid rate limits
- Generates Perplexity-style 2-3 sentence descriptions

**Why here?**
- After all filtering, we know exactly what will be displayed
- Prevents wasting API calls on items that won't be shown
- Matches Perplexity/ChatGPT approach

**Output:**
- Results with LLM-generated descriptions

---

### Step 11: Memory Filtering
**File:** `node/src/routes/agent.ts` (line 727-780)

**What happens:**
- Gets session memory (previous queries)
- Filters by:
  - **Brand** (if in session)
  - **Category** (if in session)
  - **Price** (if in session)
  - **Gender** (if in session)
- Only for shopping/hotels (not places/movies)

**Example:**
```
Session: { brand: "nike", category: "shoes" }
Results: 10 products
After memory filter: 5 products (only nike shoes)
```

**Output:**
- Memory-filtered results

---

### Step 12: Follow-up Suggestions
**File:** `node/src/routes/agent.ts` (line 620-664)
**Service:** `node/src/followup/`

**What happens:**
- Generates follow-up suggestions (Perplexity-style)
- Analyzes query to suggest related searches
- Reranks suggestions by relevance
- Extracts slots (brand, category, price, city)

**Output:**
- Follow-up suggestions array
- Behavior state (refining, exploring, etc.)

---

### Step 13: Response Building
**File:** `node/src/routes/agent.ts` (line 757-820)

**What happens:**
1. **Determine final cards**
   - Use enforced cards (if follow-up) or regular results
   - Apply minimum threshold logic (retry if < 3 cards)

2. **Build response object:**
   ```json
   {
     "success": true,
     "intent": "shopping",
     "summary": "LLM answer...",
     "answer": "LLM answer...",
     "cardType": "shopping",
     "followUps": [...],
     "results": [...],
     "products": [...],
     "cards": [...]
   }
   ```

3. **Special handling:**
   - Hotels: Group by sections, extract map points
   - Movies: Format movie data
   - Places: Format place data

**Output:**
- Complete response object ready to send

---

### Step 14: Session Memory Update
**File:** `node/src/routes/agent.ts` (line 820-830)
**Service:** `node/src/memory/sessionMemory.ts`

**What happens:**
- Saves session state:
  - Domain (shopping, hotels, etc.)
  - Brand, category, price, city
  - Gender
  - Last query and answer
- Used for next query's context

**Output:**
- Session state saved in memory

---

### Step 15: Response Sent
**File:** `node/src/routes/agent.ts` (line 875)

**What happens:**
- Sends JSON response to frontend
- Includes:
  - LLM answer
  - Cards/results
  - Follow-up suggestions
  - Intent and metadata

---

## 🔄 Complete Example Flow

### Query: "nike shoes for men under $200"

```
[1] Request Validation
    ✅ Query validated

[2] LLM Answer Generation
    → "Nike offers several men's shoe options under $200..."

[3] Intent Detection
    → Intent: "shopping", CardType: "shopping"
    → Brand: "nike", Category: "shoes", Price: "200"

[4] Query Enhancement
    → Query: "nike shoes for men under $200" (no change needed)

[5] Query Refinement
    → Repair: "nike shoes for men under $200" (no typos)
    → Memory: Adds nothing (already complete)
    → LLM: "nike men's running shoes under $200"

[6] Search
    → ProviderManager optimizes: "nike men's running shoes"
    → SerpAPI returns: 15 products
    → Backend filters: 12 products (removed items over $200)

[7] Filtering Pipeline
    → Lexical: 10 products (gender filter)
    → Location: N/A (shopping)
    → Attribute: 10 products (no attribute filters)

[8] Reranking
    → 10 products sorted by relevance

[9] LLM Correction
    → 8 products (removed 2 irrelevant)

[10] Description Generation
    → Generate descriptions for 8 products (8 API calls)
    → Batched: 5 + 3 (with delays)

[11] Memory Filtering
    → 8 products (no memory filters applied)

[12] Follow-up Suggestions
    → ["nike running shoes for women", "nike shoes under $150", ...]

[13] Response Building
    → Final: 8 products with descriptions

[14] Session Memory Update
    → Saved: { domain: "shopping", brand: "nike", category: "shoes", price: 200 }

[15] Response Sent
    → Frontend receives 8 products with descriptions
```

---

## ⚡ Performance Optimizations

1. **Description Generation**: Only for final displayed results (not all fetched)
2. **Batching**: Descriptions generated in batches of 5
3. **Query Optimization**: Removes price constraints from API queries
4. **Backend Filtering**: More accurate than API text search
5. **Smart Context**: Only adds context when refining, not changing

---

## 📊 Key Metrics

- **Total Steps**: 15 major steps
- **LLM Calls**: 
  - Answer generation: 1
  - Query repair: 1-2
  - Query refinement: 1-2
  - Description generation: Only for final results (3-10 typically)
  - Card correction: 1
- **API Calls**:
  - Search API: 1-3 (with retries)
  - Description API: Only for displayed results

---

## 🎯 Summary

The flow is designed to be:
1. **Efficient**: Only generates what's needed
2. **Accurate**: Multiple filtering layers
3. **Professional**: Matches Perplexity/ChatGPT approach
4. **Context-aware**: Uses memory and conversation history
5. **Performance-optimized**: Minimizes API calls and latency

