// ==================================================================
// BEHAVIOR TRACKER — light session-based memory for follow-up logic
// ==================================================================

export interface BehaviorState {
  lastIntent: string | null;       // shopping/hotel/location/answer
  lastCardType: string | null;     // shopping/hotel/etc.
  lastBrand: string | null;
  lastCategory: string | null;
  lastPrice: string | null;
  lastCity: string | null;
  followUpHistory: string[];       // last 5 follow-ups
  interestPattern: string | null;  // comparison/filter/budget/etc.
}

// Default empty state
export const initialBehaviorState: BehaviorState = {
  lastIntent: null,
  lastCardType: null,
  lastBrand: null,
  lastCategory: null,
  lastPrice: null,
  lastCity: null,
  followUpHistory: [],
  interestPattern: null,
};

// detect user trend based on follow-up text
function detectInterestPattern(followUp: string): string | null {
  const lower = followUp.toLowerCase();

  if (lower.includes("compare")) return "comparison";
  if (lower.includes("filter")) return "filtering";
  if (lower.includes("size") || lower.includes("color")) return "variants";
  if (lower.includes("under") || lower.includes("budget")) return "budget";
  if (lower.includes("best")) return "best_of";
  if (lower.includes("available")) return "availability";
  if (lower.includes("long-distance") || lower.includes("running")) return "performance";

  return null;
}

// ==================================================================
// UPDATE BEHAVIOR STATE BASED ON THE LATEST QUERY + CARD ANALYSIS
// ==================================================================

export function updateBehaviorState(
  prev: BehaviorState,
  params: {
    intent: string;
    cardType: string;
    brand?: string | null;
    category?: string | null;
    price?: string | null;
    city?: string | null;
    followUp?: string | null;
  }
): BehaviorState {
  const next = { ...prev };

  next.lastIntent = params.intent || prev.lastIntent;
  next.lastCardType = params.cardType || prev.lastCardType;

  if (params.brand) next.lastBrand = params.brand;
  if (params.category) next.lastCategory = params.category;
  if (params.price) next.lastPrice = params.price;
  if (params.city) next.lastCity = params.city;

  // record follow-up history
  if (params.followUp) {
    next.followUpHistory = [...prev.followUpHistory, params.followUp].slice(-5);
    const detected = detectInterestPattern(params.followUp);
    if (detected) next.interestPattern = detected;
  }

  return next;
}

// ==================================================================
// PREDICT NEXT USER PREFERENCE (for better suggestions)
// ==================================================================

export function inferUserGoal(state: BehaviorState): string | null {
  // If user repeatedly compares → next logical step = "comparison"
  if (state.interestPattern === "comparison") {
    return "comparison";
  }

  if (state.interestPattern === "filtering") {
    return "filters";
  }

  if (state.interestPattern === "budget") {
    return "budget_sensitive";
  }

  if (state.interestPattern === "variants") {
    return "variants";
  }

  if (state.interestPattern === "performance") {
    return "performance";
  }

  return null;
}

