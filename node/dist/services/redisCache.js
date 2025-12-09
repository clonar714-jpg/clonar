// src/services/redisCache.ts
import Redis from 'ioredis';
// Lazy-load Redis client
let redisClient = null;
let redisEnabled = true; // Flag to track if Redis is available
/**
 * Get Redis client (lazy initialization)
 */
function getRedisClient() {
    if (!redisEnabled) {
        return null; // Redis disabled or failed
    }
    if (!redisClient) {
        try {
            const redisUrl = process.env.REDIS_URL || 'redis://localhost:6379';
            redisClient = new Redis(redisUrl, {
                maxRetriesPerRequest: 3,
                retryStrategy: (times) => {
                    const delay = Math.min(times * 50, 2000);
                    return delay;
                },
                reconnectOnError: (err) => {
                    const targetError = 'READONLY';
                    if (err.message.includes(targetError)) {
                        return true; // Reconnect on READONLY error
                    }
                    return false;
                },
                lazyConnect: true, // Don't connect immediately
            });
            redisClient.on('connect', () => {
                console.log('✅ Redis connected');
            });
            redisClient.on('ready', () => {
                console.log('✅ Redis ready');
            });
            redisClient.on('error', (err) => {
                console.error('❌ Redis error:', err.message);
                // Disable Redis on error, fallback to in-memory
                redisEnabled = false;
                redisClient = null;
            });
            // Try to connect
            redisClient.connect().catch((err) => {
                console.warn('⚠️ Redis connection failed, using in-memory cache fallback:', err.message);
                redisEnabled = false;
                redisClient = null;
            });
        }
        catch (error) {
            console.warn('⚠️ Redis initialization failed, using in-memory cache fallback:', error.message);
            redisEnabled = false;
            redisClient = null;
        }
    }
    return redisClient;
}
// Fallback in-memory cache (used when Redis is unavailable)
const fallbackCache = new Map();
/**
 * Get cached value from Redis (with in-memory fallback)
 */
export async function getCached(key) {
    const client = getRedisClient();
    if (client) {
        try {
            const cached = await client.get(key);
            if (!cached) {
                // Check fallback cache
                return getFromFallback(key);
            }
            const entry = JSON.parse(cached);
            const now = Date.now();
            // Check if expired
            if (now - entry.timestamp > entry.ttl) {
                await client.del(key); // Remove expired entry
                return getFromFallback(key);
            }
            console.log(`💾 Redis cache HIT: ${key}`);
            return entry.data;
        }
        catch (error) {
            console.error('❌ Redis get error:', error.message);
            // Fallback to in-memory
            return getFromFallback(key);
        }
    }
    // Redis not available, use fallback
    return getFromFallback(key);
}
/**
 * Get from fallback in-memory cache
 */
function getFromFallback(key) {
    const entry = fallbackCache.get(key);
    if (!entry) {
        return null;
    }
    // Check if expired
    if (Date.now() > entry.expiresAt) {
        fallbackCache.delete(key);
        return null;
    }
    console.log(`💾 Fallback cache HIT: ${key}`);
    return entry.data;
}
/**
 * Set cached value in Redis (with in-memory fallback)
 */
export async function setCached(key, data, ttlMs = 3600000 // Default 1 hour
) {
    const client = getRedisClient();
    if (client) {
        try {
            const entry = {
                data,
                timestamp: Date.now(),
                ttl: ttlMs,
            };
            // Store with Redis TTL (auto-expire)
            await client.setex(key, Math.floor(ttlMs / 1000), JSON.stringify(entry));
            console.log(`💾 Redis cache SET: ${key} (TTL: ${Math.floor(ttlMs / 1000)}s)`);
            // Also store in fallback (for redundancy)
            setInFallback(key, data, ttlMs);
            return;
        }
        catch (error) {
            console.error('❌ Redis set error:', error.message);
            // Fallback to in-memory
        }
    }
    // Redis not available, use fallback
    setInFallback(key, data, ttlMs);
}
/**
 * Set in fallback in-memory cache
 */
function setInFallback(key, data, ttlMs) {
    fallbackCache.set(key, {
        data,
        expiresAt: Date.now() + ttlMs,
    });
}
/**
 * Delete cached value
 */
export async function deleteCached(key) {
    const client = getRedisClient();
    if (client) {
        try {
            await client.del(key);
            console.log(`🗑️ Redis cache DELETE: ${key}`);
        }
        catch (error) {
            console.error('❌ Redis delete error:', error.message);
        }
    }
    // Also remove from fallback
    fallbackCache.delete(key);
}
/**
 * Clear all cache (use with caution!)
 */
export async function clearAllCache() {
    const client = getRedisClient();
    if (client) {
        try {
            await client.flushdb();
            console.log('🧹 Redis cache CLEARED');
        }
        catch (error) {
            console.error('❌ Redis clear error:', error.message);
        }
    }
    // Also clear fallback
    fallbackCache.clear();
}
/**
 * Get cache stats
 */
export async function getCacheStats() {
    const client = getRedisClient();
    let redisKeys = 0;
    let memory = 'unknown';
    if (client) {
        try {
            redisKeys = await client.dbsize();
            const info = await client.info('memory');
            const memoryMatch = info.match(/used_memory_human:(.+)/);
            memory = memoryMatch ? memoryMatch[1].trim() : 'unknown';
        }
        catch (error) {
            console.error('❌ Redis stats error:', error.message);
        }
    }
    return {
        redisEnabled: redisEnabled && client !== null,
        redisKeys,
        fallbackKeys: fallbackCache.size,
        memory,
    };
}
/**
 * Check if Redis is available
 */
export function isRedisAvailable() {
    return redisEnabled && redisClient !== null && redisClient.status === 'ready';
}
