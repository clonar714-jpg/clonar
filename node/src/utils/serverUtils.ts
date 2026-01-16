/**
 * Server utility functions
 */

import crypto from 'crypto';

/**
 * ✅ PERPLEXICA PATTERN: Hash an object to a deterministic SHA256 hash
 * Uses sorted keys to ensure consistent hashing regardless of property order
 * 
 * @param obj - Object to hash
 * @returns SHA256 hash as hex string
 */
export function hashObj(obj: { [key: string]: any }): string {
  const json = JSON.stringify(obj, Object.keys(obj).sort());
  const hash = crypto.createHash('sha256').update(json).digest('hex');
  return hash;
}

