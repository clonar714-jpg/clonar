// ✅ PHASE 10: Enhanced Rate Limiter for API Calls

interface RateLimitEntry {
  count: number;
  resetTime: number;
}

class RateLimiter {
  private limits: Map<string, RateLimitEntry>;
  private windowMs: number;
  private maxRequests: number;

  constructor(windowMs: number = 60000, maxRequests: number = 100) {
    this.limits = new Map();
    this.windowMs = windowMs;
    this.maxRequests = maxRequests;
    
    // Clean up expired entries every minute
    setInterval(() => this.cleanup(), 60000);
  }

  /**
   * Check if request should be allowed
   * @param key - Unique identifier (IP, userId, etc.)
   * @returns true if allowed, false if rate limited
   */
  check(key: string): boolean {
    const now = Date.now();
    const entry = this.limits.get(key);

    if (!entry || now > entry.resetTime) {
      // Create new window
      this.limits.set(key, {
        count: 1,
        resetTime: now + this.windowMs,
      });
      return true;
    }

    if (entry.count >= this.maxRequests) {
      return false; // Rate limited
    }

    // Increment count
    entry.count++;
    return true;
  }

  /**
   * Get remaining requests in current window
   */
  getRemaining(key: string): number {
    const entry = this.limits.get(key);
    if (!entry || Date.now() > entry.resetTime) {
      return this.maxRequests;
    }
    return Math.max(0, this.maxRequests - entry.count);
  }

  /**
   * Get reset time for key
   */
  getResetTime(key: string): number {
    const entry = this.limits.get(key);
    return entry ? entry.resetTime : Date.now() + this.windowMs;
  }

  /**
   * Clean up expired entries
   */
  private cleanup(): void {
    const now = Date.now();
    for (const [key, entry] of this.limits.entries()) {
      if (now > entry.resetTime) {
        this.limits.delete(key);
      }
    }
  }

  /**
   * Reset limit for a key
   */
  reset(key: string): void {
    this.limits.delete(key);
  }
}

// ✅ PHASE 10: Global rate limiter (100 requests per minute per IP)
export const apiRateLimiter = new RateLimiter(60000, 100);

// ✅ PHASE 10: Agent-specific rate limiter (more restrictive)
export const agentRateLimiter = new RateLimiter(60000, 30); // 30 requests per minute

