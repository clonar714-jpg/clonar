# Session Memory Store

This module provides persistent session storage with support for both in-memory and Redis-backed storage.

## Features

- **Abstraction Layer**: `SessionStore` interface allows switching between storage backends
- **In-Memory Store**: Default implementation, fast but non-persistent
- **Redis Store**: Optional persistent storage, survives server restarts
- **Automatic TTL**: 30-minute session expiration with refresh on access
- **Graceful Fallback**: Automatically falls back to in-memory if Redis unavailable

## Configuration

### Using In-Memory Store (Default)

No configuration needed. Sessions are stored in memory and lost on server restart.

### Using Redis Store

Set environment variable:

```bash
USE_REDIS_SESSIONS=true
REDIS_URL=redis://localhost:6379  # Optional, defaults to localhost:6379
```

The system will:
1. Attempt to connect to Redis
2. If successful, use Redis for session storage
3. If Redis is unavailable, automatically fall back to in-memory store

## API

### `getSession(sessionId: string): Promise<SessionState | null>`

Get session state. Automatically refreshes TTL if session exists.

### `saveSession(sessionId: string, state: SessionState): Promise<void>`

Save or update session state. Sets TTL to 30 minutes.

### `clearSession(sessionId: string): Promise<void>`

Delete a session.

### `updateSession(sessionId: string, updates: Partial<SessionState>): Promise<void>`

Update session by merging with existing state.

### `refreshSessionTTL(sessionId: string): Promise<void>`

Explicitly refresh TTL for a session.

## Session State Structure

```typescript
interface SessionState {
  domain: "shopping" | "hotel" | "restaurants" | "flights" | "location" | "general";
  brand: string | null;
  category: string | null;
  price: number | null;
  city: string | null;
  gender: "men" | "women" | null;
  intentSpecific: Record<string, any>;
  lastQuery: string;
  lastAnswer: string;
  lastImageUrl?: string | null;
}
```

## Implementation Details

### InMemorySessionStore

- Stores sessions in a JavaScript object
- Automatic cleanup every 5 minutes
- Max 1000 sessions (evicts oldest 20% when full)
- TTL: 30 minutes

### RedisSessionStore

- Uses `ioredis` for Redis connection
- Automatic reconnection with exponential backoff
- TTL handled by Redis (30 minutes)
- Key format: `session:{sessionId}`

## Migration Notes

All session functions are now `async`. Update call sites:

```typescript
// Before
const session = getSession(sessionId);
saveSession(sessionId, state);

// After
const session = await getSession(sessionId);
await saveSession(sessionId, state);
```

## Backward Compatibility

- Function signatures remain the same (just async)
- Session state structure unchanged
- No breaking changes to request/response
- Existing code works with automatic fallback

