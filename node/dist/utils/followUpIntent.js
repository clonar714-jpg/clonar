// src/utils/followUpIntent.ts
import { classifyIntent } from "./semanticIntent";
import { getEmbedding, cosine } from "../embeddings/embeddingClient";
import { getSession } from "../memory/sessionMemory";
// ------------------------------------------------------------------
// SENTENCE GROUPS FOR CONTEXT-AWARE FOLLOW-UP CLASSIFICATION
// ------------------------------------------------------------------
const followUpShoppingTriggers = [
    "best models",
    "top models",
    "recommend models",
    "find products",
    "suggest products",
    "compare products",
    "compare models",
    "show options",
    "show more options",
    "more shoes",
    "best shoes",
    "running shoes",
    "basketball shoes",
    "find deals",
    "under",
    "price",
    "buy",
];
const followUpNonShoppingTriggers = [
    "size chart",
    "return policy",
    "warranty",
    "how long to deliver",
    "deliver",
    "shipping",
    "reviews",
];
// Attribute-level shopping queries (these should trigger shopping, not answer)
const shoppingAttributes = [
    "size", "sizes", "filter", "color", "colour",
    "availability", "in stock", "stock", "variants",
    "fit", "wide", "narrow", "large", "small", "medium",
    "black", "white", "blue", "green", "red", "grey", "gray", "brown",
    "waterproof", "durability", "comfort",
];
// hotel triggers
const followUpHotelTriggers = [
    "best areas",
    "best places to stay",
    "price per night",
    "downtown hotels",
    "cheap hotels",
    "luxury hotels",
    "compare hotels",
    "location near",
];
// restaurant triggers
const followUpRestaurantTriggers = [
    "good places to eat",
    "top restaurants",
    "near me",
    "cheap restaurants",
];
// flights triggers
const followUpFlightTriggers = [
    "cheap flights",
    "best flights",
    "airfare",
    "ticket price",
];
// ------------------------------------------------------------------
// Helper: find highest similarity within a phrase list
// ------------------------------------------------------------------
async function matchCategory(query, list) {
    const qEmb = await getEmbedding(query);
    let max = 0;
    for (const example of list) {
        const emb = await getEmbedding(example);
        const score = cosine(qEmb, emb);
        if (score > max)
            max = score;
    }
    return max;
}
/**
 * Check if query is weak (needs context to understand)
 */
function queryIsWeak(query) {
    const weakPatterns = [
        "best ones",
        "what colors?",
        "what color?",
        "what size?",
        "what sizes?",
        "more options",
        "more",
        "others",
        "alternatives",
        "different",
        "wide?",
        "narrow?",
        "running ones",
        "which one",
        "which ones",
        "show me",
        "any",
        "available?",
    ];
    const lower = query.toLowerCase();
    return weakPatterns.some((pattern) => lower.includes(pattern));
}
// ------------------------------------------------------------------
// MAIN FUNCTION — determine intent for follow-up queries
// 🧠 C9.2 — Memory-Aware Follow-Up Routing
// ------------------------------------------------------------------
export async function detectFollowUpIntent(newQuery, previousIntent, lastAnswer, sessionId) {
    newQuery = newQuery.toLowerCase().trim();
    // 🧠 C9.2 — Check session memory FIRST
    if (sessionId) {
        const session = await getSession(sessionId).catch(() => null);
        // If strong domain already active → inherit it for weak queries
        if (session && session.domain !== "general") {
            if (queryIsWeak(newQuery)) {
                console.log(`🧠 Memory-aware: Weak query "${newQuery}" inherits domain "${session.domain}"`);
                return session.domain;
            }
        }
    }
    // 1. First check explicit/obvious intent
    const explicit = await classifyIntent(newQuery);
    if (explicit !== "answer")
        return explicit;
    // 2. Then check CONTEXT (previous intent)
    if (previousIntent === "shopping") {
        // ✅ C6 PATCH #6 — Fix "Filter by size" not giving cards
        // Check shopping attributes FIRST (before other checks)
        if (shoppingAttributes.some(a => newQuery.includes(a))) {
            return "shopping"; // inherit shopping context
        }
        const shopScore = await matchCategory(newQuery, followUpShoppingTriggers);
        const nonShopScore = await matchCategory(newQuery, followUpNonShoppingTriggers);
        // If user explicitly wants to buy/search again
        if (shopScore >= 0.40 && shopScore > nonShopScore) {
            return "shopping";
        }
        // User asking about return policy/warranty/etc → NOT a product search
        if (nonShopScore >= 0.40) {
            return "answer";
        }
        // Weak signals → default to answer
        return "answer";
    }
    if (previousIntent === "hotels") {
        // ✅ Check for location-related queries (near, downtown, airport, etc.)
        // These are likely hotel refinements when previous intent was hotels
        const locationKeywords = ["near", "downtown", "airport", "beach", "center", "district", "area", "close to", "around"];
        if (locationKeywords.some(keyword => newQuery.includes(keyword))) {
            console.log(`🧠 Hotel context: Location query "${newQuery}" inherits hotels intent`);
            return "hotels";
        }
        const hotelScore = await matchCategory(newQuery, followUpHotelTriggers);
        if (hotelScore >= 0.40)
            return "hotels";
        // ✅ If query is vague/weak and previous was hotels, inherit hotels intent
        if (queryIsWeak(newQuery)) {
            console.log(`🧠 Hotel context: Weak query "${newQuery}" inherits hotels intent`);
            return "hotels";
        }
        return explicit; // fall back to semanticIntent
    }
    if (previousIntent === "restaurants") {
        const restScore = await matchCategory(newQuery, followUpRestaurantTriggers);
        if (restScore >= 0.40)
            return "restaurants";
        return explicit;
    }
    if (previousIntent === "flights") {
        const fScore = await matchCategory(newQuery, followUpFlightTriggers);
        if (fScore >= 0.40)
            return "flights";
        return explicit;
    }
    if (previousIntent === "places") {
        const placesScore = await matchCategory(newQuery, [
            "near",
            "beaches",
            "temples",
            "waterfalls",
            "mountains",
            "islands",
            "nature",
            "culture",
            "what else",
            "other places",
            "things to do",
            "attractions",
            "best places",
            "top places",
        ]);
        if (placesScore >= 0.35)
            return "places";
        return explicit;
    }
    // 🧠 C9.2 — Fallback to session memory if available
    if (sessionId) {
        const session = await getSession(sessionId).catch(() => null);
        if (session && session.domain !== "general") {
            console.log(`🧠 Memory-aware: Falling back to session domain "${session.domain}"`);
            return session.domain;
        }
    }
    // 3. If no context → rely fully on embeddings classifier
    return explicit || previousIntent || "answer";
}
// ------------------------------------------------------------------
// COMPATIBILITY WRAPPER for existing code
// ------------------------------------------------------------------
export async function detectFollowUpCardNeed(query, conversationHistory) {
    try {
        let previousIntent = 'general';
        let previousQuery = '';
        let previousSummary = '';
        if (conversationHistory && conversationHistory.length > 0) {
            for (let i = conversationHistory.length - 1; i >= 0; i--) {
                const msg = conversationHistory[i];
                if (msg.intent && msg.intent !== 'answer' && msg.intent !== 'general') {
                    previousIntent = msg.intent;
                    previousQuery = msg.query || '';
                    previousSummary = msg.summary || '';
                    break;
                }
            }
        }
        if (previousIntent === 'general' || previousIntent === 'answer') {
            return { needsCards: false, cardType: null };
        }
        const detectedIntent = await detectFollowUpIntent(query, previousIntent, previousSummary);
        const needsCards = detectedIntent !== 'answer' && detectedIntent !== 'general';
        const cardType = needsCards ? detectedIntent : null;
        return { needsCards, cardType };
    }
    catch (e) {
        console.error("❌ detectFollowUpCardNeed error:", e.message);
        return { needsCards: false, cardType: null };
    }
}
