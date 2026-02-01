// node/src/middleware/rate-limit-query.ts — query endpoint rate limiter (Phase 4)
import rateLimit from 'express-rate-limit';

export const queryRateLimiter = rateLimit({
  windowMs: 60 * 1000, // 1 minute
  max: 60, // 60 requests per IP per minute
  standardHeaders: true,
  legacyHeaders: false,
});
