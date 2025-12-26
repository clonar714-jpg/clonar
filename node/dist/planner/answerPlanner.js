// ======================================================================
// ANSWER PLANNER - Perplexity-style answer-first architecture
// ======================================================================
// This module decides WHAT to answer before deciding HOW to fetch data.
// Intent becomes a domain hint, not the primary decision maker.
/**
 * Plans the answer strategy BEFORE intent detection.
 * This is the Perplexity mental model: Think → Decide → Prove
 */
export function planAnswer(input) {
    const { query, conversationHistory, lastFollowUp } = input;
    const queryLower = query.toLowerCase().trim();
    const queryWords = query.split(/\s+/).length;
    // ======================================================================
    // STEP 1: Detect User Goal
    // ======================================================================
    let userGoal = "browse"; // Default
    // Decision queries: "best", "worth it", "should I", "better than"
    if (/\b(best|top|worth it|should i|is.*worth|is.*good|recommend|suggest)\b/i.test(query) ||
        /\b(better than|vs|versus|compared to|difference between)\b/i.test(query)) {
        userGoal = "decide";
    }
    // Comparison queries: explicit "vs", "versus", "compare"
    else if (/\b(vs|versus|compare|comparison|difference between|which is better)\b/i.test(query)) {
        userGoal = "compare";
    }
    // Choose queries: "which", "what should I", "pick"
    else if (/\b(which|what should i|pick|choose|select)\b/i.test(query)) {
        userGoal = "choose";
    }
    // Learn queries: "what is", "how does", "explain", "why"
    else if (/\b(what is|what are|how does|how do|explain|why|tell me about|describe)\b/i.test(query)) {
        userGoal = "learn";
    }
    // Locate queries: "where", "near", "in [location]"
    else if (/\b(where|near|in [a-z]+|at [a-z]+|around)\b/i.test(query)) {
        userGoal = "locate";
    }
    // Browse queries: default for product/hotel/movie searches
    else {
        userGoal = "browse";
    }
    // ======================================================================
    // STEP 2: Assess Ambiguity (Perplexity-accurate)
    // ======================================================================
    let ambiguity = "none";
    // Hard ambiguity = missing REQUIRED information with no safe defaults
    // Location-based queries without city/device location
    if (/\b(near me|nearby|around me|close to me)\b/i.test(query) &&
        !/\b(in|at|near|from|to)\s+[A-Z][a-zA-Z\s]{2,}/i.test(query)) {
        ambiguity = "hard";
    }
    // Very vague queries with no context
    else if (queryWords < 3 ||
        (queryWords < 4 && /\b(it|this|that|one|some|any)\b/i.test(query))) {
        ambiguity = "hard";
    }
    // Soft ambiguity = multiple interpretations BUT industry defaults exist
    else if (
    // Queries with price + category have safe defaults
    (/\b(under|below|above|over|under \$|below \$)\d+/i.test(query) && /\b(laptop|phone|watch|shoes|hotel|restaurant)\b/i.test(query)) ||
        // "worth it", "best", "under $X" queries have safe defaults
        /\b(worth it|is.*worth|best|top|recommend|suggest)\b/i.test(query) ||
        // Comparison queries have safe defaults
        /\b(vs|versus|compare|comparison|difference between)\b/i.test(query)) {
        ambiguity = "soft";
    }
    // None ambiguity: specific query with all required details
    else {
        ambiguity = "none";
    }
    // ======================================================================
    // STEP 3: Determine Card Role (Goal > Domain > Intent precedence)
    // ======================================================================
    let cardRole = "none";
    let needsCards = false;
    let maxCards = 0;
    // CRITICAL: Learn goal = ZERO cards (prevents domain leakage)
    if (userGoal === "learn") {
        cardRole = "none";
        needsCards = false;
        maxCards = 0; // NEVER show cards for learn queries
    }
    // Locate goal = cards only AFTER location known
    else if (userGoal === "locate") {
        if (ambiguity === "hard") {
            // No location available - no cards
            cardRole = "none";
            needsCards = false;
            maxCards = 0;
        }
        else {
            // Location known - cards allowed
            cardRole = "evidence";
            needsCards = true;
            maxCards = 5;
        }
    }
    // Cards are EVIDENCE, never the main answer
    else if (userGoal === "decide" || userGoal === "compare") {
        cardRole = "evidence";
        needsCards = true;
        maxCards = 3; // Max 2-3 for decision/comparison
    }
    else if (userGoal === "choose") {
        cardRole = "options";
        needsCards = true;
        maxCards = 5; // More options for choosing
    }
    else if (userGoal === "browse") {
        cardRole = "options";
        needsCards = true;
        maxCards = 6; // Up to 6 for browsing
    }
    // ======================================================================
    // STEP 4: Generate Clarification Question (ONLY for hard ambiguity)
    // ======================================================================
    let clarificationQuestion;
    if (ambiguity === "hard") {
        // Location-based queries: ask ONLY for location
        if (/\b(near me|nearby|around me|close to me)\b/i.test(query)) {
            clarificationQuestion = "What location are you looking for?";
        }
        // Very vague queries: ask for specifics
        else if (/\b(it|this|that)\b/i.test(query)) {
            clarificationQuestion = "What specifically are you looking for?";
        }
        else if (queryWords < 3) {
            clarificationQuestion = "Could you provide more details about what you're looking for?";
        }
        else {
            clarificationQuestion = "Could you clarify what you're looking for?";
        }
    }
    // ======================================================================
    // STEP 5: Refine Primary Question
    // ======================================================================
    let primaryQuestion = query;
    // If it's a follow-up, try to extract the core question
    if (lastFollowUp && conversationHistory.length > 0) {
        const lastQuery = conversationHistory[conversationHistory.length - 1]?.query || "";
        // Merge context if needed
        if (queryWords < 4 && lastQuery) {
            primaryQuestion = `${lastQuery} ${query}`;
        }
    }
    // ======================================================================
    // STEP 6: Override for Hard Ambiguity
    // ======================================================================
    if (ambiguity === "hard") {
        // Don't fetch cards for hard ambiguous queries
        needsCards = false;
        maxCards = 0;
        cardRole = "none";
    }
    return {
        userGoal,
        primaryQuestion,
        needsCards,
        maxCards,
        cardRole,
        ambiguity,
        clarificationQuestion,
    };
}
