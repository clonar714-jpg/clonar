/**
 * Feedback store: persists answer feedback (thumbs up/down) per session.
 * Used so the next query in the same session can see "user was not satisfied" and improve.
 * In-memory; replace with DB for production if needed.
 */

export interface FeedbackPayload {
  sessionId: string;
  userId?: string;
  query: string;
  mode: 'quick' | 'deep';
  vertical: string;
  thumb: 'up' | 'down';
  reason?: string;
  comment?: string;
  debug?: unknown;
}

export interface SourceFeedbackPayload {
  sessionId: string;
  sourceIndex: number;
  url: string;
  reason?: string;
  userId?: string;
}

/** Latest feedback per session (one entry per sessionId; overwritten on new feedback). */
const lastFeedbackBySession = new Map<string, FeedbackPayload>();

export async function storeFeedback(payload: FeedbackPayload): Promise<void> {
  lastFeedbackBySession.set(payload.sessionId, { ...payload });
}

export async function storeSourceFeedback(payload: SourceFeedbackPayload): Promise<void> {
  // optional: persist source-level feedback for future use
  void payload;
}

/**
 * Get and clear the last feedback for this session.
 * Called when handling the *next* query so we only apply "previous answer was unhelpful" once.
 */
export function getAndClearLastFeedback(sessionId: string): FeedbackPayload | undefined {
  const payload = lastFeedbackBySession.get(sessionId);
  if (payload) {
    lastFeedbackBySession.delete(sessionId);
    return payload;
  }
  return undefined;
}
