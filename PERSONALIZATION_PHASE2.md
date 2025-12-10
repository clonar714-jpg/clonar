# 🎯 Phase 2: Query Enhancement - Implementation Complete

## ✅ What's Implemented

Phase 2 enhances **all queries** with user preferences from the database, not just "of my type" queries.

### Key Features

1. **Automatic Query Enhancement**
   - Loads user preferences before query refinement
   - Enhances queries for shopping, hotels, restaurants, flights, places
   - Only applies when preferences have sufficient confidence (≥30%)

2. **Intelligent Preference Application**
   - **Brand preferences**: Added for shopping queries (if user hasn't specified a brand)
   - **Style keywords**: Added for shopping/hotels (luxury, budget, etc.)
   - **Price range**: Added for shopping (only if query is vague and confidence ≥60%)
   - **Category-specific**: Applies preferences based on detected category (glasses, shoes, etc.)

3. **Smart Conflict Detection**
   - Doesn't add preferences if user already specified them
   - Doesn't override explicit user choices
   - Only enhances vague/general queries

---

## 📁 Files Created/Modified

### New Files
- `node/src/services/personalization/queryEnhancer.ts`
  - `enhanceQueryWithPreferences()`: Main enhancement function
  - `extractCategoryFromQuery()`: Extracts category from query

### Modified Files
- `node/src/routes/agent.ts`
  - Added Phase 2 enhancement before query refinement
  - Integrated with existing "of my type" personalization

---

## 🔄 How It Works

### Flow
```
User Query → Phase 2 Enhancement → Session Memory → Query Refinement → Search
                ↓
        Load user_preferences
                ↓
        Apply preferences (if relevant)
                ↓
        Enhanced query
```

### Example Enhancements

**Example 1: Brand Preference**
```
User Query: "glasses"
User Preferences: { brand_preferences: ["Prada"], confidence_score: 0.6 }
Enhanced: "Prada glasses"
```

**Example 2: Style Preference**
```
User Query: "hotels in miami"
User Preferences: { style_keywords: ["luxury"], confidence_score: 0.7 }
Enhanced: "hotels in miami luxury"
```

**Example 3: Category-Specific**
```
User Query: "glasses"
User Preferences: { 
  category_preferences: { 
    "glasses": { brands: ["Prada"], style: "luxury" } 
  },
  confidence_score: 0.8
}
Enhanced: "Prada glasses luxury"
```

**Example 4: Price Range**
```
User Query: "shoes" (vague, 1 word)
User Preferences: { price_range_max: 200, confidence_score: 0.65 }
Enhanced: "shoes under $200"
```

---

## 🧠 Intelligence Rules

### When Preferences Are Applied

1. **Brand Preferences**
   - ✅ Applied if: Query is vague (≤2 words) OR confidence ≥50%
   - ❌ Not applied if: Query already mentions a brand

2. **Style Keywords**
   - ✅ Applied if: Confidence ≥50% AND intent is shopping/hotels
   - ❌ Not applied if: Query already mentions style keywords

3. **Price Range**
   - ✅ Applied if: Query is vague (≤3 words) AND confidence ≥60%
   - ❌ Not applied if: Query already mentions price

4. **Category-Specific**
   - ✅ Applied if: Category matches AND preferences exist
   - ❌ Not applied if: Query already contains the preference

### Confidence Thresholds

- **Minimum**: 30% (to even consider preferences)
- **Brand**: 40% (or vague query)
- **Style**: 50%
- **Price**: 60% (more sensitive)
- **Category-specific**: Uses overall confidence

---

## 🔍 Integration Points

### In `agent.ts` (Line ~423)

```typescript
// ✅ PHASE 2: Enhance query with user preferences
if (shouldEnhanceQuery && userId && userId !== "global" && userId !== "dev-user-id") {
  const category = extractCategoryFromQuery(cleanQuery, finalIntent);
  const preferenceEnhanced = await enhanceQueryWithPreferences(
    cleanQuery,
    userId,
    {
      intent: finalIntent,
      category: category,
      minConfidence: 0.3,
    }
  );
  
  if (preferenceEnhanced !== cleanQuery) {
    contextAwareQuery = preferenceEnhanced;
    queryForRefinement = preferenceEnhanced;
  }
}
```

### Order of Enhancement

1. **Phase 2** (User Preferences) - Applied first
2. **Session Memory** (Same-chat context) - Applied second (takes precedence)
3. **Query Refinement** (LLM optimization) - Applied last

This ensures:
- User preferences provide baseline personalization
- Session memory handles same-chat follow-ups
- LLM refinement optimizes for search engines

---

## 📊 Testing

### To Test Phase 2

1. **Ensure user has preferences** (run aggregation or manually create):
   ```sql
   INSERT INTO user_preferences (user_id, brand_preferences, style_keywords, confidence_score)
   VALUES ('user-id', ARRAY['Prada'], ARRAY['luxury'], 0.7);
   ```

2. **Test queries**:
   - "glasses" → Should enhance with brand/style
   - "prada glasses" → Should NOT add brand (already specified)
   - "luxury hotels in miami" → Should NOT add style (already specified)
   - "shoes" → Should enhance if confidence ≥60% and query is vague

3. **Check logs**:
   - Look for: `🎯 Phase 2: Preference-enhanced query: ...`
   - Or: `🎯 Enhanced with brand preference: ...`

---

## ⚠️ Important Notes

1. **Preferences must exist**: Phase 2 only works if `user_preferences` table has data
   - Run `aggregateUserPreferences()` to build preferences from signals
   - Or manually create preferences for testing

2. **Confidence matters**: Low confidence preferences won't be applied
   - Minimum: 30% to even consider
   - Brand: 40% (or vague query)
   - Style: 50%
   - Price: 60%

3. **Session memory takes precedence**: If user has same-chat context, that's used instead
   - Phase 2 provides baseline personalization
   - Session memory handles immediate follow-ups

4. **Non-blocking**: Enhancement failures don't break queries
   - Errors are logged but query continues normally
   - Falls back to original query if enhancement fails

---

## 🚀 Next Steps (Phase 3 & 4)

- **Phase 3**: "Of My Taste" matching with embeddings
- **Phase 4**: Background jobs for automatic aggregation

---

## ✅ Status

**Phase 2: COMPLETE** ✅

- Query enhancement implemented
- Intelligent preference application
- Integrated into agent route
- Ready for testing

