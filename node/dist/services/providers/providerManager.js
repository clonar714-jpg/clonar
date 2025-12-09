/**
 * 🎛️ Provider Manager
 * Manages providers for all field types with automatic fallback
 * ✅ OPTIMIZED: Parallel provider calls + Caching (Perplexity-style)
 */
import { QueryOptimizer, extractFilters, applyBackendFilters } from "./baseProvider";
/**
 * Redis cache for query results (with in-memory fallback)
 */
import { getCached, setCached } from '../redisCache';
class QueryCache {
    constructor() {
        this.TTL = 3600000; // 1 hour
    }
    getKey(query, fieldType) {
        return `${fieldType}:${query.toLowerCase().trim()}`;
    }
    async get(key) {
        // ✅ Use Redis cache (with in-memory fallback)
        const cacheKey = `provider:${key}`;
        return await getCached(cacheKey);
    }
    async set(key, data) {
        // ✅ Use Redis cache (with in-memory fallback)
        const cacheKey = `provider:${key}`;
        await setCached(cacheKey, data, this.TTL);
    }
    async clear() {
        // Note: Redis clear would require pattern matching
        // For now, just log (individual keys will expire naturally)
        console.log('⚠️ QueryCache.clear() called - keys will expire naturally');
    }
}
/**
 * Provider Manager for all fields
 */
export class ProviderManager {
    constructor() {
        this.providers = new Map();
        this.cache = new QueryCache();
    }
    /**
     * Register a provider for a field type
     */
    register(provider) {
        const fieldType = provider.fieldType;
        if (!this.providers.has(fieldType)) {
            this.providers.set(fieldType, []);
        }
        this.providers.get(fieldType).push(provider);
    }
    /**
     * Search using providers with parallel calls (Perplexity-style)
     * ✅ Calls all providers simultaneously, uses first successful response
     */
    async search(query, fieldType, options) {
        const providers = this.providers.get(fieldType) || [];
        if (providers.length === 0) {
            throw new Error(`No providers registered for field type: ${fieldType}`);
        }
        // ✅ Check cache first (instant return for common queries)
        const cacheKey = this.cache.getKey(query, fieldType);
        const cached = await this.cache.get(cacheKey);
        if (cached) {
            console.log(`⚡ Cache hit for "${query}" (${cached.length} results)`);
            return cached;
        }
        // Optimize query (Perplexity-style)
        const optimizedQuery = QueryOptimizer.optimize(query, fieldType);
        console.log(`🔍 Optimized query (${fieldType}): "${query}" → "${optimizedQuery}"`);
        // Extract filters for backend filtering
        const filters = extractFilters(query, fieldType);
        // Merge filters with options
        const searchOptions = {
            ...options,
            ...filters,
            limit: options?.limit || 20,
        };
        // ✅ PARALLEL PROVIDER CALLS (Perplexity-style)
        // Call all providers simultaneously, use FIRST successful response (race condition)
        const providerPromises = providers.map(async (provider) => {
            try {
                console.log(`🔍 Calling ${provider.name} provider for ${fieldType} (parallel)...`);
                const results = await provider.search(optimizedQuery, searchOptions);
                if (results && results.length > 0) {
                    // Apply backend filters
                    const filtered = applyBackendFilters(results, filters, fieldType);
                    if (filtered.length > 0) {
                        console.log(`✅ ${provider.name} returned ${filtered.length} results (${results.length} before filtering)`);
                        return { provider: provider.name, results: filtered, success: true };
                    }
                }
                throw new Error(`No results from ${provider.name}`);
            }
            catch (error) {
                console.warn(`⚠️ ${provider.name} failed:`, error.message);
                throw error; // Re-throw to be caught by Promise.any
            }
        });
        // ✅ Use Promise.any to get FIRST successful response (fastest wins!)
        try {
            const firstSuccess = await Promise.any(providerPromises);
            const finalResults = firstSuccess.results;
            // ✅ Cache successful results
            await this.cache.set(cacheKey, finalResults);
            console.log(`⚡ Using ${firstSuccess.provider} results (fastest successful - ${finalResults.length} items)`);
            return finalResults;
        }
        catch (error) {
            // Promise.any throws if all promises reject
            console.warn(`⚠️ All parallel providers failed, trying sequential fallback...`);
        }
        // If all failed, try sequential fallback (for debugging)
        console.warn(`⚠️ All parallel providers failed, trying sequential fallback...`);
        for (const provider of providers) {
            try {
                const results = await provider.search(optimizedQuery, searchOptions);
                if (results && results.length > 0) {
                    const filtered = applyBackendFilters(results, filters, fieldType);
                    if (filtered.length > 0) {
                        await this.cache.set(cacheKey, filtered);
                        return filtered;
                    }
                }
            }
            catch (error) {
                console.warn(`⚠️ ${provider.name} sequential fallback failed:`, error.message);
            }
        }
        throw new Error(`All providers failed for field type: ${fieldType}`);
    }
    /**
     * Get all registered providers for a field type
     */
    getProviders(fieldType) {
        return this.providers.get(fieldType) || [];
    }
}
// Global provider manager instance
export const providerManager = new ProviderManager();
