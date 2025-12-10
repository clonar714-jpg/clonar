# 🎯 Phase 3: "Of My Taste" Matching - Implementation Complete

## ✅ What's Implemented

Phase 3 uses **embeddings** to match products to user preferences, providing personalized results for "of my taste" queries.

### Key Features

1. **Preference Profile Building**
   - Converts user preferences into a text description
   - Includes: brands, styles, price ranges, category-specific preferences
   - Creates embedding from preference profile

2. **Embedding-Based Matching**
   - Scores each product against preference profile using cosine similarity
   - Adds boosts for exact matches (brand, style, price)
   - Reranks products by preference similarity

3. **Hybrid Reranking**
   - Combines query relevance (60%) with preference matching (40%)
   - Works for all queries (not just "of my taste")
   - Balances search relevance with personalization

4. **Smart Integration**
   - "Of my taste" queries: Pure preference matching
   - Regular queries: Hybrid reranking (query + preferences)
   - No preferences: Falls back to regular reranking

---

## 📁 Files Created/Modified

### New Files
- `node/src/services/personalization/preferenceMatcher.ts`
  - `buildPreferenceProfile()`: Builds text description from preferences
  - `matchProductsToPreferences()`: Matches products using embeddings
  - `hybridRerank()`: Combines query + preference relevance

### Modified Files
- `node/src/routes/agent.ts`
  - Added Phase 3 matching for "of my taste" queries
  - Added hybrid reranking for regular queries
  - Integrated with existing reranking pipeline

---

## 🔄 How It Works

### Flow for "Of My Taste" Queries

```
User Query: "glasses of my taste"
    ↓
1. Extract category: "glasses"
    ↓
2. Load user preferences from database
    ↓
3. Build preference profile:
   "User preferences: prefers brands: Prada. prefers luxury style. prefers products under $500"
    ↓
4. Get embedding for preference profile
    ↓
5. Search products (normal search)
    ↓
6. For each product:
   - Get product embedding
   - Calculate similarity to preference profile
   - Add boosts for exact matches (brand, style, price)
    ↓
7. Rerank by preference similarity
    ↓
8. Return top matches
```

### Flow for Regular Queries (Hybrid)

```
User Query: "glasses"
    ↓
1. Search products
    ↓
2. Get query embedding
    ↓
3. Get preference profile embedding (if available)
    ↓
4. For each product:
   - Calculate query similarity (60% weight)
   - Calculate preference similarity (40% weight)
   - Combine into hybrid score
    ↓
5. Rerank by hybrid score
    ↓
6. Return results
```

---

## 🧠 Intelligence Rules

### Preference Profile Building

**Includes:**
- Top 3 brand preferences
- Top 3 style keywords
- Price range (min/max)
- Category-specific preferences (if category matches)

**Example Profile:**
```
"User preferences: prefers brands: Prada, Gucci. prefers luxury style. prefers products under $500. prefers Prada for glasses"
```

### Matching Algorithm

1. **Semantic Similarity** (Base Score)
   - Cosine similarity between product embedding and preference profile embedding
   - Range: 0.0 to 1.0

2. **Exact Match Boosts**
   - Brand match: +0.2
   - Style match: +0.15
   - Price match: +0.1

3. **Final Score**
   - `min(similarity + boosts, 1.0)`
   - Products sorted by score (highest first)

### Hybrid Reranking

**Weights:**
- Query relevance: 60%
- Preference matching: 40%

**Formula:**
```
hybridScore = querySimilarity × 0.6 + preferenceSimilarity × 0.4
```

---

## 📊 Examples

### Example 1: "Of My Taste" Query

**User Query:** "glasses of my taste"

**User Preferences:**
```json
{
  "brand_preferences": ["Prada"],
  "style_keywords": ["luxury"],
  "price_range_max": 500,
  "category_preferences": {
    "glasses": { "brands": ["Prada"], "style": "luxury" }
  },
  "confidence_score": 0.8
}
```

**Preference Profile:**
```
"User preferences: prefers brands: Prada. prefers luxury style. prefers products under $500. prefers Prada for glasses"
```

**Result:**
- Products matching Prada + luxury + under $500 ranked highest
- Semantic similarity ensures style/quality matches
- Exact brand/style matches get boosts

### Example 2: Regular Query with Hybrid Reranking

**User Query:** "glasses"

**User Preferences:** (same as above)

**Result:**
- Products relevant to "glasses" (query similarity)
- PLUS products matching user preferences (preference similarity)
- Balanced ranking: 60% query relevance, 40% preferences

### Example 3: No Preferences

**User Query:** "glasses"

**User Preferences:** None or low confidence

**Result:**
- Falls back to regular reranking
- No preference matching applied
- Normal search behavior

---

## 🔍 Integration Points

### In `agent.ts` (Shopping Case)

```typescript
// 4. Rerank using embeddings (C7) OR Phase 3 preference matching
const category = extractCategoryFromQuery(cleanQuery, finalIntent);
if (isPersonalizationQuery && userId && userId !== "global" && userId !== "dev-user-id") {
  // ✅ PHASE 3: "Of My Taste" - Match products to preferences using embeddings
  results = await matchProductsToPreferences(rawShoppingCards, userId, category);
} else if (userId && userId !== "global" && userId !== "dev-user-id") {
  // ✅ PHASE 3: Hybrid reranking (combine query relevance + preferences)
  results = await hybridRerank(rawShoppingCards, refinedQuery, userId, category, 0.6, 0.4);
} else {
  // Regular reranking (no preferences)
  results = await rerankCards(refinedQuery, rawShoppingCards, "shopping");
}
```

### Decision Logic

1. **"Of my taste" query** → Pure preference matching
2. **Regular query + preferences** → Hybrid reranking
3. **No preferences** → Regular reranking

---

## ⚠️ Important Notes

1. **Requires Preferences**: Phase 3 only works if user has preferences in database
   - Minimum confidence: 30%
   - Run `aggregateUserPreferences()` to build preferences

2. **Performance**: Embedding calls add latency
   - ~300ms per embedding call
   - Batch processing used where possible
   - Caching helps reduce calls

3. **Confidence Thresholds**:
   - Minimum: 30% to consider preferences
   - "Of my taste": Uses preferences if available
   - Hybrid: Only if confidence ≥ 30%

4. **Fallback Behavior**:
   - If preference matching fails → Falls back to regular reranking
   - If no preferences → Uses regular reranking
   - Errors don't break the flow

---

## 🧪 Testing

### To Test Phase 3

1. **Ensure user has preferences**:
   ```sql
   INSERT INTO user_preferences (user_id, brand_preferences, style_keywords, price_range_max, confidence_score)
   VALUES ('user-id', ARRAY['Prada'], ARRAY['luxury'], 500, 0.8);
   ```

2. **Test "of my taste" query**:
   - Query: "glasses of my taste"
   - Should rank Prada luxury glasses highest
   - Check logs: `🎯 Phase 3: Matching X products to preferences`

3. **Test hybrid reranking**:
   - Query: "glasses"
   - Should balance query relevance + preferences
   - Check logs: `🎯 Phase 3: Using hybrid reranking`

4. **Check scores**:
   - Look for: `🎯 Phase 3: Top 3 preference matches (scores: ...)`
   - Higher scores = better preference matches

---

## 🚀 Next Steps (Phase 4)

- **Phase 4**: Background jobs for automatic aggregation
  - Aggregate preferences every 5 conversations
  - Update preferences every 24 hours
  - Clean up old signals

---

## ✅ Status

**Phase 3: COMPLETE** ✅

- Preference profile building implemented
- Embedding-based matching implemented
- Hybrid reranking implemented
- Integrated into agent route
- Ready for testing

