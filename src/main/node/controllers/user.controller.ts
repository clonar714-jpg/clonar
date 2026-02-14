
import type { Request, Response } from 'express';
export function getUser(_req: Request, res: Response) {
  res.status(501).json({ error: 'Not implemented' });
}

