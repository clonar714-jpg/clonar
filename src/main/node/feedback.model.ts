export interface Feedback {
  id?: number;
  sessionId: string;
  userId?: string;
  query: string;
  mode: string;
  vertical: string;
  thumb: 'up' | 'down';
  reason?: string;
  comment?: string;
  debugJson?: Record<string, unknown>;
  createdAt?: Date;
}

export interface FeedbackPayload {
  sessionId: string;
  userId?: string;
  query: string;
  mode: string;
  vertical: string;
  thumb: 'up' | 'down';
  reason?: string;
  comment?: string;
  debugJson?: Record<string, unknown>;
}
