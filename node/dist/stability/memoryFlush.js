// ✅ PHASE 10: Memory Flush Logic for Stale Contexts
import { clearSession, getAllSessions } from '../memory/sessionMemory';
/**
 * Flush stale session contexts
 * @param maxAge - Maximum age in milliseconds (default: 1 hour)
 */
export function flushStaleContexts(maxAge = 3600000) {
    try {
        const now = Date.now();
        const sessions = getAllSessions();
        let flushedCount = 0;
        for (const [sessionId, session] of Object.entries(sessions)) {
            // Check if session is stale (no activity for maxAge)
            const lastActivity = session.lastActivity || session.timestamp || 0;
            const age = now - lastActivity;
            if (age > maxAge) {
                clearSession(sessionId);
                flushedCount++;
            }
        }
        if (flushedCount > 0) {
            console.log(`🧹 Flushed ${flushedCount} stale session contexts (older than ${maxAge / 1000 / 60} minutes)`);
        }
    }
    catch (error) {
        console.error('❌ Error flushing stale contexts:', error);
    }
}
/**
 * Start periodic memory flush (every 30 minutes)
 */
export function startMemoryFlushScheduler() {
    // Flush immediately on start
    flushStaleContexts();
    // Then flush every 30 minutes
    setInterval(() => {
        flushStaleContexts();
    }, 30 * 60 * 1000);
    console.log('✅ Memory flush scheduler started (every 30 minutes)');
}
