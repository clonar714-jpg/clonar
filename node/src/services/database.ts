/**
 * Minimal stub so the server can start when running query-pipeline only.
 * Exports connectDatabase (no-op) and db/supabase that throw on use.
 * Replace with a real implementation (e.g. Supabase + schema) for auth, users, collages, etc.
 */
const DB_NOT_CONFIGURED =
  'Database not configured. This stub allows the query pipeline (/api/query) to run; add a real database module for auth, users, collages, and other routes.';

function throwStub(): never {
  throw new Error(DB_NOT_CONFIGURED);
}

export async function connectDatabase(): Promise<void> {
  // no-op; server can start without a real DB
}

/** Stub: any use will throw. Replace with real Supabase client for full app. */
export const db = new Proxy(
  {} as any,
  {
    get() {
      throwStub();
    },
  }
);

/** Stub: any use will throw. Replace with real Supabase client for full app. */
export const supabase = new Proxy(
  {} as any,
  {
    get() {
      throwStub();
    },
  }
);
