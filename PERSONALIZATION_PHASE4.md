# 🎯 Phase 4: Background Jobs - Implementation Complete

## ✅ What's Implemented

Phase 4 automates preference aggregation using background jobs that run periodically.

### Key Features

1. **Automatic Aggregation**
   - Aggregates preferences every **5 conversations** OR every **24 hours**
   - Runs in background (non-blocking)
   - Processes all users with preference signals

2. **Conversation Tracking**
   - Tracks conversation count per user (in-memory)
   - Increments after each query that stores signals
   - Triggers aggregation when threshold reached

3. **Signal Cleanup**
   - Keeps last 100 signals per user
   - Deletes older signals automatically
   - Prevents database bloat

4. **Periodic Background Job**
   - Runs every hour
   - Processes users in batches (10 at a time)
   - Handles errors gracefully

---

## 📁 Files Created/Modified

### New Files
- `node/src/services/personalization/backgroundAggregator.ts`
  - `incrementConversationCount()`: Tracks conversations per user
  - `aggregateIfNeeded()`: Aggregates if threshold reached
  - `cleanupOldSignals()`: Removes old signals (keeps last 100)
  - `runBackgroundAggregation()`: Processes all users
  - `startBackgroundJob()`: Starts periodic scheduler

### Modified Files
- `node/src/routes/agent.ts`
  - Increments conversation count after storing signals
  - Checks if aggregation is needed (non-blocking)
- `node/src/index.ts`
  - Starts background job scheduler on server startup

---

## 🔄 How It Works

### Flow After Each Query

```
User Query → Store Preference Signal
    ↓
Increment Conversation Count
    ↓
Check if aggregation needed:
  - 5+ conversations? → Aggregate
  - 24 hours passed? → Aggregate
    ↓
If needed: Aggregate preferences (background)
```

### Background Job Flow

```
Every Hour:
    ↓
1. Get all users with preference signals
    ↓
2. For each user:
   - Check if aggregation needed
   - Aggregate if needed
   - Clean up old signals (keep last 100)
    ↓
3. Process in batches (10 users at a time)
    ↓
4. Log results
```

### Aggregation Triggers

**Trigger 1: Conversation Count**
- User has 5+ conversations since last aggregation
- Resets count after aggregation

**Trigger 2: Time-Based**
- 24 hours have passed since last aggregation
- Works even if user hasn't had 5 conversations

**Minimum Requirements:**
- User must have at least 3 signals
- Otherwise, aggregation is skipped

---

## 🧠 Intelligence Rules

### Conversation Tracking

- **In-memory**: Stored in Map (resets on server restart)
- **Increments**: After each query that stores signals
- **Resets**: After successful aggregation

### Aggregation Logic

1. **Check Thresholds**
   - Conversation count ≥ 5? → Aggregate
   - OR 24 hours passed? → Aggregate

2. **Check Signal Count**
   - Must have ≥ 3 signals
   - Otherwise skip

3. **Aggregate**
   - Use existing `aggregateUserPreferences()` function
   - Updates `user_preferences` table

4. **Cleanup**
   - Keep last 100 signals per user
   - Delete older signals

### Batch Processing

- **Batch Size**: 10 users at a time
- **Delay**: 1 second between batches
- **Parallel**: Process batch in parallel
- **Error Handling**: Uses `Promise.allSettled()` (continues on errors)

---

## 📊 Examples

### Example 1: Conversation-Based Aggregation

```
User makes 5 queries:
1. "prada glasses" → Signal stored, count = 1
2. "luxury watches" → Signal stored, count = 2
3. "under $500" → Signal stored, count = 3
4. "gucci bags" → Signal stored, count = 4
5. "designer shoes" → Signal stored, count = 5
   → Triggers aggregation!
   → Preferences updated
   → Count reset to 0
```

### Example 2: Time-Based Aggregation

```
User made 2 queries yesterday:
- Last aggregation: 24 hours ago
- Current time: Now
→ Triggers aggregation (even though only 2 conversations)
→ Preferences updated
```

### Example 3: Signal Cleanup

```
User has 150 signals:
- Keep: Last 100 (most recent)
- Delete: First 50 (oldest)
→ Cleanup runs after aggregation
```

---

## 🔍 Integration Points

### In `agent.ts` (After Signal Storage)

```typescript
// ✅ PHASE 4: Increment conversation count and check if aggregation is needed
incrementConversationCount(userId);

// Check if aggregation is needed (non-blocking)
setImmediate(async () => {
  await aggregateIfNeeded(userId);
});
```

### In `index.ts` (Server Startup)

```typescript
app.listen(PORT, '0.0.0.0', () => {
  // ... server startup logs ...
  
  // ✅ PHASE 4: Start background aggregation job
  startBackgroundJob();
});
```

### Background Job Scheduler

```typescript
// Run immediately (after 30 seconds)
setTimeout(() => {
  runBackgroundAggregation();
}, 30000);

// Then run every hour
setInterval(() => {
  runBackgroundAggregation();
}, 60 * 60 * 1000);
```

---

## ⚠️ Important Notes

1. **In-Memory Tracking**: Conversation counts reset on server restart
   - In production, consider storing in database
   - Time-based aggregation still works (checks database)

2. **Non-Blocking**: All operations are async and non-blocking
   - Doesn't slow down user queries
   - Errors don't break the flow

3. **Batch Processing**: Processes users in batches to avoid overload
   - 10 users at a time
   - 1 second delay between batches
   - Prevents overwhelming the system

4. **Error Handling**: Uses `Promise.allSettled()`
   - Continues processing even if one user fails
   - Errors are logged but don't stop the job

5. **Signal Cleanup**: Keeps last 100 signals per user
   - Prevents database bloat
   - Older signals are deleted
   - Recent signals preserved for aggregation

---

## 🧪 Testing

### To Test Phase 4

1. **Make 5 queries** (as a logged-in user):
   - Each query should store a signal
   - After 5th query, check logs for aggregation

2. **Check logs**:
   - Look for: `🔄 Phase 4: Aggregating preferences for user...`
   - Or: `✅ Phase 4: Aggregated preferences for user...`

3. **Check database**:
   ```sql
   -- Check if preferences were updated
   SELECT * FROM user_preferences WHERE user_id = 'user-id';
   
   -- Check signal count (should be ≤ 100 after cleanup)
   SELECT COUNT(*) FROM preference_signals WHERE user_id = 'user-id';
   ```

4. **Wait 24 hours** (or modify code to test):
   - Background job should run
   - Should aggregate even if < 5 conversations

5. **Check background job logs**:
   - Look for: `🔄 Phase 4: Starting background aggregation job...`
   - Should appear every hour

---

## 🚀 Configuration

### Adjustable Parameters

**In `backgroundAggregator.ts`:**

```typescript
// Conversation threshold
const CONVERSATION_THRESHOLD = 5; // Aggregate every 5 conversations

// Time threshold
const TIME_THRESHOLD_HOURS = 24; // Aggregate every 24 hours

// Signal cleanup limit
const SIGNAL_LIMIT = 100; // Keep last 100 signals

// Batch size
const BATCH_SIZE = 10; // Process 10 users at a time

// Background job interval
const JOB_INTERVAL = 60 * 60 * 1000; // 1 hour
```

---

## ✅ Status

**Phase 4: COMPLETE** ✅

- Background job system implemented
- Conversation tracking implemented
- Periodic aggregation implemented
- Signal cleanup implemented
- Integrated into agent route and server startup
- Ready for production

---

## 🎉 All Phases Complete!

**Phase 1**: ✅ Foundation (database + signal extraction)  
**Phase 2**: ✅ Query enhancement (apply preferences)  
**Phase 3**: ✅ "Of my taste" (embedding matching)  
**Phase 4**: ✅ Background jobs (automated aggregation)

The personalization system is now **fully implemented** and ready to learn user preferences automatically! 🚀

