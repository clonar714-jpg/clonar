// node/src/middleware/correlation.ts — correlation ID for observability (Phase 4)
import { Request, Response, NextFunction } from 'express';
import { randomUUID } from 'crypto';

export function attachCorrelationId(
  req: Request,
  res: Response,
  next: NextFunction,
): void {
  const headerId = req.header('x-correlation-id');
  const correlationId = headerId ?? randomUUID();

  (req as Request & { correlationId?: string }).correlationId = correlationId;
  res.setHeader('x-correlation-id', correlationId);
  next();
}
