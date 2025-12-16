// src/services/llmContextCache.ts
// 🚀 Cache for LLM context extraction results
// Reduces redundant LLM calls for same query pairs

import { ExtractedContext } from "./llmContextExtractor";
import { createHash } from "crypto";

interface CachedResult {
  context: ExtractedContext;
  confidence: number;
  timestamp: number;
}

// In-memory cache with TTL
const cache = new Map<string, CachedResult>();
const CACHE_TTL = 60 * 60 * 1000; // 1 hour

/**
 * Generate cache key from query pair
 */
function generateCacheKey(query: string, parentQuery?: string | null, conversationHistory?: any[]): string {
  const historyHash = conversationHistory && conversationHistory.length > 0
    ? createHash('md5').update(JSON.stringify(conversationHistory.slice(-3))).digest('hex').substring(0, 8)
    : '';
  
  const key = `${query.toLowerCase().trim()}|${parentQuery?.toLowerCase().trim() || ''}|${historyHash}`;
  return createHash('md5').update(key).digest('hex');
}

/**
 * Get cached context extraction result
 */
export function getCachedContext(
  query: string,
  parentQuery?: string | null,
  conversationHistory?: any[]
): { context: ExtractedContext; confidence: number } | null {
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
export function setCachedContext(
  query: string,
  parentQuery: string | null | undefined,
  conversationHistory: any[] | undefined,
  context: ExtractedContext,
  confidence: number
): void {
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
export function cleanupCache(): void {
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

