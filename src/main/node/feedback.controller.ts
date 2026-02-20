import type { Request, Response } from 'express';
import { z } from 'zod';
import { saveFeedback, getFeedbackBySession } from '@/services/feedback.service';
import { logger } from '@/utils/logger';

const FeedbackSchema = z.object({
  sessionId: z.string().min(1),
  userId:    z.string().optional(),
  query:     z.string().min(1),
  mode:      z.string().min(1),
  vertical:  z.string().min(1),
  thumb:     z.enum(['up', 'down']),
  reason:    z.string().optional(),
  comment:   z.string().max(1000).optional(),
  debugJson: z.record(z.unknown()).optional(),
});

// POST /api/feedback
export async function submitFeedback(req: Request, res: Response): Promise<void> {
  const parsed = FeedbackSchema.safeParse(req.body);

  if (!parsed.success) {
    res.status(400).json({
      error: 'Invalid request body',
      details: parsed.error.flatten().fieldErrors,
    });
    return;
  }

  try {
    const saved = await saveFeedback(parsed.data);
    res.status(201).json({ ok: true, id: saved.id });
  } catch (err) {
    logger.error('Failed to save feedback', { error: err });
    res.status(500).json({ error: 'Failed to save feedback' });
  }
}

// GET /api/feedback/:sessionId
export async function getFeedback(req: Request, res: Response): Promise<void> {
  const { sessionId } = req.params;

  if (!sessionId) {
    res.status(400).json({ error: 'sessionId is required' });
    return;
  }

  try {
    const items = await getFeedbackBySession(sessionId);
    res.status(200).json({ ok: true, data: items });
  } catch (err) {
    logger.error('Failed to fetch feedback', { error: err });
    res.status(500).json({ error: 'Failed to fetch feedback' });
  }
}
