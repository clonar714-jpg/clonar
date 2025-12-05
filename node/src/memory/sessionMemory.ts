// src/memory/sessionMemory.ts

/**
 * 🧠 C9 — Behavior Memory State
 * Stores session snapshot of user's active topic
 */
export interface SessionState {
  domain: "shopping" | "hotel" | "restaurants" | "flights" | "location" | "general";
  brand: string | null;
  category: string | null;
  price: number | null;
  city: string | null;
  gender: "men" | "women" | null;
  intentSpecific: Record<string, any>; // e.g. { running: true, wideFit: true }
  lastQuery: string;
  lastAnswer: string;
}

// In-memory storage (can be replaced with Redis/database for production)
const memory: Record<string, SessionState> = {};

/**
 * Get session state for a given session ID
 */
export function getSession(sessionId: string): SessionState | null {
  return memory[sessionId] || null;
}

/**
 * Save session state
 */
export function saveSession(sessionId: string, state: SessionState): void {
  memory[sessionId] = state;
  console.log(`💾 Saved session state for ${sessionId}:`, {
    domain: state.domain,
    brand: state.brand,
    category: state.category,
    price: state.price,
  });
}

/**
 * Clear session state
 */
export function clearSession(sessionId: string): void {
  delete memory[sessionId];
  console.log(`🗑️ Cleared session state for ${sessionId}`);
}

/**
 * Update session state (merge with existing)
 */
export function updateSession(sessionId: string, updates: Partial<SessionState>): void {
  const existing = getSession(sessionId);
  if (existing) {
    saveSession(sessionId, { ...existing, ...updates });
  } else {
    // Create new session with defaults
    saveSession(sessionId, {
      domain: updates.domain || "general",
      brand: updates.brand || null,
      category: updates.category || null,
      price: updates.price || null,
      city: updates.city || null,
      gender: updates.gender || null,
      intentSpecific: updates.intentSpecific || {},
      lastQuery: updates.lastQuery || "",
      lastAnswer: updates.lastAnswer || "",
    });
  }
}

