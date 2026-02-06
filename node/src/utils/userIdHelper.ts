/**
 * Resolve a valid user id from request (header/param). Used by chats route.
 */
export function getValidUserId(raw: string | undefined): string {
  const trimmed = typeof raw === 'string' ? raw.trim() : '';
  return trimmed || 'anonymous';
}
