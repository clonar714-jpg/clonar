

import { SessionManager } from './APISearchAgent';

class SessionStore {
  private sessions: Map<string, SessionManager> = new Map();

 
  set(backendId: string, session: SessionManager): void {
    this.sessions.set(backendId, session);
  }

 
  get(backendId: string): SessionManager | undefined {
    return this.sessions.get(backendId);
  }

  
  delete(backendId: string): void {
    this.sessions.delete(backendId);
  }

 
  has(backendId: string): boolean {
    return this.sessions.has(backendId);
  }

  
  clear(): void {
    this.sessions.clear();
  }
}


export const sessionStore = new SessionStore();

