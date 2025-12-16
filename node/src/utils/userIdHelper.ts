// src/utils/userIdHelper.ts
// ✅ Production-grade user ID handling
// Ensures valid UUIDs for database compatibility

import { v4 as uuidv4 } from 'uuid';

/**
 * Get or generate a valid user ID
 * In dev mode, generates a consistent UUID for "dev-user-id"
 * In production, expects a valid UUID from auth token
 */
const DEV_USER_ID_MAP = new Map<string, string>();

/**
 * Convert dev user ID to valid UUID
 * Uses consistent mapping so same dev ID always maps to same UUID
 */
export function getValidUserId(userId: string | undefined | null): string {
  // If no userId provided, use dev mode default
  if (!userId || userId === 'dev-user-id' || userId === 'global') {
    // Generate consistent UUID for dev mode
    if (!DEV_USER_ID_MAP.has('dev-user-id')) {
      // Use a fixed UUID for dev mode (consistent across restarts)
      // Format: 00000000-0000-0000-0000-000000000001
      DEV_USER_ID_MAP.set('dev-user-id', '00000000-0000-0000-0000-000000000001');
    }
    return DEV_USER_ID_MAP.get('dev-user-id')!;
  }

  // Check if it's already a valid UUID
  const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  if (uuidRegex.test(userId)) {
    return userId;
  }

  // If not a valid UUID, generate one and cache it
  if (!DEV_USER_ID_MAP.has(userId)) {
    DEV_USER_ID_MAP.set(userId, uuidv4());
  }
  return DEV_USER_ID_MAP.get(userId)!;
}

/**
 * Check if a string is a valid UUID
 */
export function isValidUUID(str: string): boolean {
  const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  return uuidRegex.test(str);
}

