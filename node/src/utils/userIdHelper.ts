

import { v4 as uuidv4 } from 'uuid';


const DEV_USER_ID_MAP = new Map<string, string>();


export function getValidUserId(userId: string | undefined | null): string {
  
  if (!userId || userId === 'dev-user-id' || userId === 'global') {
    
    if (!DEV_USER_ID_MAP.has('dev-user-id')) {
      
      DEV_USER_ID_MAP.set('dev-user-id', '00000000-0000-0000-0000-000000000001');
    }
    return DEV_USER_ID_MAP.get('dev-user-id')!;
  }

  
  const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  if (uuidRegex.test(userId)) {
    return userId;
  }

  
  if (!DEV_USER_ID_MAP.has(userId)) {
    DEV_USER_ID_MAP.set(userId, uuidv4());
  }
  return DEV_USER_ID_MAP.get(userId)!;
}


export function isValidUUID(str: string): boolean {
  const uuidRegex = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
  return uuidRegex.test(str);
}

