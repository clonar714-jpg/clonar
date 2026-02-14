
import type { Request, Response, NextFunction } from 'express';
export function validationMiddleware(_req: Request, _res: Response, next: NextFunction) {
  next();
}

