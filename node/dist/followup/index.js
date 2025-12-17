// ==================================================================
// FOLLOW-UP ENGINE WRAPPER (ENTRY POINT)
// 🟦 C10.5 — LLM NORMALIZATION (Perplexity polish)
// ==================================================================
import { initialBehaviorState, updateBehaviorState, inferUserGoal, } from "./behaviorTracker";
import { generateSmartFollowUps } from "./smartFollowups";
import { analyzeCardNeed } from "./cardAnalyzer";
import { TEMPLATES } from "./templates";
import { fillSlots } from "./slotFiller";
import { extractAttributes } from "./attributeExtractor";
import { rerankFollowUps } from "./rerankFollowups";
import { inferIntentStage } from "./intentStage";
import { detectAnswerCoverage } from "./answerCoverage";
import { scoreFollowup } from "./followupScorer";
import { noveltyScore } from "./novelty";
import { extractAnswerGaps } from "./answerGapExtractor";
// To store lightweight session-based behavior states
// (Per session, not long-term user memory)
const behaviorStore = new Map();
// Create a session ID if none provided
function getSessionId(sessionId) {
    return sessionId ?? "global";
}
// Retrieve or initialize behavior state
function getBehaviorState(sessionId) {
    if (!behaviorStore.has(sessionId)) {
        behaviorStore.set(sessionId, { ...initialBehaviorState });
    }
    return behaviorStore.get(sessionId);
}
// Save updated state
function setBehaviorState(sessionId, state) {
    behaviorStore.set(sessionId, state);
}
// ==================================================================
// MAIN FUNCTION CALLED BY THE AGENT ROUTE
// ==================================================================
export async function getFollowUpSuggestions(params) {
    const { query, answer, intent, lastFollowUp, parentQuery, cards = [], routingSlots, answerPlan } = params;
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
    const slots = {
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
    const slotValues = {
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
    const combined = [...slotFilled];
    if (attrs.purpose) {
        combined.push(`Which is best for ${attrs.purpose}?`);
        combined.push(`Alternatives for ${attrs.purpose}?`);
    }
    if (attrs.attribute) {
        combined.push(`Any ${attrs.attribute} options?`);
    }
    if (attrs.style === "budget") {
        combined.push("Any premium upgrade?");
    }
    else if (attrs.style === "premium") {
        combined.push("Is there a better budget option?");
    }
    // ✅ UPGRADE: Get follow-up history from behavior state
    const recentFollowups = prevState.followUpHistory || [];
    // ✅ UPGRADE: Infer intent stage
    const intentStage = inferIntentStage(query, recentFollowups);
    // ✅ UPGRADE: Detect answer coverage (what was already answered)
    const answerCoverage = detectAnswerCoverage(answer);
    // ✅ ANSWER-FIRST: Extract reasoning gaps from answer
    const answerGaps = await extractAnswerGaps(query, answer, cards);
    console.log(`🧠 Answer gaps extracted: ${answerGaps.potentialFollowUps.length} follow-ups from reasoning gaps`);
    // ✅ ANSWER-FIRST: Add reasoning-based follow-ups (prioritize these)
    if (answerGaps.potentialFollowUps.length > 0) {
        combined.push(...answerGaps.potentialFollowUps);
    }
    // ✅ UPGRADE: Suppress follow-ups that cover already-answered dimensions
    let filteredCombined = combined.filter((followup) => {
        const lower = followup.toLowerCase();
        // Suppress comparison follow-ups if answer already covers comparison
        if (answerCoverage.comparison && /compare|vs|versus|alternative/i.test(lower)) {
            return false;
        }
        // Suppress price follow-ups if answer already covers price
        if (answerCoverage.price && /under|\$|price|cost|budget|cheap/i.test(lower)) {
            return false;
        }
        // Suppress durability follow-ups if answer already covers durability
        if (answerCoverage.durability && /durable|long-term|quality|last/i.test(lower)) {
            return false;
        }
        // Suppress use case follow-ups if answer already covers use case
        if (answerCoverage.useCase && /for running|for travel|for work|use case|purpose/i.test(lower)) {
            return false;
        }
        return true;
    });
    // Step 5: Embedding-based reranking with multi-context (C10.4 + UPGRADE)
    const answerSummary = answer.length > 200 ? answer.substring(0, 200) + "..." : answer;
    const rankedWithScores = await rerankFollowUps(query, filteredCombined, 5, answerSummary, recentFollowups);
    // Fallback to smart follow-ups if we don't have enough ranked suggestions
    let allCandidates = rankedWithScores.map((r) => ({
        candidate: r.candidate,
        embeddingScore: r.score,
    }));
    if (rankedWithScores.length < 3) {
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
        // Merge and deduplicate, assign default embedding scores
        const existingCandidates = new Set(rankedWithScores.map((r) => r.candidate.toLowerCase()));
        const newSmartFollowUps = smartFollowUps
            .filter((s) => !existingCandidates.has(s.toLowerCase()))
            .map((candidate) => ({ candidate, embeddingScore: 0.5 }));
        allCandidates = [...allCandidates, ...newSmartFollowUps].slice(0, 5);
    }
    // ✅ UPGRADE: Score each follow-up using multi-factor scoring
    const userGoal = inferUserGoal(prevState);
    const scoredFollowups = allCandidates.map((item) => {
        const followup = item.candidate;
        const lower = followup.toLowerCase();
        // Behavior score: match user's interest pattern
        let behaviorScore = 0.5; // default
        if (userGoal === "comparison" && /compare|vs|versus/i.test(lower)) {
            behaviorScore = 1.0;
        }
        else if (userGoal === "budget_sensitive" && /budget|cheap|under|\$/i.test(lower)) {
            behaviorScore = 1.0;
        }
        else if (userGoal === "variants" && /size|color|variation/i.test(lower)) {
            behaviorScore = 1.0;
        }
        else if (userGoal === "performance" && /durable|quality|long-term/i.test(lower)) {
            behaviorScore = 1.0;
        }
        // Stage match: align with current intent stage
        let stageMatch = 0.5; // default
        if (intentStage === "compare" && /compare|vs|versus|difference/i.test(lower)) {
            stageMatch = 1.0;
        }
        else if (intentStage === "narrow" && /under|only|filter|specifically/i.test(lower)) {
            stageMatch = 1.0;
        }
        else if (intentStage === "act" && /buy|book|reserve|order/i.test(lower)) {
            stageMatch = 1.0;
        }
        else if (intentStage === "explore" && /best|top|recommend|what/i.test(lower)) {
            stageMatch = 1.0;
        }
        // Gap match: fills gaps in answer coverage
        let gapMatch = 0.0;
        if (!answerCoverage.comparison && /compare|vs|versus|alternative/i.test(lower)) {
            gapMatch = 1.0;
        }
        else if (!answerCoverage.price && /under|\$|price|cost|budget/i.test(lower)) {
            gapMatch = 1.0;
        }
        else if (!answerCoverage.durability && /durable|long-term|quality/i.test(lower)) {
            gapMatch = 1.0;
        }
        else if (!answerCoverage.useCase && /for |use case|purpose|suitable/i.test(lower)) {
            gapMatch = 1.0;
        }
        // Novelty score
        const novelty = noveltyScore(followup, recentFollowups);
        // Boost novelty if user has asked many follow-ups
        const adjustedNovelty = recentFollowups.length >= 3 ? novelty * 1.5 : novelty;
        // Final score
        const finalScore = scoreFollowup({
            embeddingScore: item.embeddingScore,
            behaviorScore,
            stageMatch,
            noveltyScore: Math.min(adjustedNovelty, 1.0), // Cap at 1.0
            gapMatch,
        });
        return {
            candidate: followup,
            score: finalScore,
        };
    });
    // ✅ UPGRADE: Sort by final score and return top 3
    const finalFollowUps = scoredFollowups
        .sort((a, b) => b.score - a.score)
        .slice(0, 3)
        .map((item) => item.candidate);
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
