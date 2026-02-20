import { Pool } from 'pg';
import { FeedbackPayload, Feedback } from '@/models/feedback.model';
import { logger } from '@/utils/logger';

const pool = new Pool({
  connectionString: process.env.DATABASE_URL,
});

export async function saveFeedback(payload: FeedbackPayload): Promise<Feedback> {
  const {
    sessionId, userId, query, mode,
    vertical, thumb, reason, comment, debugJson,
  } = payload;

  const result = await pool.query<Feedback>(
    `INSERT INTO feedback
      (session_id, user_id, query, mode, vertical, thumb, reason, comment, debug_json)
     VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
     RETURNING *`,
    [sessionId, userId ?? null, query, mode, vertical, thumb,
     reason ?? null, comment ?? null, debugJson ? JSON.stringify(debugJson) : null],
  );

  logger.info('Feedback saved', { id: result.rows[0].id, thumb });
  return result.rows[0];
}

export async function getFeedbackBySession(sessionId: string): Promise<Feedback[]> {
  const result = await pool.query<Feedback>(
    `SELECT * FROM feedback WHERE session_id = $1 ORDER BY created_at DESC`,
    [sessionId],
  );
  return result.rows;
}
