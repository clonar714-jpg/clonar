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
  lastImageUrl?: string | null; // ✅ Track last image URL to detect changes
}

interface SessionEntry {
  state: SessionState;
  timestamp: number;
}

// ✅ FIX: In-memory storage with TTL to prevent unbounded growth
const memory: Record<string, SessionEntry> = {};

// ✅ FIX: Session TTL - 30 minutes of inactivity
const SESSION_TTL = 30 * 60 * 1000; // 30 minutes
const MAX_SESSIONS = 1000; // Maximum number of sessions to prevent memory issues

/**
 * ✅ FIX: Cleanup expired sessions
 */
function cleanupExpiredSessions(): void {
  const now = Date.now();
  const sessionIds = Object.keys(memory);
  let cleaned = 0;
  
  for (const sessionId of sessionIds) {
    const entry = memory[sessionId];
    if (entry && (now - entry.timestamp) > SESSION_TTL) {
      delete memory[sessionId];
      cleaned++;
    }
  }
  
  // ✅ FIX: If we're at max capacity, remove oldest sessions
  if (sessionIds.length >= MAX_SESSIONS) {
    const sorted = sessionIds
      .map(id => ({ id, timestamp: memory[id]?.timestamp || 0 }))
      .sort((a, b) => a.timestamp - b.timestamp);
    
    // Remove oldest 20% of sessions
    const toRemove = Math.floor(sorted.length * 0.2);
    for (let i = 0; i < toRemove; i++) {
      delete memory[sorted[i].id];
      cleaned++;
    }
  }
  
  if (cleaned > 0) {
    console.log(`🧹 Cleaned up ${cleaned} expired/old sessions`);
  }
}

// ✅ FIX: Run cleanup every 5 minutes
if (typeof setInterval !== 'undefined') {
  setInterval(cleanupExpiredSessions, 5 * 60 * 1000); // Every 5 minutes
}

/**
 * Get session state for a given session ID
 */
export function getSession(sessionId: string): SessionState | null {
  const entry = memory[sessionId];
  if (!entry) return null;
  
  // ✅ FIX: Check if session expired
  const now = Date.now();
  if ((now - entry.timestamp) > SESSION_TTL) {
    delete memory[sessionId];
    return null;
  }
  
  // Update timestamp on access (refresh TTL)
  entry.timestamp = now;
  return entry.state;
}

/**
 * Save session state
 */
export function saveSession(sessionId: string, state: SessionState): void {
  // ✅ FIX: Cleanup before saving to prevent memory issues
  cleanupExpiredSessions();
  
  memory[sessionId] = {
    state,
    timestamp: Date.now(),
  };
  
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

