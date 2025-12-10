# 🎯 Personalization System - Phase 1 Implementation

## ✅ Completed (Phase 1: Foundation)

### 1. Database Schema
- **File**: `supabase_migrations/003_create_personalization_tables.sql`
- **Tables Created**:
  - `user_preferences`: Aggregated user preferences with confidence scores
  - `preference_signals`: Raw signals from each conversation for learning
- **Features**:
  - Row Level Security (RLS) policies
  - Automatic timestamp updates
  - Indexes for performance
  - Cleanup function for old signals

### 2. Preference Extraction Service
- **File**: `node/src/services/personalization/preferenceExtractor.ts`
- **Functions**:
  - `extractStyleKeywords()`: Detects luxury, budget, modern, vintage, etc.
  - `extractPriceRange()`: Extracts price ranges from queries and cards
  - `extractBrands()`: Identifies brand mentions
  - `extractRatings()`: Extracts rating mentions (4-star, 5-star, etc.)
  - `extractPreferenceSignals()`: Main function that combines all extractions

### 3. Preference Storage Service
- **File**: `node/src/services/personalization/preferenceStorage.ts`
- **Functions**:
  - `storePreferenceSignal()`: Stores signals (non-blocking, async)
  - `getUserPreferences()`: Retrieves user preferences
  - `updateUserPreferences()`: Updates or creates preferences
  - `getRecentSignals()`: Gets recent signals for aggregation

### 4. Preference Aggregator Service
- **File**: `node/src/services/personalization/preferenceAggregator.ts`
- **Functions**:
  - `aggregateUserPreferences()`: Aggregates signals into preferences
  - Calculates confidence scores (30% threshold)
  - Builds category-specific preferences
  - Handles price ranges, brands, styles

### 5. Integration with Agent Route
- **File**: `node/src/routes/agent.ts`
- **Changes**:
  - Added preference signal extraction after results are fetched
  - Stores signals in background (non-blocking, using `setImmediate`)
  - Only stores for valid user IDs (not "global" or "dev-user-id")
  - Silent failure (doesn't block response if storage fails)

### 6. Database Service Update
- **File**: `node/src/services/database.ts`
- **Added**:
  - `userPreferences()`: Access to user_preferences table
  - `preferenceSignals()`: Access to preference_signals table

---

## 🚀 How It Works

### Signal Collection Flow
```
User Query → Agent Processes → Results Fetched
                ↓
        Extract Preference Signals
        (style, price, brands, ratings)
                ↓
        Store in preference_signals (async, non-blocking)
                ↓
        Continue with normal response
```

### Learning Flow (Manual Trigger for Now)
```
1. Collect signals from preference_signals table
2. Count occurrences (style keywords, brands, prices)
3. Calculate confidence scores (30% threshold)
4. Aggregate into user_preferences
5. Update user profile
```

---

## 📊 Current Status

### ✅ Working Now
- Preference signals are being collected from every query
- Signals stored in database (non-blocking)
- Extraction logic detects: styles, prices, brands, ratings
- Database schema ready for preferences

### ⏳ Next Steps (Phase 2)
1. **Query Enhancement**: Use preferences to enhance queries
2. **Preference Loading**: Load user preferences before searching
3. **Context Application**: Apply preferences to new queries

### ⏳ Future (Phase 3 & 4)
1. **"Of My Taste" Detection**: Detect phrases like "of my taste"
2. **Embedding Matching**: Use embeddings to match products to preferences
3. **Background Jobs**: Automated aggregation every 5 conversations or 24 hours

---

## 🧪 Testing

### To Test Signal Collection
1. Run a few queries with style keywords (e.g., "luxury hotels in miami")
2. Check `preference_signals` table in Supabase
3. Verify signals are being stored

### To Test Aggregation (Manual)
```typescript
import { aggregateUserPreferences } from "./services/personalization/preferenceAggregator";

// Run this manually for a user
await aggregateUserPreferences("user-id-here");
```

### To Check User Preferences
```typescript
import { getUserPreferences } from "./services/personalization/preferenceStorage";

const prefs = await getUserPreferences("user-id-here");
console.log(prefs);
```

---

## 🔧 Configuration

### Style Keywords
Edit `STYLE_KEYWORDS` in `preferenceExtractor.ts` to add more styles.

### Confidence Threshold
Currently set to 30% (appears in 30% of conversations).
Edit `aggregateUserPreferences()` to change threshold.

### Signal Limit
Currently stores last 50 signals per user.
Edit `getRecentSignals()` limit parameter.

---

## 📝 Notes

- **Non-blocking**: Signal storage doesn't slow down responses
- **Privacy**: Only stores for logged-in users (not "global" or "dev-user-id")
- **Silent failures**: Storage errors don't break the app
- **Incremental**: Preferences build up over time (needs 3+ conversations)

---

## 🚀 Next Implementation

Ready to implement Phase 2 (Query Enhancement) when you're ready!

