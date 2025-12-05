// ==================================================================
// FOLLOW-UP ENGINE WRAPPER (ENTRY POINT)
// 🟦 C10.5 — LLM NORMALIZATION (Perplexity polish)
// ==================================================================

import { generateFollowUps } from "./generator";
import {
  BehaviorState,
  initialBehaviorState,
  updateBehaviorState,
} from "./behaviorTracker";
import { generateSmartFollowUps } from "./smartFollowups";
import { analyzeCardNeed } from "./cardAnalyzer";
import { TEMPLATES } from "./templates";
import { fillSlots, SlotValues } from "./slotFiller";
import { extractAttributes } from "./attributeExtractor";
import { rerankFollowUps } from "./rerankFollowups";
import { Slots } from "./context";

// To store lightweight session-based behavior states
// (Per session, not long-term user memory)
const behaviorStore = new Map<string, BehaviorState>();

// Create a session ID if none provided
function getSessionId(sessionId?: string): string {
  return sessionId ?? "global";
}

// Retrieve or initialize behavior state
function getBehaviorState(sessionId: string): BehaviorState {
  if (!behaviorStore.has(sessionId)) {
    behaviorStore.set(sessionId, { ...initialBehaviorState });
  }
  return behaviorStore.get(sessionId)!;
}

// Save updated state
function setBehaviorState(sessionId: string, state: BehaviorState) {
  behaviorStore.set(sessionId, state);
}

// ==================================================================
// MAIN FUNCTION CALLED BY THE AGENT ROUTE
// ==================================================================

export async function getFollowUpSuggestions(params: {
  query: string;
  answer: string;
  intent: string;
  sessionId?: string;
  lastFollowUp?: string | null;
  parentQuery?: string | null;
  cards?: any[]; // ✅ NEW: Pass cards for smart follow-ups
  routingSlots?: { // ✅ C3: Pass routing slots if available
    brand?: string | null;
    category?: string | null;
    price?: string | null;
    city?: string | null;
  };
}) {
  const { query, answer, intent, lastFollowUp, parentQuery, cards = [], routingSlots } = params;
  const sessionId = getSessionId(params.sessionId);

  // Load behavior state for this session
  const prevState = getBehaviorState(sessionId);

  // ✅ C3: Use smart follow-ups generator (Perplexity-level)
  // First, get card analysis for slots from new query
  const extracted = analyzeCardNeed(query);
  
  // Extract slots from the *parent* query so context persists
  const parentSlots = parentQuery ? analyzeCardNeed(parentQuery) : {
    brand: null,
    category: null,
    price: null,
    city: null,
  };
  
  // Merge slots: new query slots take priority, fallback to parent, then routing
  const slots: Slots = {
    brand: extracted.brand ?? parentSlots.brand ?? routingSlots?.brand ?? null,
    category: extracted.category ?? parentSlots.category ?? routingSlots?.category ?? null,
    price: extracted.price ?? parentSlots.price ?? routingSlots?.price ?? null,
    city: extracted.city ?? parentSlots.city ?? routingSlots?.city ?? null,
  };
  
  // Use extracted card analysis for card type and trigger
  const cardAnalysis = extracted;

  // 🟦 C10.5 — LLM NORMALIZATION (Perplexity polish)
  // Step 1: Get domain-specific templates
  const domain = intent === "shopping" ? "shopping" 
    : intent === "hotel" || intent === "hotels" ? "hotels"
    : intent === "restaurants" ? "restaurants"
    : intent === "flights" ? "flights"
    : intent === "places" ? "places"
    : intent === "location" ? "location"
    : "general";
  
  const templates = TEMPLATES[domain] || TEMPLATES.general;
  
  // Step 2: Extract attributes from answer (needed for both slot filling and follow-up generation)
  const attrs = extractAttributes(answer);
  
  // Step 3: Fill slots in templates
  const slotValues: SlotValues = {
    brand: slots.brand,
    category: slots.category,
    price: slots.price,
    city: slots.city,
    purpose: attrs.purpose || attrs.attribute || null,
    gender: null, // Can be extracted from query if needed
  };
  
  const slotFilled = templates
    .map((t) => fillSlots(t, slotValues))
    .filter((t) => t.length > 0); // Remove empty templates
  
  // Step 4: Add attribute-based follow-ups
  const combined: string[] = [...slotFilled];
  
  if (attrs.purpose) {
    combined.push(`Which is best for ${attrs.purpose}?`);
    combined.push(`Alternatives for ${attrs.purpose}?`);
  }
  
  if (attrs.attribute) {
    combined.push(`Any ${attrs.attribute} options?`);
  }
  
  if (attrs.style === "budget") {
    combined.push("Any premium upgrade?");
  } else if (attrs.style === "premium") {
    combined.push("Is there a better budget option?");
  }
  
  // Step 5: Embedding-based reranking (C10.4)
  const ranked = await rerankFollowUps(query, combined, 5);
  
  // Fallback to smart follow-ups if we don't have enough ranked suggestions
  let finalFollowUps = ranked;
  if (ranked.length < 3) {
    console.log("⚠️ Few ranked follow-ups, using smart follow-ups as fallback");
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
    // Merge and deduplicate
    const allFollowUps = [...ranked, ...smartFollowUps];
    const unique = Array.from(new Set(allFollowUps));
    finalFollowUps = unique.slice(0, 5);
  }

  // Update behavior state (still track for analytics)
  const behaviorState = updateBehaviorState(prevState, {
    intent,
    cardType: cardAnalysis.cardType,
    brand: slots.brand,
    category: slots.category,
    price: slots.price,
    city: slots.city,
    followUp: query,
  });
  setBehaviorState(sessionId, behaviorState);

  return {
    suggestions: finalFollowUps,
    cardType: cardAnalysis.cardType,
    shouldReturnCards: cardAnalysis.shouldReturnCards,
    slots,
    behaviorState,
  };
}

// ==================================================================
// CLEAR MEMORY (for debugging)
// ==================================================================

export function clearBehaviorMemory() {
  behaviorStore.clear();
  console.log("🧹 Cleared behavior memory.");
}

