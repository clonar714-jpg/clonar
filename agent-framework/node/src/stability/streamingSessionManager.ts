// ✅ PHASE 10: LRU for Streaming Sessions

interface StreamingSession {
  sessionId: string;
  userId?: string;
  createdAt: number;
  lastActivity: number;
  response?: any;
}

class LRUCache {
  private cache: Map<string, StreamingSession>;
  private maxSize: number;

  constructor(maxSize: number = 50) {
    this.cache = new Map();
    this.maxSize = maxSize;
  }

  get(sessionId: string): StreamingSession | undefined {
    const session = this.cache.get(sessionId);
    if (session) {
      // Update last activity (move to end)
      this.cache.delete(sessionId);
      this.cache.set(sessionId, { ...session, lastActivity: Date.now() });
      return session;
    }
    return undefined;
  }

  set(sessionId: string, session: StreamingSession): void {
    // If already exists, update
    if (this.cache.has(sessionId)) {
      this.cache.delete(sessionId);
    } else if (this.cache.size >= this.maxSize) {
      // Remove least recently used (first item)
      const firstKey = this.cache.keys().next().value;
      if (firstKey) {
        this.cache.delete(firstKey);
        console.log(`🗑️ LRU eviction: Removed session ${firstKey}`);
      }
    }
    
    this.cache.set(sessionId, {
      ...session,
      lastActivity: Date.now(),
    });
  }

  delete(sessionId: string): void {
    this.cache.delete(sessionId);
  }

  clear(): void {
    this.cache.clear();
  }

  size(): number {
    return this.cache.size;
  }

  // Clean up stale sessions (older than 1 hour)
  cleanupStale(maxAge: number = 3600000): void {
    const now = Date.now();
    const toDelete: string[] = [];
    
    for (const [sessionId, session] of this.cache.entries()) {
      if (now - session.lastActivity > maxAge) {
        toDelete.push(sessionId);
      }
    }
    
    toDelete.forEach(id => {
      this.cache.delete(id);
      console.log(`🧹 Cleaned up stale session: ${id}`);
    });
  }
}

// ✅ PHASE 10: Global streaming session manager (LRU, max 50)
export const streamingSessionManager = new LRUCache(50);

// Clean up stale sessions every 10 minutes
setInterval(() => {
  streamingSessionManager.cleanupStale();
}, 10 * 60 * 1000);

