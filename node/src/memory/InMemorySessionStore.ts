

import { SessionStore } from "./SessionStore";
import { SessionState } from "./sessionMemory";

interface SessionEntry {
  state: SessionState;
  timestamp: number;
}


export class InMemorySessionStore implements SessionStore {
  private memory: Record<string, SessionEntry> = {};
  private readonly ttl: number;
  private readonly maxSessions: number;
  private cleanupInterval: NodeJS.Timeout | null = null;

  constructor(ttlMinutes: number = 30, maxSessions: number = 1000) {
    this.ttl = ttlMinutes * 60 * 1000; // Convert to milliseconds
    this.maxSessions = maxSessions;
    this.startCleanupInterval();
  }

  
  private startCleanupInterval(): void {
    if (typeof setInterval !== 'undefined') {
      this.cleanupInterval = setInterval(() => {
        this.cleanupExpiredSessions();
      }, 5 * 60 * 1000); 
    }
  }

  
  private cleanupExpiredSessions(): void {
    const now = Date.now();
    const sessionIds = Object.keys(this.memory);
    let cleaned = 0;

    
    for (const sessionId of sessionIds) {
      const entry = this.memory[sessionId];
      if (entry && (now - entry.timestamp) > this.ttl) {
        delete this.memory[sessionId];
        cleaned++;
      }
    }

    
    const remainingIds = Object.keys(this.memory);
    if (remainingIds.length >= this.maxSessions) {
      const sorted = remainingIds
        .map(id => ({ id, timestamp: this.memory[id]?.timestamp || 0 }))
        .sort((a, b) => a.timestamp - b.timestamp);

      
      const toRemove = Math.floor(sorted.length * 0.2);
      for (let i = 0; i < toRemove; i++) {
        delete this.memory[sorted[i].id];
        cleaned++;
      }
    }

    if (cleaned > 0) {
      console.log(`🧹 InMemorySessionStore: Cleaned up ${cleaned} expired/old sessions`);
    }
  }

  async get(sessionId: string): Promise<SessionState | null> {
    const entry = this.memory[sessionId];
    if (!entry) return null;

    
    const now = Date.now();
    if ((now - entry.timestamp) > this.ttl) {
      delete this.memory[sessionId];
      return null;
    }

    
    entry.timestamp = now;
    return entry.state;
  }

  async set(sessionId: string, state: SessionState): Promise<void> {
    
    this.cleanupExpiredSessions();

    this.memory[sessionId] = {
      state,
      timestamp: Date.now(),
    };

    console.log(`💾 InMemorySessionStore: Saved session state for ${sessionId}:`, {
      domain: state.domain,
      brand: state.brand,
      category: state.category,
      price: state.price,
    });
  }

  async delete(sessionId: string): Promise<void> {
    delete this.memory[sessionId];
    console.log(`🗑️ InMemorySessionStore: Cleared session state for ${sessionId}`);
  }

  async refreshTTL(sessionId: string): Promise<void> {
    const entry = this.memory[sessionId];
    if (entry) {
      entry.timestamp = Date.now();
    }
  }

  isAvailable(): boolean {
    return true; 
  }

  
  destroy(): void {
    if (this.cleanupInterval) {
      clearInterval(this.cleanupInterval);
      this.cleanupInterval = null;
    }
  }
}

