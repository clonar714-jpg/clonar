

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
    
    
    if (!(store instanceof InMemorySessionStore)) {
      console.log('ℹ️ Memory flush skipped (using persistent store with TTL)');
      return;
    }

    
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

export function startMemoryFlushScheduler(): void {
  
  flushStaleContexts();

  
  setInterval(() => {
    flushStaleContexts();
  }, 30 * 60 * 1000);

  console.log('✅ Memory flush scheduler started (every 30 minutes)');
}

