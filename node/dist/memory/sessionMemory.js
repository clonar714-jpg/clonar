// src/memory/sessionMemory.ts
import { InMemorySessionStore } from "./InMemorySessionStore";
import { RedisSessionStore } from "./RedisSessionStore";
// ✅ Session TTL - 30 minutes of inactivity
const SESSION_TTL_MINUTES = 30;
// ✅ Initialize session store with graceful fallback
let sessionStore;
/**
 * Initialize session store based on environment
 * Falls back to in-memory if Redis is unavailable
 */
async function initializeSessionStore() {
    const useRedis = process.env.USE_REDIS_SESSIONS === 'true';
    if (useRedis) {
        console.log('🔧 Initializing RedisSessionStore...');
        const redisStore = new RedisSessionStore(SESSION_TTL_MINUTES);
        // Wait a bit for connection, then check availability
        await new Promise(resolve => setTimeout(resolve, 1000));
        if (redisStore.isAvailable()) {
            console.log('✅ Using RedisSessionStore for persistent sessions');
            return redisStore;
        }
        else {
            console.warn('⚠️ RedisSessionStore unavailable, falling back to InMemorySessionStore');
        }
    }
    console.log('✅ Using InMemorySessionStore (default)');
    return new InMemorySessionStore(SESSION_TTL_MINUTES);
}
// Initialize store on module load (use top-level await)
let storeInitialized = false;
// Initialize store asynchronously
initializeSessionStore().then(store => {
    sessionStore = store;
    storeInitialized = true;
    console.log('✅ Session store initialized');
}).catch(err => {
    console.error('❌ Failed to initialize session store:', err);
    // Fallback to in-memory store
    sessionStore = new InMemorySessionStore(SESSION_TTL_MINUTES);
    storeInitialized = true;
});
/**
 * Get session state for a given session ID
 * Automatically refreshes TTL if session exists
 */
export async function getSession(sessionId) {
    try {
        // Wait for store initialization if needed
        if (!storeInitialized) {
            await new Promise(resolve => {
                const checkInterval = setInterval(() => {
                    if (storeInitialized) {
                        clearInterval(checkInterval);
                        resolve(undefined);
                    }
                }, 10);
                // Timeout after 1 second
                setTimeout(() => {
                    clearInterval(checkInterval);
                    resolve(undefined);
                }, 1000);
            });
        }
        const state = await sessionStore.get(sessionId);
        // TTL is automatically refreshed in the store's get() method
        return state;
    }
    catch (err) {
        console.error(`❌ getSession error for ${sessionId}:`, err.message);
        return null;
    }
}
/**
 * Save session state
 * Sets TTL to 30 minutes
 */
export async function saveSession(sessionId, state) {
    try {
        // Wait for store initialization if needed
        if (!storeInitialized) {
            await new Promise(resolve => {
                const checkInterval = setInterval(() => {
                    if (storeInitialized) {
                        clearInterval(checkInterval);
                        resolve(undefined);
                    }
                }, 10);
                // Timeout after 1 second
                setTimeout(() => {
                    clearInterval(checkInterval);
                    resolve(undefined);
                }, 1000);
            });
        }
        await sessionStore.set(sessionId, state);
    }
    catch (err) {
        console.error(`❌ saveSession error for ${sessionId}:`, err.message);
        // If Redis fails, fall back to in-memory store
        if (!sessionStore.isAvailable()) {
            console.warn('⚠️ Session store unavailable, creating fallback in-memory store');
            sessionStore = new InMemorySessionStore(SESSION_TTL_MINUTES);
            storeInitialized = true;
            await sessionStore.set(sessionId, state);
        }
        else {
            throw err;
        }
    }
}
/**
 * Clear session state
 */
export async function clearSession(sessionId) {
    try {
        await sessionStore.delete(sessionId);
    }
    catch (err) {
        console.error(`❌ clearSession error for ${sessionId}:`, err.message);
    }
}
/**
 * Update session state (merge with existing)
 */
export async function updateSession(sessionId, updates) {
    const existing = await getSession(sessionId);
    if (existing) {
        await saveSession(sessionId, { ...existing, ...updates });
    }
    else {
        // Create new session with defaults
        await saveSession(sessionId, {
            domain: updates.domain || "general",
            brand: updates.brand || null,
            category: updates.category || null,
            price: updates.price || null,
            city: updates.city || null,
            gender: updates.gender || null,
            intentSpecific: updates.intentSpecific || {},
            lastQuery: updates.lastQuery || "",
            lastAnswer: updates.lastAnswer || "",
        });
    }
}
/**
 * Refresh TTL for a session (useful for explicit refresh)
 */
export async function refreshSessionTTL(sessionId) {
    try {
        await sessionStore.refreshTTL(sessionId);
    }
    catch (err) {
        console.error(`❌ refreshSessionTTL error for ${sessionId}:`, err.message);
    }
}
/**
 * Get the current session store instance (for testing/debugging)
 */
export function getSessionStore() {
    return sessionStore;
}
