/**
 * ✅ Session Store: In-memory store for active APISearchAgent sessions
 * Used for reconnection support
 */

import { SessionManager } from './APISearchAgent';

class SessionStore {
  private sessions: Map<string, SessionManager> = new Map();

  /**
   * Store a session by backendId
   */
  set(backendId: string, session: SessionManager): void {
    this.sessions.set(backendId, session);
  }

  /**
   * Get a session by backendId
   */
  get(backendId: string): SessionManager | undefined {
    return this.sessions.get(backendId);
  }

  /**
   * Remove a session
   */
  delete(backendId: string): void {
    this.sessions.delete(backendId);
  }

  /**
   * Check if a session exists
   */
  has(backendId: string): boolean {
    return this.sessions.has(backendId);
  }

  /**
   * Clear all sessions
   */
  clear(): void {
    this.sessions.clear();
  }
}

// Singleton instance
export const sessionStore = new SessionStore();

