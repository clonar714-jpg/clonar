/**
 * ✅ Intent Stage Inference: Determine user's current intent stage
 */

export type IntentStage = 'explore' | 'compare' | 'narrow' | 'act';

/**
 * Infer user's intent stage from query and follow-up history
 */
export function inferIntentStage(query: string, recentFollowups: string[]): IntentStage {
  const lower = query.toLowerCase();
  
  // Act stage: User wants to take action
  if (/buy|purchase|order|book|reserve|get|where to buy/i.test(lower)) {
    return 'act';
  }
  
  // Compare stage: User wants to compare
  if (/compare|vs|versus|difference|better|which one/i.test(lower)) {
    return 'compare';
  }
  
  // Narrow stage: User wants to filter/narrow down
  if (/under|below|less than|only|specifically|filter|narrow/i.test(lower)) {
    return 'narrow';
  }
  
  // Explore stage: User is exploring (default)
  if (/best|top|recommend|what|how|why|tell me/i.test(lower)) {
    return 'explore';
  }
  
  // If user has asked many follow-ups, they're likely narrowing
  if (recentFollowups.length >= 2) {
    return 'narrow';
  }
  
  return 'explore';
}

