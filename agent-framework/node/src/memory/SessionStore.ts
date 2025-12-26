// src/memory/SessionStore.ts

import { SessionState } from "./sessionMemory";

/**
 * SessionStore interface for abstracting session storage
 * Supports both in-memory and persistent (Redis) storage
 */
export interface SessionStore {
  /**
   * Get session state for a given session ID
   * Should refresh TTL if session exists
   * @param sessionId - Session identifier
   * @returns SessionState or null if not found/expired
   */
  get(sessionId: string): Promise<SessionState | null>;

  /**
   * Save or update session state
   * Sets TTL to default (30 minutes)
   * @param sessionId - Session identifier
   * @param state - Session state to save
   */
  set(sessionId: string, state: SessionState): Promise<void>;

  /**
   * Delete session
   * @param sessionId - Session identifier
   */
  delete(sessionId: string): Promise<void>;

  /**
   * Refresh TTL for an existing session
   * @param sessionId - Session identifier
   */
  refreshTTL(sessionId: string): Promise<void>;

  /**
   * Check if store is available/healthy
   * @returns true if store is ready to use
   */
  isAvailable(): boolean;
}

