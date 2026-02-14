
export interface Feedback {
  id?: string;
  sessionId: string;
  thumb: 'up' | 'down';
  reason?: string;
}

