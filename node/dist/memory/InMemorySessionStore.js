// src/memory/InMemorySessionStore.ts
/**
 * In-memory session store (default implementation)
 * Non-persistent, lost on server restart
 */
export class InMemorySessionStore {
    constructor(ttlMinutes = 30, maxSessions = 1000) {
        this.memory = {};
        this.cleanupInterval = null;
        this.ttl = ttlMinutes * 60 * 1000; // Convert to milliseconds
        this.maxSessions = maxSessions;
        this.startCleanupInterval();
    }
    /**
     * Start periodic cleanup of expired sessions
     */
    startCleanupInterval() {
        if (typeof setInterval !== 'undefined') {
            this.cleanupInterval = setInterval(() => {
                this.cleanupExpiredSessions();
            }, 5 * 60 * 1000); // Every 5 minutes
        }
    }
    /**
     * Cleanup expired sessions and enforce max capacity
     */
    cleanupExpiredSessions() {
        const now = Date.now();
        const sessionIds = Object.keys(this.memory);
        let cleaned = 0;
        // Remove expired sessions
        for (const sessionId of sessionIds) {
            const entry = this.memory[sessionId];
            if (entry && (now - entry.timestamp) > this.ttl) {
                delete this.memory[sessionId];
                cleaned++;
            }
        }
        // If at max capacity, remove oldest sessions
        const remainingIds = Object.keys(this.memory);
        if (remainingIds.length >= this.maxSessions) {
            const sorted = remainingIds
                .map(id => ({ id, timestamp: this.memory[id]?.timestamp || 0 }))
                .sort((a, b) => a.timestamp - b.timestamp);
            // Remove oldest 20% of sessions
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
    async get(sessionId) {
        const entry = this.memory[sessionId];
        if (!entry)
            return null;
        // Check if session expired
        const now = Date.now();
        if ((now - entry.timestamp) > this.ttl) {
            delete this.memory[sessionId];
            return null;
        }
        // Refresh TTL on access
        entry.timestamp = now;
        return entry.state;
    }
    async set(sessionId, state) {
        // Cleanup before saving to prevent memory issues
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
    async delete(sessionId) {
        delete this.memory[sessionId];
        console.log(`🗑️ InMemorySessionStore: Cleared session state for ${sessionId}`);
    }
    async refreshTTL(sessionId) {
        const entry = this.memory[sessionId];
        if (entry) {
            entry.timestamp = Date.now();
        }
    }
    isAvailable() {
        return true; // In-memory store is always available
    }
    /**
     * Cleanup interval on shutdown
     */
    destroy() {
        if (this.cleanupInterval) {
            clearInterval(this.cleanupInterval);
            this.cleanupInterval = null;
        }
    }
}
