
import type { Request, Response, NextFunction } from 'express';
import { logger } from '@/utils/logger';
export function errorMiddleware(err: unknown, _req: Request, res: Response, _next: NextFunction) {
  logger.error('Unhandled error', { error: err instanceof Error ? err.message : String(err) });
  res.status(500).json({ error: 'internal_error', message: 'Internal Server Error' });
}

