/** Feedback controller (stub). */
import type { Request, Response } from 'express';
export function submitFeedback(_req: Request, res: Response) {
  res.status(501).json({ error: 'Not implemented' });
}
