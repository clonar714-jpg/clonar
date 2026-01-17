

import { analyzeCardNeed, type SlotExtraction } from './cardAnalyzer';
import { TEMPLATES } from './templates';
import { fillSlots } from './slotFiller';
import { extractAttributes } from './attributeExtractor';
import { detectAnswerCoverage } from './answerCoverage';
import { inferIntentStage } from './intentStage';
import { scoreFollowup } from './followupScorer';
import { rerankFollowUps } from './rerankFollowups';
import { extractAnswerGaps } from './answerGapExtractor';
import { generateSmartFollowUps } from './smartFollowups';


const behaviorStore = new Map<string, any>();

function getSessionId(sessionId?: string): string {
  return sessionId ?? 'global';
}

function getBehaviorState(sessionId: string): any {
  if (!behaviorStore.has(sessionId)) {
    behaviorStore.set(sessionId, {
      followUpHistory: [],
      userGoal: null,
    });
  }
  return behaviorStore.get(sessionId);
}

function setBehaviorState(sessionId: string, state: any): void {
  behaviorStore.set(sessionId, state);
}

export interface FollowUpParams {
  query: string;
  answer: string;
  intent?: string;
  lastFollowUp?: string;
  parentQuery?: string;
  cards?: any[];
  routingSlots?: SlotExtraction;
  sessionId?: string;
  confidenceBand?: 'high' | 'medium' | 'low';
}

export interface FollowUpResult {
  suggestions: string[];
  slots: SlotExtraction;
}


export async function getFollowUpSuggestions(params: FollowUpParams): Promise<FollowUpResult> {
  const {
    query,
    answer,
    intent = 'answer',
    lastFollowUp,
    parentQuery,
    cards = [],
    routingSlots,
    sessionId: providedSessionId,
    confidenceBand,
  } = params;

  const sessionId = getSessionId(providedSessionId);
  const prevState = getBehaviorState(sessionId);

  
  const extracted = analyzeCardNeed(query);
  const parentSlots = parentQuery ? analyzeCardNeed(parentQuery) : {
    brand: null,
    category: null,
    price: null,
    city: null,
  };

  
  const slots: SlotExtraction = {
    brand: extracted.brand ?? parentSlots.brand ?? routingSlots?.brand ?? null,
    category: extracted.category ?? parentSlots.category ?? routingSlots?.category ?? null,
    price: extracted.price ?? parentSlots.price ?? routingSlots?.price ?? null,
    city: extracted.city ?? parentSlots.city ?? routingSlots?.city ?? null,
  };

  
  const domain = intent === 'shopping' ? 'shopping'
    : intent === 'hotel' || intent === 'hotels' ? 'hotels'
    : intent === 'restaurants' ? 'restaurants'
    : intent === 'flights' ? 'flights'
    : intent === 'places' ? 'places'
    : intent === 'location' ? 'location'
    : 'general';

  const templates = TEMPLATES[domain] || TEMPLATES.general;

  
  const attrs = extractAttributes(answer);

  
  const slotValues = {
    brand: slots.brand,
    category: slots.category,
    price: slots.price,
    city: slots.city,
    purpose: attrs.purpose || attrs.attribute || null,
    gender: null,
  };

  const slotFilled = templates
    .map((t) => fillSlots(t, slotValues))
    .filter((t) => t.length > 0);

  
  const combined: string[] = [...slotFilled];
  
  if (attrs.purpose) {
    combined.push(`Which is best for ${attrs.purpose}?`);
    combined.push(`Alternatives for ${attrs.purpose}?`);
  }
  if (attrs.attribute) {
    combined.push(`Any ${attrs.attribute} options?`);
  }
  if (attrs.style === 'budget') {
    combined.push('Any premium upgrade?');
  } else if (attrs.style === 'premium') {
    combined.push('Is there a better budget option?');
  }

  
  const recentFollowups = prevState.followUpHistory || [];
  const intentStage = inferIntentStage(query, recentFollowups);

  
  const answerCoverage = detectAnswerCoverage(answer);

  
  const answerGaps = await extractAnswerGaps(query, answer, cards);
  console.log(`🧠 Answer gaps extracted: ${answerGaps.potentialFollowUps.length} follow-ups from reasoning gaps`);

  if (answerGaps.potentialFollowUps.length > 0) {
    combined.push(...answerGaps.potentialFollowUps);
  }

  
  const filteredCombined = combined.filter((followup) => {
    const lower = followup.toLowerCase();
    
    if (answerCoverage.comparison && /compare|vs|versus|alternative/i.test(lower)) {
      return false;
    }
    if (answerCoverage.price && /under|\$|price|cost|budget|cheap/i.test(lower)) {
      return false;
    }
    if (answerCoverage.durability && /durable|long-term|quality|last/i.test(lower)) {
      return false;
    }
    if (answerCoverage.useCase && /for running|for travel|for work|use case|purpose/i.test(lower)) {
      return false;
    }
    return true;
  });

  
  const answerSummary = answer.length > 200 ? answer.substring(0, 200) + '...' : answer;
  const rankedWithScores = await rerankFollowUps(query, filteredCombined, 5, answerSummary, recentFollowups);

  
  let allCandidates = rankedWithScores.map((r) => ({
    candidate: r.candidate,
    embeddingScore: r.score,
  }));

  if (rankedWithScores.length < 3) {
    console.log('⚠️ Few ranked follow-ups, using smart follow-ups as fallback');
    const smartFollowUps = await generateSmartFollowUps({
      query,
      answer,
      intent,
      brand: slots.brand,
      category: slots.category,
      price: slots.price,
      city: slots.city,
      lastFollowUp: lastFollowUp || null,
      parentQuery: parentQuery || null,
      cards: cards || [],
    });

    const existingCandidates = new Set(rankedWithScores.map((r) => r.candidate.toLowerCase()));
    const newSmartFollowUps = smartFollowUps
      .filter((s) => !existingCandidates.has(s.toLowerCase()))
      .map((candidate) => ({ candidate, embeddingScore: 0.5 }));

    allCandidates = [...allCandidates, ...newSmartFollowUps].slice(0, 5);
  }

  
  const userGoal = prevState.userGoal || null;
  const scoredFollowups = allCandidates.map((item) => {
    const followup = item.candidate;
    const lower = followup.toLowerCase();

    
    let behaviorScore = 0.5;
    if (userGoal === 'comparison' && /compare|vs|versus/i.test(lower)) {
      behaviorScore = 1.0;
    } else if (userGoal === 'budget_sensitive' && /budget|cheap|under|\$/i.test(lower)) {
      behaviorScore = 1.0;
    } else if (userGoal === 'variants' && /size|color|variation/i.test(lower)) {
      behaviorScore = 1.0;
    } else if (userGoal === 'performance' && /durable|quality|long-term/i.test(lower)) {
      behaviorScore = 1.0;
    }

    
    let stageMatch = 0.5;
    if (intentStage === 'compare' && /compare|vs|versus|difference/i.test(lower)) {
      stageMatch = 1.0;
    } else if (intentStage === 'narrow' && /under|only|filter|specifically/i.test(lower)) {
      stageMatch = 1.0;
    } else if (intentStage === 'act' && /buy|book|reserve|order/i.test(lower)) {
      stageMatch = 1.0;
    } else if (intentStage === 'explore' && /best|top|recommend|what/i.test(lower)) {
      stageMatch = 1.0;
    }

    
    let gapMatch = 0.0;
    if (!answerCoverage.comparison && /compare|vs|versus|alternative/i.test(lower)) {
      gapMatch = 1.0;
    } else if (!answerCoverage.price && /under|\$|price|cost|budget/i.test(lower)) {
      gapMatch = 1.0;
    } else if (!answerCoverage.durability && /durable|long-term|quality/i.test(lower)) {
      gapMatch = 1.0;
    } else if (!answerCoverage.useCase && /for |use case|purpose|suitable/i.test(lower)) {
      gapMatch = 1.0;
    }

    
    const novelty = recentFollowups.length > 0
      ? recentFollowups.some((f: string) => f.toLowerCase() === followup.toLowerCase()) ? 0.3 : 0.8
      : 0.8;

    const adjustedNovelty = recentFollowups.length >= 3 ? novelty * 1.5 : novelty;

    
    const finalScore = scoreFollowup({
      embeddingScore: item.embeddingScore,
      behaviorScore,
      stageMatch,
      noveltyScore: Math.min(adjustedNovelty, 1.0),
      gapMatch,
    });

    return {
      candidate: followup,
      score: finalScore,
    };
  });

  
  let finalFollowUps = scoredFollowups
    .sort((a, b) => b.score - a.score)
    .slice(0, 3)
    .map((item) => item.candidate);

  
  const behaviorState = {
    ...prevState,
    followUpHistory: [...recentFollowups, query].slice(-10), // Keep last 10
    userGoal: userGoal || (intent === 'shopping' ? 'comparison' : null),
  };
  setBehaviorState(sessionId, behaviorState);

  return {
    suggestions: finalFollowUps,
    slots,
  };
}

export function clearBehaviorMemory(): void {
  behaviorStore.clear();
  console.log('🧹 Cleared behavior memory.');
}

