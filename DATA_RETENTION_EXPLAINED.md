# 🗄️ Data Retention & Cleanup - Explained

## Do ChatGPT & Perplexity Clean Up Data?

### ChatGPT
**What They Store:**
- ✅ Conversation history (permanently, unless you delete it)
- ✅ User can delete individual conversations
- ✅ User can disable chat history
- ✅ They likely archive old data (move to cheaper storage)
- ✅ They use it for training/improvement

**Why They Can Store Permanently:**
- Massive infrastructure (billions in funding)
- Cheap storage (cloud storage is very cheap at scale)
- Data is valuable for training AI models
- Users expect their history to persist

### Perplexity
**What They Store:**
- ✅ Search history (permanently, unless you delete it)
- ✅ User can delete searches
- ✅ They likely archive old data
- ✅ They use it for personalization

**Why They Can Store Permanently:**
- Similar to ChatGPT - large infrastructure
- Storage costs are manageable at scale
- Data is valuable for improving search

---

## Why We Clean Up (Our System)

### The Problem

**Our System:**
- Smaller scale (not billions in funding)
- Database storage costs money
- Each signal stores:
  - Query text
  - Intent
  - Style keywords
  - Price mentions
  - Brand mentions
  - Rating mentions
  - Cards shown (JSON - can be large!)
  - User interaction data

**Example:**
```
1 user × 1000 searches = 1000 signals
Each signal: ~2-5 KB
Total: 2-5 MB per user

1000 users × 5 MB = 5 GB
10,000 users × 5 MB = 50 GB
100,000 users × 5 MB = 500 GB
```

**Without Cleanup:**
- Database grows forever
- Costs increase over time
- Slower queries (more data to scan)
- More expensive backups

### Why We Keep Last 100

**Reasoning:**
- Last 100 searches = Recent behavior (most relevant)
- Old searches = Less relevant (preferences change)
- 100 is enough for aggregation (we only use last 50 anyway)
- Balances: Recent data + Database size

**Math:**
```
100 signals × 3 KB average = 300 KB per user
10,000 users × 300 KB = 3 GB (manageable)
vs.
10,000 signals × 3 KB = 30 KB per user
10,000 users × 30 KB = 300 GB (expensive!)
```

---

## Comparison Table

| System | Storage Policy | Why |
|--------|---------------|-----|
| **ChatGPT** | Permanent (unless deleted) | Massive infrastructure, data valuable for training |
| **Perplexity** | Permanent (unless deleted) | Large infrastructure, data valuable for search |
| **Our System** | Keep last 100 | Smaller scale, cost-conscious, recent data is most relevant |

---

## Should We Store Permanently?

### Option 1: Keep Current (Last 100) ✅

**Pros:**
- ✅ Cost-effective
- ✅ Recent data is most relevant
- ✅ Fast queries
- ✅ Manageable database size

**Cons:**
- ❌ Lose old search history
- ❌ Can't analyze long-term trends
- ❌ Can't detect preference changes over time

### Option 2: Store Permanently (Like ChatGPT/Perplexity)

**Pros:**
- ✅ Complete history
- ✅ Can analyze long-term trends
- ✅ Can detect preference changes
- ✅ More data = better preferences

**Cons:**
- ❌ Higher storage costs
- ❌ Slower queries (more data)
- ❌ More expensive backups
- ❌ May need archival system

### Option 3: Hybrid Approach (Recommended) ⭐

**Store:**
- ✅ Last 100 signals (for active aggregation)
- ✅ Aggregated preferences (permanently - this is small)
- ✅ Archive old signals (move to cheaper storage, don't delete)

**Benefits:**
- ✅ Recent data for fast aggregation
- ✅ Preferences stored permanently (small size)
- ✅ Old signals archived (can recover if needed)
- ✅ Cost-effective

---

## What We Actually Need

### For Personalization, We Need:

1. **Recent Signals (Last 50-100)**
   - For aggregation
   - For detecting current preferences
   - ✅ We keep this

2. **Aggregated Preferences**
   - Final result of aggregation
   - Small size (~1 KB per user)
   - ✅ We store permanently

3. **Old Signals**
   - Less important for current preferences
   - Could be archived (not deleted)
   - ❌ Currently we delete

---

## Recommendation: Make It Configurable

### Current Implementation
```typescript
// Keep last 100 signals
const SIGNAL_LIMIT = 100;
```

### Better Implementation
```typescript
// Configurable limit
const SIGNAL_LIMIT = process.env.PREFERENCE_SIGNAL_LIMIT || 100;

// Or: Archive instead of delete
if (signals.length > SIGNAL_LIMIT) {
  // Archive old signals (move to archive table)
  // Don't delete - just move to cheaper storage
}
```

---

## What ChatGPT/Perplexity Actually Do

### They Likely:

1. **Store Everything Initially**
   - All conversations/searches stored

2. **Archive Old Data**
   - Move old data to cheaper storage (cold storage)
   - Keep recent data in fast storage
   - Don't delete - just archive

3. **Use for Training**
   - Old data valuable for improving AI
   - Anonymized data for model training

4. **User Control**
   - Users can delete their data
   - Users can disable history
   - But data might still be used for training (anonymized)

---

## Our Current Approach vs. Better Approach

### Current (Simple)
```
Keep: Last 100 signals
Delete: Everything older
```

### Better (Like ChatGPT/Perplexity)
```
Keep: Last 100 signals (active)
Archive: Older signals (cheaper storage)
Store: Preferences permanently (small, valuable)
```

---

## Should We Change It?

### For Now: Current Approach is Fine ✅

**Why:**
- We're smaller scale
- Recent data is most relevant
- Preferences are stored permanently (that's what matters)
- Cost-effective

### Future: Consider Archival ⭐

**When to Change:**
- If we have many users (10,000+)
- If storage costs become an issue
- If we want to analyze long-term trends
- If we want to detect preference changes

**How to Change:**
- Create `preference_signals_archive` table
- Move old signals there (don't delete)
- Keep recent signals in main table
- Query archive only when needed

---

## Summary

### Do ChatGPT/Perplexity Clean Up?

**Short Answer:** Not really - they store permanently, but likely archive old data.

**Details:**
- ✅ They store conversation/search history permanently
- ✅ Users can delete their own data
- ✅ They likely archive old data (move to cheaper storage)
- ✅ They use data for training/improvement
- ✅ They have massive infrastructure (can afford storage)

### Why We Clean Up

**Short Answer:** Cost and performance - we're smaller scale.

**Details:**
- ✅ Database storage costs money
- ✅ Recent data is most relevant anyway
- ✅ We store preferences permanently (that's what matters)
- ✅ Last 100 is enough for aggregation
- ✅ Keeps database size manageable

### Should We Change?

**For Now:** Current approach is fine ✅

**Future:** Consider archival instead of deletion ⭐

---

## Key Insight

**What Matters for Personalization:**
- ✅ **Aggregated Preferences** (stored permanently) - This is what we use!
- ✅ **Recent Signals** (last 100) - For updating preferences
- ❌ **Old Signals** (older than 100) - Less relevant, can be archived

**The Important Part:**
- We store **preferences permanently** (small, valuable)
- We only clean up **raw signals** (large, less valuable after aggregation)
- This is actually smart! We keep what matters, clean what doesn't.

**ChatGPT/Perplexity:**
- They store everything because:
  - They can afford it
  - Data is valuable for training
  - Users expect history to persist
- But they likely archive old data too (move to cheaper storage)

---

## Bottom Line

**Our cleanup is actually smart:**
- ✅ We keep what matters (preferences)
- ✅ We clean what doesn't (old raw signals)
- ✅ Cost-effective
- ✅ Recent data is most relevant anyway

**ChatGPT/Perplexity:**
- Store more because they can afford it
- But they likely archive old data too
- They use it for training (we don't need that)

**Our approach is appropriate for our scale!** 🎯

