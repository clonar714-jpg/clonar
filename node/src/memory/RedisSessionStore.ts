// src/memory/RedisSessionStore.ts

import Redis from 'ioredis';
import { SessionStore } from "./SessionStore";
import { SessionState } from "./sessionMemory";

/**
 * Redis-backed session store
 * Persistent across server restarts, supports scaling
 */
export class RedisSessionStore implements SessionStore {
  private client: Redis | null = null;
  private isConnected: boolean = false;
  private readonly ttl: number;
  private readonly keyPrefix: string = 'session:';

  constructor(ttlMinutes: number = 30, redisUrl?: string) {
    this.ttl = ttlMinutes * 60; // Redis TTL is in seconds
    this.initializeRedis(redisUrl);
  }

  /**
   * Initialize Redis client with graceful fallback
   */
  private async initializeRedis(redisUrl?: string): Promise<void> {
    try {
      const url = redisUrl || process.env.REDIS_URL || 'redis://localhost:6379';
      this.client = new Redis(url, {
        retryStrategy: (times) => {
          // Exponential backoff, max 30 seconds
          const delay = Math.min(times * 50, 30000);
          return delay;
        },
        maxRetriesPerRequest: 3,
        enableReadyCheck: true,
        lazyConnect: true,
      });

      this.client.on('error', (err) => {
        console.error('❌ RedisSessionStore error:', err.message);
        this.isConnected = false;
      });

      this.client.on('connect', () => {
        console.log('✅ RedisSessionStore: Connected to Redis');
        this.isConnected = true;
      });

      this.client.on('ready', () => {
        console.log('✅ RedisSessionStore: Ready to accept commands');
        this.isConnected = true;
      });

      this.client.on('close', () => {
        console.log('⚠️ RedisSessionStore: Connection closed');
        this.isConnected = false;
      });

      // Attempt connection
      await this.client.connect();
    } catch (err: any) {
      console.warn('⚠️ RedisSessionStore: Failed to connect, will fall back to in-memory store:', err.message);
      this.isConnected = false;
      this.client = null;
    }
  }

  private getKey(sessionId: string): string {
    return `${this.keyPrefix}${sessionId}`;
  }

  async get(sessionId: string): Promise<SessionState | null> {
    if (!this.isAvailable()) {
      return null;
    }

    try {
      const key = this.getKey(sessionId);
      const data = await this.client!.get(key);
      
      if (!data) {
        return null;
      }

      // Refresh TTL on access
      await this.refreshTTL(sessionId);

      const state = JSON.parse(data) as SessionState;
      return state;
    } catch (err: any) {
      console.error(`❌ RedisSessionStore.get error for ${sessionId}:`, err.message);
      return null;
    }
  }

  async set(sessionId: string, state: SessionState): Promise<void> {
    if (!this.isAvailable()) {
      throw new Error('RedisSessionStore: Redis not available');
    }

    try {
      const key = this.getKey(sessionId);
      const data = JSON.stringify(state);
      
      // Set with TTL
      await this.client!.setex(key, this.ttl, data);

      console.log(`💾 RedisSessionStore: Saved session state for ${sessionId}:`, {
        domain: state.domain,
        brand: state.brand,
        category: state.category,
        price: state.price,
      });
    } catch (err: any) {
      console.error(`❌ RedisSessionStore.set error for ${sessionId}:`, err.message);
      throw err;
    }
  }

  async delete(sessionId: string): Promise<void> {
    if (!this.isAvailable()) {
      return; // Silently fail if Redis unavailable
    }

    try {
      const key = this.getKey(sessionId);
      await this.client!.del(key);
      console.log(`🗑️ RedisSessionStore: Cleared session state for ${sessionId}`);
    } catch (err: any) {
      console.error(`❌ RedisSessionStore.delete error for ${sessionId}:`, err.message);
    }
  }

  async refreshTTL(sessionId: string): Promise<void> {
    if (!this.isAvailable()) {
      return;
    }

    try {
      const key = this.getKey(sessionId);
      await this.client!.expire(key, this.ttl);
    } catch (err: any) {
      console.error(`❌ RedisSessionStore.refreshTTL error for ${sessionId}:`, err.message);
    }
  }

  isAvailable(): boolean {
    return this.isConnected && this.client !== null;
  }

  /**
   * Gracefully close Redis connection
   */
  async destroy(): Promise<void> {
    if (this.client) {
      await this.client.quit();
      this.client = null;
      this.isConnected = false;
    }
  }
}

