/**
 * Stub feedback store so /api/feedback routes work.
 * Replace with a durable store (DB, file, etc.) for production.
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

export async function storeFeedback(payload: FeedbackPayload): Promise<void> {
  // no-op stub
  void payload;
}

export async function storeSourceFeedback(payload: SourceFeedbackPayload): Promise<void> {
  // no-op stub
  void payload;
}
