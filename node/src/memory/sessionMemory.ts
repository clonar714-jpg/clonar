

import { SessionStore } from "./SessionStore";
import { InMemorySessionStore } from "./InMemorySessionStore";
import { RedisSessionStore } from "./RedisSessionStore";


export interface SessionState {
  domain: "shopping" | "hotel" | "restaurants" | "flights" | "location" | "general";
  brand: string | null;
  category: string | null;
  price: number | null;
  city: string | null;
  gender: "men" | "women" | null;
  intentSpecific: Record<string, any>; 
  lastQuery: string;
  lastAnswer: string;
  lastImageUrl?: string | null; 
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


export async function updateSession(sessionId: string, updates: Partial<SessionState>): Promise<void> {
  const existing = await getSession(sessionId);
  if (existing) {
    await saveSession(sessionId, { ...existing, ...updates });
  } else {
    
    await saveSession(sessionId, {
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

