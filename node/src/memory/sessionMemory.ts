

import { SessionStore } from "./SessionStore";
import { InMemorySessionStore } from "./InMemorySessionStore";
import { RedisSessionStore } from "./RedisSessionStore";
import type {
  PlanCandidateHotelFilters,
  PlanCandidateFlightFilters,
  PlanCandidateMovieFilters,
  PlanCandidateProductFilters,
} from "@/types/core";

/** One turn in the conversation thread (Perplexity-style: use prior messages for context). */
export interface ConversationTurn {
  query: string;
  answer: string;
}

/** Max turns to keep in session (Perplexity-style thread). */
export const CONVERSATION_THREAD_MAX_TURNS = 10;

export interface SessionState {
  /** Conversation thread (last N turns) for rewrite/context like Perplexity. */
  conversationThread?: ConversationTurn[];
  /** Last-used filters (Perplexity-style): merged with extracted filters next turn. */
  lastHotelFilters?: PlanCandidateHotelFilters;
  lastFlightFilters?: PlanCandidateFlightFilters;
  lastMovieFilters?: PlanCandidateMovieFilters;
  lastProductFilters?: PlanCandidateProductFilters;
}

/** Updates for updateSession: appendTurn to add a turn to the thread; last*Filters to persist. */
export interface UpdateSessionUpdates {
  /** Current turn to append to conversationThread (replaces old lastQuery/lastAnswer). */
  appendTurn?: { query: string; answer: string };
  lastHotelFilters?: PlanCandidateHotelFilters;
  lastFlightFilters?: PlanCandidateFlightFilters;
  lastMovieFilters?: PlanCandidateMovieFilters;
  lastProductFilters?: PlanCandidateProductFilters;
}


const SESSION_TTL_MINUTES = 30;


let sessionStore: SessionStore;


async function initializeSessionStore(): Promise<SessionStore> {
  const useRedis = process.env.USE_REDIS_SESSIONS === 'true';
  
  if (useRedis) {
    console.log('🔧 Initializing RedisSessionStore...');
    const redisStore = new RedisSessionStore(SESSION_TTL_MINUTES);
    
    
    await new Promise(resolve => setTimeout(resolve, 1000));
    
    if (redisStore.isAvailable()) {
      console.log('✅ Using RedisSessionStore for persistent sessions');
      return redisStore;
    } else {
      console.warn('⚠️ RedisSessionStore unavailable, falling back to InMemorySessionStore');
    }
  }
  
  console.log('✅ Using InMemorySessionStore (default)');
  return new InMemorySessionStore(SESSION_TTL_MINUTES);
}


let storeInitialized = false;


initializeSessionStore().then(store => {
  sessionStore = store;
  storeInitialized = true;
  console.log('✅ Session store initialized');
}).catch(err => {
  console.error('❌ Failed to initialize session store:', err);
  
  sessionStore = new InMemorySessionStore(SESSION_TTL_MINUTES);
  storeInitialized = true;
});


export async function getSession(sessionId: string): Promise<SessionState | null> {
  try {
    
    if (!storeInitialized) {
      await new Promise(resolve => {
        const checkInterval = setInterval(() => {
          if (storeInitialized) {
            clearInterval(checkInterval);
            resolve(undefined);
          }
        }, 10);
        
        setTimeout(() => {
          clearInterval(checkInterval);
          resolve(undefined);
        }, 1000);
      });
    }

    const state = await sessionStore.get(sessionId);
    
    return state;
  } catch (err: any) {
    console.error(`❌ getSession error for ${sessionId}:`, err.message);
    return null;
  }
}


export async function saveSession(sessionId: string, state: SessionState): Promise<void> {
  try {
    
    if (!storeInitialized) {
      await new Promise(resolve => {
        const checkInterval = setInterval(() => {
          if (storeInitialized) {
            clearInterval(checkInterval);
            resolve(undefined);
          }
        }, 10);
        
        setTimeout(() => {
          clearInterval(checkInterval);
          resolve(undefined);
        }, 1000);
      });
    }

    await sessionStore.set(sessionId, state);
  } catch (err: any) {
    console.error(`❌ saveSession error for ${sessionId}:`, err.message);
    
    if (!sessionStore.isAvailable()) {
      console.warn('⚠️ Session store unavailable, creating fallback in-memory store');
      sessionStore = new InMemorySessionStore(SESSION_TTL_MINUTES);
      storeInitialized = true;
      await sessionStore.set(sessionId, state);
    } else {
      throw err;
    }
  }
}


export async function clearSession(sessionId: string): Promise<void> {
  try {
    await sessionStore.delete(sessionId);
  } catch (err: any) {
    console.error(`❌ clearSession error for ${sessionId}:`, err.message);
  }
}


export async function updateSession(sessionId: string, updates: UpdateSessionUpdates): Promise<void> {
  const existing = await getSession(sessionId);
  const base = existing ?? {};

  // Append current turn to conversation thread (last N turns)
  let conversationThread = existing?.conversationThread ?? [];
  const turn = updates.appendTurn;
  if (turn?.query != null && turn?.answer != null) {
    conversationThread = conversationThread
      .concat([{ query: turn.query, answer: turn.answer }])
      .slice(-CONVERSATION_THREAD_MAX_TURNS);
  }

  // Keep last filters for verticals we didn't use this turn (updates override, else keep existing)
  const lastHotelFilters = updates.lastHotelFilters ?? existing?.lastHotelFilters;
  const lastFlightFilters = updates.lastFlightFilters ?? existing?.lastFlightFilters;
  const lastMovieFilters = updates.lastMovieFilters ?? existing?.lastMovieFilters;
  const lastProductFilters = updates.lastProductFilters ?? existing?.lastProductFilters;

  await saveSession(sessionId, {
    ...base,
    conversationThread,
    ...(lastHotelFilters != null && { lastHotelFilters }),
    ...(lastFlightFilters != null && { lastFlightFilters }),
    ...(lastMovieFilters != null && { lastMovieFilters }),
    ...(lastProductFilters != null && { lastProductFilters }),
  });
}


export async function refreshSessionTTL(sessionId: string): Promise<void> {
  try {
    await sessionStore.refreshTTL(sessionId);
  } catch (err: any) {
    console.error(`❌ refreshSessionTTL error for ${sessionId}:`, err.message);
  }
}


export function getSessionStore(): SessionStore {
  return sessionStore;
}

