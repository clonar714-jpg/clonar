

export type IntentStage = 'explore' | 'compare' | 'narrow' | 'act';


export function inferIntentStage(query: string, recentFollowups: string[]): IntentStage {
  const lower = query.toLowerCase();
  
  
  if (/buy|purchase|order|book|reserve|get|where to buy/i.test(lower)) {
    return 'act';
  }
  
  
  if (/compare|vs|versus|difference|better|which one/i.test(lower)) {
    return 'compare';
  }
  
  
  if (/under|below|less than|only|specifically|filter|narrow/i.test(lower)) {
    return 'narrow';
  }
  
  
  if (/best|top|recommend|what|how|why|tell me/i.test(lower)) {
    return 'explore';
  }
  
  
  if (recentFollowups.length >= 2) {
    return 'narrow';
  }
  
  return 'explore';
}

