# 🎯 Personalization System Strategy

## Overview
Implement Perplexity-style personalization that learns user preferences across chats and applies them intelligently to new queries.

---

## 🏗️ Architecture

### Components
1. **Preference Storage Layer** (Supabase)
2. **Preference Extraction Engine** (Background processing)
3. **Query Enhancement Layer** (Real-time)
4. **Embedding Matching System** (For "of my taste" queries)

---

## 📊 Database Schema

### 1. `user_preferences` Table
```sql
CREATE TABLE user_preferences (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  
  -- Style Preferences (learned from conversations)
  style_keywords TEXT[], -- ["luxury", "budget", "modern", "vintage"]
  price_range_min DECIMAL(10,2),
  price_range_max DECIMAL(10,2),
  
  -- Category-specific preferences
  category_preferences JSONB, -- {"hotels": {"rating_min": 4, "style": "luxury"}, "watches": {"brands": ["Rolex", "Omega"]}}
  
  -- Preference strength (confidence)
  confidence_score DECIMAL(3,2) DEFAULT 0.0, -- 0.0 to 1.0
  
  -- Metadata
  conversations_analyzed INT DEFAULT 0,
  last_updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
  
  UNIQUE(user_id)
);

CREATE INDEX idx_user_preferences_user_id ON user_preferences(user_id);
```

### 2. `preference_signals` Table (for incremental learning)
```sql
CREATE TABLE preference_signals (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  conversation_id UUID, -- Optional: link to conversation
  query TEXT NOT NULL,
  intent TEXT, -- "shopping", "hotels", etc.
  
  -- Extracted signals
  style_keywords TEXT[], -- ["luxury", "5-star"]
  price_mentions TEXT[], -- ["$200-$500", "expensive"]
  brand_mentions TEXT[],
  rating_mentions TEXT[], -- ["4-star", "5-star"]
  
  -- Context
  cards_shown JSONB, -- What was actually shown
  user_interaction JSONB, -- Clicks, time spent (future)
  
  created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

CREATE INDEX idx_preference_signals_user_id ON preference_signals(user_id);
CREATE INDEX idx_preference_signals_created_at ON preference_signals(created_at);
```

---

## 🔄 Data Flow

### Phase 1: Signal Collection (Real-time, non-blocking)
```
User Query → Agent Processes → Extract Signals → Store in preference_signals (async)
                                    ↓
                            Continue with normal flow
```

### Phase 2: Preference Learning (Background, periodic)
```
Every 5 conversations OR every 24 hours:
  → Aggregate preference_signals for user
  → Calculate preference scores
  → Update user_preferences table
  → Clear old preference_signals (keep last 100)
```

### Phase 3: Query Enhancement (Real-time, fast)
```
User Query → Check user_preferences → Enhance Query → Search
                ↓
         "hotels in hawaii" + {style: "luxury"} 
         → "luxury hotels in hawaii"
```

### Phase 4: "Of My Taste" Matching (On-demand)
```
User Query: "watches of my taste"
  → Retrieve user_preferences
  → Get all products
  → Calculate similarity scores (embeddings)
  → Rerank and return top matches
```

---

## 🧠 Preference Extraction Logic

### Style Keywords Detection
```typescript
const STYLE_KEYWORDS = {
  luxury: ["luxury", "premium", "high-end", "5-star", "upscale", "exclusive"],
  budget: ["budget", "affordable", "cheap", "economy", "low-cost"],
  modern: ["modern", "contemporary", "sleek", "minimalist"],
  vintage: ["vintage", "classic", "retro", "antique"],
  // ... more
};

function extractStyleKeywords(query: string, cards: any[]): string[] {
  const found = [];
  const text = (query + " " + cards.map(c => c.title).join(" ")).toLowerCase();
  
  for (const [style, keywords] of Object.entries(STYLE_KEYWORDS)) {
    if (keywords.some(kw => text.includes(kw))) {
      found.push(style);
    }
  }
  
  return found;
}
```

### Price Range Detection
```typescript
function extractPriceRange(query: string, cards: any[]): {min?: number, max?: number} {
  // Look for: "$200-$500", "under $100", "above $500", etc.
  const pricePatterns = [
    /\$(\d+)\s*-\s*\$(\d+)/,  // $200-$500
    /under\s*\$(\d+)/i,        // under $100
    /above\s*\$(\d+)/i,        // above $500
    /(\d+)\s*-\s*(\d+)\s*dollars/i, // 200-500 dollars
  ];
  
  // Extract from query and cards
  // Return {min, max}
}
```

### Brand/Category Detection
```typescript
function extractBrands(query: string, cards: any[]): string[] {
  // Known brands list
  const brands = ["Rolex", "Omega", "Nike", "Adidas", ...];
  const found = brands.filter(brand => 
    query.toLowerCase().includes(brand.toLowerCase()) ||
    cards.some(c => c.title?.toLowerCase().includes(brand.toLowerCase()))
  );
  return found;
}
```

---

## 📈 Preference Aggregation (Background Job)

### Algorithm
```typescript
async function aggregateUserPreferences(userId: string) {
  // 1. Get last 50 preference signals
  const signals = await getRecentSignals(userId, 50);
  
  // 2. Count occurrences
  const styleCounts = {};
  const priceRanges = [];
  const brandCounts = {};
  
  signals.forEach(signal => {
    // Count style keywords
    signal.style_keywords?.forEach(style => {
      styleCounts[style] = (styleCounts[style] || 0) + 1;
    });
    
    // Collect price ranges
    if (signal.price_mentions) {
      priceRanges.push(...signal.price_mentions);
    }
    
    // Count brands
    signal.brand_mentions?.forEach(brand => {
      brandCounts[brand] = (brandCounts[brand] || 0) + 1;
    });
  });
  
  // 3. Calculate confidence scores
  const totalSignals = signals.length;
  const styleConfidence = Object.entries(styleCounts)
    .filter(([_, count]) => count >= totalSignals * 0.3) // 30% threshold
    .map(([style, count]) => ({
      style,
      confidence: count / totalSignals
    }));
  
  // 4. Calculate price range (median of all mentions)
  const priceRange = calculatePriceRange(priceRanges);
  
  // 5. Top brands (appear in >20% of signals)
  const topBrands = Object.entries(brandCounts)
    .filter(([_, count]) => count >= totalSignals * 0.2)
    .map(([brand, count]) => brand)
    .slice(0, 10); // Top 10
  
  // 6. Update user_preferences
  await updateUserPreferences(userId, {
    style_keywords: styleConfidence.map(s => s.style),
    price_range_min: priceRange.min,
    price_range_max: priceRange.max,
    brand_preferences: topBrands,
    confidence_score: Math.min(totalSignals / 20, 1.0), // Cap at 1.0
    conversations_analyzed: totalSignals,
  });
}
```

---

## 🚀 Query Enhancement Strategy

### Rules
1. **Only enhance if confidence > 0.3** (30% of conversations show preference)
2. **Respect explicit user intent** (if user says "budget", don't add "luxury")
3. **Category-specific** (hotel preferences don't apply to watches)
4. **Non-intrusive** (subtle enhancement, not forced)

### Implementation
```typescript
function enhanceQueryWithPreferences(
  query: string,
  intent: string,
  userPreferences: UserPreferences
): string {
  // 1. Check if we should enhance
  if (!userPreferences || userPreferences.confidence_score < 0.3) {
    return query; // Not enough data
  }
  
  // 2. Check for explicit user intent (don't override)
  const queryLower = query.toLowerCase();
  const explicitStyles = Object.keys(STYLE_KEYWORDS).filter(style =>
    STYLE_KEYWORDS[style].some(kw => queryLower.includes(kw))
  );
  
  if (explicitStyles.length > 0) {
    return query; // User already specified
  }
  
  // 3. Get category-specific preferences
  const categoryPrefs = userPreferences.category_preferences?.[intent];
  const stylePrefs = categoryPrefs?.style || userPreferences.style_keywords;
  
  // 4. Apply most confident style preference
  if (stylePrefs && stylePrefs.length > 0) {
    const topStyle = stylePrefs[0]; // Already sorted by confidence
    return `${topStyle} ${query}`;
  }
  
  // 5. Apply price range if available
  if (categoryPrefs?.price_range) {
    // Add price filter to query
    // (implementation depends on API)
  }
  
  return query;
}
```

---

## 🎨 "Of My Taste" Query Handling

### Detection
```typescript
const OF_MY_TASTE_PATTERNS = [
  /of my taste/i,
  /of my type/i,
  /i like/i,
  /my style/i,
  /my preference/i,
  /similar to what i like/i,
];

function isOfMyTasteQuery(query: string): boolean {
  return OF_MY_TASTE_PATTERNS.some(pattern => pattern.test(query));
}
```

### Matching Algorithm
```typescript
async function findProductsOfMyTaste(
  query: string,
  userPreferences: UserPreferences,
  products: Product[]
): Promise<Product[]> {
  // 1. Create preference embedding
  const preferenceText = [
    ...userPreferences.style_keywords,
    ...(userPreferences.brand_preferences || []),
    `price range ${userPreferences.price_range_min}-${userPreferences.price_range_max}`,
  ].join(" ");
  
  const preferenceEmbedding = await createEmbedding(preferenceText);
  
  // 2. Create product embeddings (batch)
  const productEmbeddings = await Promise.all(
    products.map(p => createEmbedding(
      `${p.title} ${p.description} ${p.price} ${p.brand || ""}`
    ))
  );
  
  // 3. Calculate similarity scores
  const scores = productEmbeddings.map((emb, i) => ({
    product: products[i],
    score: cosineSimilarity(preferenceEmbedding, emb),
  }));
  
  // 4. Sort by similarity
  scores.sort((a, b) => b.score - a.score);
  
  // 5. Return top matches (score > 0.7)
  return scores
    .filter(s => s.score > 0.7)
    .map(s => s.product)
    .slice(0, 20); // Top 20
}
```

---

## ⚡ Performance Optimizations

### 1. Async Signal Storage
- Store preference signals in background (non-blocking)
- Use queue system for high traffic

### 2. Caching
- Cache user preferences in memory (Redis/local cache)
- TTL: 1 hour (refresh on update)

### 3. Batch Processing
- Aggregate preferences every 5 conversations OR 24 hours
- Not on every query (too expensive)

### 4. Embedding Caching
- Cache product embeddings (they don't change often)
- Only recalculate when products update

### 5. Lazy Loading
- Only load preferences when needed
- Don't block query processing

---

## 🛡️ Edge Cases & Safety

### 1. New Users
- No preferences → show all results (default behavior)
- Start learning after 3+ conversations

### 2. Conflicting Preferences
- User says "luxury" in one chat, "budget" in another
- Use most recent OR most frequent (configurable)

### 3. Explicit Override
- User says "budget hotels" → don't add "luxury"
- Always respect explicit user intent

### 4. Privacy
- User can clear preferences
- User can opt-out of personalization
- Don't share preferences across users

### 5. Low Confidence
- If confidence < 0.3, don't apply preferences
- Better to show all than wrong results

---

## 📋 Implementation Phases

### Phase 1: Foundation (Week 1)
- [ ] Database schema (Supabase migration)
- [ ] Basic preference signal extraction
- [ ] Store signals in background (non-blocking)
- [ ] Basic preference aggregation (manual trigger)

### Phase 2: Query Enhancement (Week 2)
- [ ] Load user preferences (cached)
- [ ] Query enhancement logic
- [ ] Integration with existing search flow
- [ ] Testing with various queries

### Phase 3: "Of My Taste" (Week 3)
- [ ] Detection of "of my taste" queries
- [ ] Embedding-based matching
- [ ] Reranking logic
- [ ] Performance optimization

### Phase 4: Background Jobs (Week 4)
- [ ] Automated preference aggregation (cron job)
- [ ] Signal cleanup (keep last 100)
- [ ] Monitoring and logging
- [ ] Error handling

---

## 🧪 Testing Strategy

### Unit Tests
- Preference extraction logic
- Query enhancement rules
- Embedding similarity calculations

### Integration Tests
- End-to-end: query → signal → preference → enhancement
- "Of my taste" flow
- Edge cases (new user, conflicting preferences)

### Performance Tests
- Signal storage (should be <10ms)
- Preference loading (should be <50ms with cache)
- Embedding matching (should be <500ms for 100 products)

---

## 📊 Monitoring

### Metrics to Track
- Preference extraction rate
- Query enhancement rate
- "Of my taste" query frequency
- User satisfaction (implicit: click-through rate)
- Performance (latency)

### Alerts
- Preference aggregation failures
- High latency in embedding matching
- Low confidence scores (might indicate issues)

---

## 🎯 Success Criteria

1. ✅ Preferences learned from 3+ conversations
2. ✅ Query enhancement applied when confidence > 0.3
3. ✅ "Of my taste" queries return relevant results
4. ✅ No performance degradation (<100ms overhead)
5. ✅ Privacy respected (user can opt-out)

---

## 🚀 Next Steps

1. Review and approve strategy
2. Create database migration
3. Implement Phase 1 (foundation)
4. Test and iterate
5. Deploy incrementally

