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
    // STEP 2: Assess Ambiguity
    // ======================================================================
    let ambiguity = "low";
    // High ambiguity: very short queries, vague terms
    if (queryWords < 4 || /\b(it|this|that|one|some|any)\b/i.test(query)) {
        ambiguity = "high";
    }
    // Medium ambiguity: missing context (no brand, location, category)
    else if (!/\b(brand|location|category|price|under|above)\b/i.test(query) &&
        queryWords < 6) {
        ambiguity = "medium";
    }
    // Low ambiguity: specific query with details
    else {
        ambiguity = "low";
    }
    // ======================================================================
    // STEP 3: Determine Card Role
    // ======================================================================
    let cardRole = "none";
    let needsCards = false;
    let maxCards = 0;
    // Cards are EVIDENCE, never the main answer
    if (userGoal === "decide" || userGoal === "compare") {
        cardRole = "evidence";
        needsCards = true;
        maxCards = 3; // Max 3 for decision/comparison
    }
    else if (userGoal === "choose") {
        cardRole = "options";
        needsCards = true;
        maxCards = 5; // More options for choosing
    }
    else if (userGoal === "browse") {
        cardRole = "options";
        needsCards = true;
        maxCards = 8; // More for browsing
    }
    else if (userGoal === "learn" || userGoal === "locate") {
        // Pure explanation or location - cards optional
        cardRole = "evidence";
        needsCards = false;
        maxCards = 0;
    }
    // ======================================================================
    // STEP 4: Generate Clarification Question (if ambiguous)
    // ======================================================================
    let clarificationQuestion;
    if (ambiguity === "high") {
        // Generate context-aware clarification
        if (/\b(it|this|that)\b/i.test(query)) {
            clarificationQuestion = "Could you provide more details? What specifically are you looking for?";
        }
        else if (queryWords < 3) {
            clarificationQuestion = "I'd like to help you better. Could you tell me more about what you're looking for?";
        }
        else {
            clarificationQuestion = "To give you the best answer, could you clarify what you're looking for?";
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
    // STEP 6: Override for High Ambiguity
    // ======================================================================
    if (ambiguity === "high") {
        // Don't fetch cards for highly ambiguous queries
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
