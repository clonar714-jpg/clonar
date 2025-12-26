// ======================================================================
// CARD FETCH DECISION - Goal-first card fetching authority
// ======================================================================
// This module enforces goal-first execution and decouples Decide from shopping

export type UserGoal = "browse" | "compare" | "choose" | "decide" | "learn" | "locate";
export type AmbiguityLevel = "none" | "soft" | "hard";

// ✅ RULE 4: Separate CardRole (from Goal) from CardDomain (from Capability)
export type CardRole = "evidence" | "options" | "none";
export type CardDomain = "shopping" | "hotel" | "restaurant" | "flight" | "place" | "movie" | "web" | null;

export interface CardFetchParams {
  userGoal: UserGoal;
  ambiguity: AmbiguityLevel;
  needsCards: boolean;
  domainHint?: string; // Capability hint (e.g., "shopping", "hotels")
  isNonSkuCategory?: boolean; // For non-SKU categories (cars, real estate, etc.)
}

export interface CardFetchDecision {
  shouldFetch: boolean;
  cardRole: CardRole; // ✅ RULE 4: Role comes ONLY from UserGoal
  cardDomain: CardDomain; // ✅ RULE 4: Domain comes ONLY from Capability
  maxCards: number;
  disableShoppingFetch: boolean;
  suppressShoppingTag: boolean;
  // ✅ DEPRECATED: cardType kept for backward compatibility during migration
  // @deprecated Use cardRole + cardDomain instead
  cardType: "shopping" | "hotel" | "restaurants" | "flights" | "places" | "movies" | "evidence" | null;
}

/**
 * ✅ SINGLE SOURCE OF TRUTH for card fetching decisions
 * Enforces goal-first execution and fully decouples Decide from shopping
 */
export function shouldFetchCards(params: CardFetchParams): CardFetchDecision {
  const { userGoal, ambiguity, needsCards, domainHint, isNonSkuCategory = false } = params;

  // ✅ GUARDRAIL 1: Learn goal - cards always disabled
  // ✅ LEARN INVARIANT: LEARN queries are answer-only. They must never trigger commerce, retries, or card fetch.
  // This is a hard invariant that cannot be overridden by embeddings, intent detection, or query rewrite.
  if (userGoal === "learn") {
    return {
      shouldFetch: false,
      cardRole: "none", // ✅ RULE 4: Role from Goal
      cardDomain: null, // ✅ RULE 4: No domain for learn
      maxCards: 0,
      disableShoppingFetch: true,
      suppressShoppingTag: true,
      cardType: null, // ✅ DEPRECATED: Backward compatibility
    };
  }

  // ✅ GUARDRAIL 2: Hard ambiguity - no cards
  if (ambiguity === "hard") {
    return {
      shouldFetch: false,
      cardRole: "none", // ✅ RULE 4: Role from Goal
      cardDomain: null, // ✅ RULE 4: No domain for hard ambiguity
      maxCards: 0,
      disableShoppingFetch: true,
      suppressShoppingTag: true,
      cardType: null, // ✅ DEPRECATED: Backward compatibility
    };
  }

  // ✅ GUARDRAIL 3: Decide goal - evidence cards only, NEVER shopping
  // ✅ INVARIANT: Decision queries may fetch evidence cards even when shopping is suppressed
  // Evidence cards are NOT shopping cards - they come from reviews, comparisons, expert articles
  if (userGoal === "decide") {
    // Decide queries get evidence cards only (reviews, comparisons, specs)
    // Max 2-3 cards, cardRole = "evidence", cardDomain = "web", NEVER "shopping"
    return {
      shouldFetch: needsCards && !isNonSkuCategory, // Allow evidence if needed and not non-SKU
      cardRole: needsCards && !isNonSkuCategory ? "evidence" : "none", // ✅ RULE 4: Role from Goal
      cardDomain: needsCards && !isNonSkuCategory ? "web" : null, // ✅ RULE 4: Domain for evidence is "web"
      maxCards: 3, // Max 2-3 cards for decide
      disableShoppingFetch: true, // ✅ CRITICAL: Disable shopping providers (NOT evidence providers)
      suppressShoppingTag: true, // ✅ CRITICAL: No shopping tag
      cardType: needsCards && !isNonSkuCategory ? "evidence" : null, // ✅ DEPRECATED: Backward compatibility
    };
  }

  // ✅ GUARDRAIL 4: Browse goal - full shopping pipeline allowed
  if (userGoal === "browse") {
    // Browse queries can use full shopping pipeline
    // ✅ RULE 4: Map capability hint to domain
    const cardDomain: CardDomain = domainHint === "shopping" ? "shopping" : 
                     domainHint === "hotels" ? "hotel" :
                     domainHint === "restaurants" ? "restaurant" :
                     domainHint === "flights" ? "flight" :
                     domainHint === "places" ? "place" :
                     domainHint === "movies" ? "movie" :
                     null;
    
    return {
      shouldFetch: needsCards && !!cardDomain,
      cardRole: "options", // ✅ RULE 4: Role from Goal (browse = options)
      cardDomain, // ✅ RULE 4: Domain from Capability
      maxCards: 12, // Browse can have more cards
      disableShoppingFetch: false, // Shopping allowed for browse
      suppressShoppingTag: false, // Shopping tag allowed for browse
      cardType: cardDomain === "hotel" ? "hotel" : 
                cardDomain === "restaurant" ? "restaurants" :
                cardDomain === "flight" ? "flights" :
                cardDomain === "place" ? "places" :
                cardDomain === "movie" ? "movies" :
                cardDomain, // ✅ DEPRECATED: Backward compatibility
    };
  }

  // ✅ GUARDRAIL 5: Compare goal - evidence cards, max 2-3
  // ✅ COMPARE INVARIANT: COMPARE is a terminal analytical goal. It cannot be overridden by shopping or decision logic.
  // COMPARE may have zero cards OR evidence-only cards (reviews, specs). COMPARE must NEVER use shopping cards.
  if (userGoal === "compare") {
    return {
      shouldFetch: needsCards,
      cardRole: needsCards ? "evidence" : "none", // ✅ RULE 4: Role from Goal (compare = evidence)
      cardDomain: needsCards ? "web" : null, // ✅ RULE 4: Domain for evidence is "web"
      maxCards: 3, // Max 2-3 cards for compare
      disableShoppingFetch: true, // ✅ COMPARE INVARIANT: No shopping for compare
      suppressShoppingTag: true, // ✅ COMPARE INVARIANT: No shopping tag
      cardType: needsCards ? "evidence" : null, // ✅ DEPRECATED: Backward compatibility
    };
  }

  // ✅ GUARDRAIL 6: Locate goal - location cards only
  if (userGoal === "locate") {
    const hasLocationCapability = domainHint === "places" || domainHint === "location";
    return {
      shouldFetch: needsCards && hasLocationCapability,
      cardRole: needsCards && hasLocationCapability ? "evidence" : "none", // ✅ RULE 4: Role from Goal (locate = evidence)
      cardDomain: needsCards && hasLocationCapability ? "place" : null, // ✅ RULE 4: Domain from Capability
      maxCards: 6,
      disableShoppingFetch: true,
      suppressShoppingTag: true,
      cardType: needsCards && hasLocationCapability ? "places" : null, // ✅ DEPRECATED: Backward compatibility
    };
  }

  // ✅ GUARDRAIL 7: Choose goal - options cards
  if (userGoal === "choose") {
    // ✅ RULE 4: Map capability hint to domain
    const cardDomain: CardDomain = domainHint === "shopping" ? "shopping" : 
                     domainHint === "hotels" ? "hotel" :
                     domainHint === "restaurants" ? "restaurant" :
                     domainHint === "flights" ? "flight" :
                     domainHint === "places" ? "place" :
                     domainHint === "movies" ? "movie" :
                     null;
    
    return {
      shouldFetch: needsCards && !!cardDomain,
      cardRole: "options", // ✅ RULE 4: Role from Goal (choose = options)
      cardDomain, // ✅ RULE 4: Domain from Capability
      maxCards: 5, // More options for choosing
      disableShoppingFetch: cardDomain === "shopping" ? false : true, // Shopping allowed if domain is shopping
      suppressShoppingTag: cardDomain === "shopping" ? false : true,
      cardType: cardDomain === "hotel" ? "hotel" : 
                cardDomain === "restaurant" ? "restaurants" :
                cardDomain === "flight" ? "flights" :
                cardDomain === "place" ? "places" :
                cardDomain === "movie" ? "movies" :
                cardDomain, // ✅ DEPRECATED: Backward compatibility
    };
  }

  // ✅ Default: No cards
  return {
    shouldFetch: false,
    cardRole: "none", // ✅ RULE 4: Role from Goal (default = none)
    cardDomain: null, // ✅ RULE 4: No domain by default
    maxCards: 0,
    disableShoppingFetch: true,
    suppressShoppingTag: true,
    cardType: null, // ✅ DEPRECATED: Backward compatibility
  };
}

/**
 * ✅ RULE 5: Hard Invariant Assertion
 * Throws if decide goal has shopping domain
 */
export function assertDecideNotShopping(userGoal: UserGoal, cardDomain: CardDomain): void {
  if (userGoal === "decide" && cardDomain === "shopping") {
    throw new Error("Invariant violation: Decide cannot have shopping domain");
  }
}

/**
 * ✅ DEPRECATED: Legacy assertion for backward compatibility
 * @deprecated Use assertDecideNotShopping with cardDomain instead
 */
export function assertDecideNotShoppingLegacy(userGoal: UserGoal, cardType: string | null): void {
  if (userGoal === "decide" && cardType === "shopping") {
    throw new Error("Invariant violation: Decide cannot be shopping");
  }
}


