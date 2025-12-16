// ✅ PHASE 10: Memory Flush Logic for Stale Contexts

import { getSessionStore } from '../memory/sessionMemory';
import { InMemorySessionStore } from '../memory/InMemorySessionStore';

/**
 * Flush stale session contexts
 * Note: This only works with InMemorySessionStore
 * Redis sessions are automatically expired via TTL
 * @param maxAge - Maximum age in milliseconds (default: 1 hour)
 */
export async function flushStaleContexts(maxAge: number = 3600000): Promise<void> {
  try {
    const store = getSessionStore();
    
    // Only flush in-memory stores (Redis handles TTL automatically)
    if (!(store instanceof InMemorySessionStore)) {
      console.log('ℹ️ Memory flush skipped (using persistent store with TTL)');
      return;
    }

    // Access private memory for cleanup (this is a workaround for in-memory store)
    // In production, consider adding a cleanup method to SessionStore interface
    const now = Date.now();
    const memory = (store as any).memory as Record<string, { state: any; timestamp: number }>;
    let flushedCount = 0;

    for (const [sessionId, entry] of Object.entries(memory)) {
      const age = now - entry.timestamp;
      if (age > maxAge) {
        await store.delete(sessionId);
        flushedCount++;
      }
    }

    if (flushedCount > 0) {
      console.log(`🧹 Flushed ${flushedCount} stale session contexts (older than ${maxAge / 1000 / 60} minutes)`);
    }
  } catch (error) {
    console.error('❌ Error flushing stale contexts:', error);
  }
}

/**
 * Start periodic memory flush (every 30 minutes)
 */
export function startMemoryFlushScheduler(): void {
  // Flush immediately on start
  flushStaleContexts();

  // Then flush every 30 minutes
  setInterval(() => {
    flushStaleContexts();
  }, 30 * 60 * 1000);

  console.log('✅ Memory flush scheduler started (every 30 minutes)');
}

