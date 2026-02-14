/** Auth middleware (stub). */
import type { Request, Response, NextFunction } from 'express';
export function authMiddleware(_req: Request, _res: Response, next: NextFunction) {
  next();
}
