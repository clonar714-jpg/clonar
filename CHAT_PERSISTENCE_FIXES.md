# Chat Persistence Fixes - Production-Grade Implementation

## Issues Fixed

### 1. **UUID Validation Error**
**Problem:** `"dev-user-id"` is not a valid UUID format, causing PostgreSQL errors:
```
invalid input syntax for type uuid: "dev-user-id"
```

**Solution:**
- Created `node/src/utils/userIdHelper.ts` with `getValidUserId()` function
- Converts `"dev-user-id"` to consistent UUID: `00000000-0000-0000-0000-000000000001`
- Caches mappings for consistency across restarts
- Validates UUID format before database operations

**Files Changed:**
- `node/src/utils/userIdHelper.ts` (new)
- `node/src/routes/chats.ts` (all endpoints now use `getValidUserId()`)

### 2. **Database Schema Mismatch**
**Problem:** Code tries to insert/select `query` and `image_url` columns that don't exist:
```
Could not find the 'query' column of 'conversations' in the schema cache
```

**Solution:**
- Graceful fallback: Try with optional columns first, retry without them if they don't exist
- Conditional column inclusion: Only include `query` and `image_url` if provided
- Error detection: Check for `PGRST204` error code (column not found)
- Automatic retry: Retry insert with only required columns on schema errors

**Files Changed:**
- `node/src/routes/chats.ts` (POST /api/chats, POST /api/chats/:id/messages)

### 3. **Conversation Not Found (404 Errors)**
**Problem:** Frontend tries to save messages to conversation that doesn't exist in database:
```
GET /api/chats/1765771109214 → 404
POST /api/chats/1765771109214/messages → 404
```

**Solution:**
- **Auto-create conversation** (Perplexity-style): If conversation doesn't exist when saving message, create it automatically
- **ID handling**: Supports both UUID and numeric IDs (converts numeric to UUID)
- **Idempotent**: Safe to retry, won't create duplicates
- **Fallback matching**: If auto-create fails, tries to find by title

**Files Changed:**
- `node/src/routes/chats.ts` (POST /api/chats/:id/messages)
- `lib/services/ChatHistoryServiceCloud.dart` (improved error handling)

### 4. **Frontend Error Handling**
**Problem:** Frontend logs "Saved chat to cloud" even when requests fail

**Solution:**
- Track success/failure counts for message saves
- Log actual results (e.g., "Saved 5/10 messages")
- Handle conversation ID updates (if backend returns different ID)
- Continue with remaining messages even if some fail

**Files Changed:**
- `lib/services/ChatHistoryServiceCloud.dart` (`_saveToCloud()` method)

## Production-Grade Features

### 1. **Input Validation**
- ✅ Title must be non-empty string
- ✅ Query must be non-empty string
- ✅ Conversation ID format validation
- ✅ String length limits (title: 255, query: 1000, URLs: 500)
- ✅ Type checking for all inputs

### 2. **Error Handling**
- ✅ Graceful fallbacks for schema mismatches
- ✅ Automatic retry with reduced columns
- ✅ Detailed error codes (don't expose internal errors)
- ✅ Non-blocking timestamp updates
- ✅ Continue processing on partial failures

### 3. **Idempotency**
- ✅ Auto-create conversation if missing (safe to retry)
- ✅ Consistent UUID mapping for dev mode
- ✅ Duplicate prevention via database constraints

### 4. **Performance**
- ✅ Non-blocking conversation timestamp updates
- ✅ Batch message saves (continue on individual failures)
- ✅ Timeout protection (5 seconds per request)
- ✅ Efficient queries (only select needed columns)

### 5. **Developer Experience**
- ✅ Clear error messages with codes
- ✅ Debug logging in development mode only
- ✅ Helpful hints in error responses
- ✅ Consistent behavior across endpoints

## API Changes

### POST /api/chats/:id/messages
**New Behavior:**
- Auto-creates conversation if it doesn't exist
- Returns `conversationId` in response (may differ from request ID if numeric ID was converted)
- Handles both UUID and numeric conversation IDs

**Response:**
```json
{
  "message": { ... },
  "conversationId": "actual-uuid-from-db"  // New field
}
```

### All Endpoints
**New Behavior:**
- Accept `"dev-user-id"` and convert to valid UUID automatically
- Handle missing optional columns gracefully
- Return proper error codes

## Migration Notes

### Database Schema
The code now works with **both** schema versions:
- **With optional columns**: `query`, `image_url` in `conversations` table
- **Without optional columns**: Only required columns (`id`, `user_id`, `title`, `created_at`, `updated_at`, `deleted_at`)

### Frontend
- No breaking changes
- Improved error handling
- Better logging

### Backend
- All endpoints now use `getValidUserId()` for UUID conversion
- Graceful schema handling
- Auto-creation of conversations

## Testing Checklist

- [x] Create conversation with valid UUID
- [x] Create conversation with "dev-user-id" (auto-converts)
- [x] Save message to existing conversation
- [x] Save message to non-existent conversation (auto-creates)
- [x] Handle schema without optional columns
- [x] Handle schema with optional columns
- [x] Frontend sync works with backend auto-creation
- [x] Error handling doesn't crash app
- [x] Partial message save failures don't block entire sync

## Performance Impact

- **Before**: 404 errors, failed syncs, user frustration
- **After**: Automatic recovery, graceful degradation, seamless experience

## Security

- ✅ User ID validation (prevents SQL injection via user_id)
- ✅ Input sanitization (length limits, type checks)
- ✅ Ownership verification (conversation belongs to user)
- ✅ No sensitive data in error messages

## Backward Compatibility

- ✅ All existing API calls work
- ✅ Frontend doesn't need changes (but benefits from improvements)
- ✅ Works with old and new database schemas
- ✅ Dev mode still works with "dev-user-id"

