// src/services/llmContextCache.ts
// 🚀 Cache for LLM context extraction results
// Reduces redundant LLM calls for same query pairs
import { createHash } from "crypto";
// In-memory cache with TTL
const cache = new Map();
const CACHE_TTL = 60 * 60 * 1000; // 1 hour
/**
 * Generate cache key from query pair
 */
function generateCacheKey(query, parentQuery, conversationHistory) {
    const historyHash = conversationHistory && conversationHistory.length > 0
        ? createHash('md5').update(JSON.stringify(conversationHistory.slice(-3))).digest('hex').substring(0, 8)
        : '';
    const key = `${query.toLowerCase().trim()}|${parentQuery?.toLowerCase().trim() || ''}|${historyHash}`;
    return createHash('md5').update(key).digest('hex');
}
/**
 * Get cached context extraction result
 */
export function getCachedContext(query, parentQuery, conversationHistory) {
    const key = generateCacheKey(query, parentQuery, conversationHistory);
    const cached = cache.get(key);
    if (!cached) {
        return null;
    }
    // Check if expired
    const now = Date.now();
    if (now - cached.timestamp > CACHE_TTL) {
        cache.delete(key);
        return null;
    }
    return {
        context: cached.context,
        confidence: cached.confidence,
    };
}
/**
 * Cache context extraction result
 */
export function setCachedContext(query, parentQuery, conversationHistory, context, confidence) {
    const key = generateCacheKey(query, parentQuery, conversationHistory);
    cache.set(key, {
        context,
        confidence,
        timestamp: Date.now(),
    });
}
/**
 * Clear expired cache entries (run periodically)
 */
export function cleanupCache() {
    const now = Date.now();
    let cleaned = 0;
    for (const [key, value] of cache.entries()) {
        if (now - value.timestamp > CACHE_TTL) {
            cache.delete(key);
            cleaned++;
        }
    }
    if (cleaned > 0 && process.env.NODE_ENV === 'development') {
        console.log(`🧹 LLM Context Cache: Cleaned up ${cleaned} expired entries`);
    }
}
// Cleanup cache every 30 minutes
if (typeof setInterval !== 'undefined') {
    setInterval(cleanupCache, 30 * 60 * 1000);
}
