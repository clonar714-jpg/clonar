// node/src/services/cache.ts — Redis cache-aside for pipeline (Phase 4); optional when Redis unavailable
//
// Caching strategy:
// - Final answer: quick mode caches full PipelineResult by (mode, message, history) to avoid recomputing.
// - Plan: understandQuery result is cached by (message, history) so duplicate/retry requests reuse the plan.
// - Retrieval: per-vertical retrieval can be cached by (vertical, filters, query) in future for lower latency.
// We avoid recomputing expensive steps when inputs are unchanged; final answer cache remains the main win for quick mode.
import Redis from 'ioredis';
import { logger } from './logger';

let redis: Redis | null = null;

function redisError(err: Error): string {
  return err?.message ?? err?.toString?.() ?? 'Connection failed';
}

export async function initRedis(): Promise<void> {
  const redisUrl = process.env.REDIS_URL;
  if (!redisUrl || !redisUrl.trim()) {
    logger.info('redis:skipped', { reason: 'REDIS_URL not set' });
    return;
  }

  const client = new Redis(redisUrl, {
    maxRetriesPerRequest: 3,
    retryStrategy(times) {
      if (times > 3) return null; // stop after 3 retries
      return Math.min(times * 200, 2000);
    },
  });

  client.on('error', (err: Error) => {
    logger.warn('redis:error', { error: redisError(err) });
  });

  try {
    await client.ping();
    redis = client;
    logger.info('redis:connected');
  } catch (err) {
    logger.warn('redis:connect_failed', {
      error: err instanceof Error ? redisError(err) : String(err),
    });
    client.disconnect();
  }
}

export async function getCache<T = unknown>(key: string): Promise<T | null> {
  if (redis == null || redis.status !== 'ready') return null;
  try {
    const raw = await redis.get(key);
    if (!raw) return null;
    return JSON.parse(raw) as T;
  } catch {
    return null;
  }
}

export async function setCache(
  key: string,
  value: unknown,
  ttlSeconds: number,
): Promise<void> {
  if (redis == null || redis.status !== 'ready') return;
  try {
    await redis.set(key, JSON.stringify(value), 'EX', ttlSeconds);
  } catch (err) {
    logger.warn('redis:set_error', {
      key,
      error: err instanceof Error ? redisError(err) : String(err),
    });
  }
}
