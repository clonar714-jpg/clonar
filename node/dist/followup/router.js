// src/followup/router.ts
import { detectSemanticIntent } from "../utils/semanticIntent";
import { detectFollowUpIntent } from "../utils/followUpIntent";
import { analyzeCardNeed } from "./cardAnalyzer";
/**
 * MAIN ROUTER — Perplexity-style routing engine
 */
export async function routeQuery({ query, lastTurn, llmAnswer, }) {
    // 1. Pure semantic intent
    const baseIntent = await detectSemanticIntent(query);
    // 2. Follow-up override
    let contextualIntent = baseIntent;
    if (lastTurn) {
        contextualIntent = await detectFollowUpIntent(query, lastTurn.intent ?? "answer", lastTurn.summary ?? "");
    }
    // Normalize mapping
    const normalizedIntent = contextualIntent === "general" ? "answer" : contextualIntent;
    // 3. Card analyzer — entity extraction + hard typing
    const cardInfo = analyzeCardNeed(query);
    // 4. FINAL INTENT LOGIC
    let finalIntent = normalizedIntent;
    // If analyzer says "shopping", override everything
    if (cardInfo.cardType === "shopping")
        finalIntent = "shopping";
    if (cardInfo.cardType === "hotel")
        finalIntent = "hotels";
    if (cardInfo.cardType === "restaurants")
        finalIntent = "restaurants";
    if (cardInfo.cardType === "flights")
        finalIntent = "flights";
    if (cardInfo.cardType === "places")
        finalIntent = "places";
    if (cardInfo.cardType === "location")
        finalIntent = "location";
    // 5. If LLM answer contains hotel/product cues, adjust card type
    const answer = llmAnswer.toLowerCase();
    if (answer.includes("hotel") && finalIntent === "answer") {
        finalIntent = "hotels";
    }
    if ((answer.includes("model") ||
        answer.includes("price") ||
        answer.includes("options")) &&
        finalIntent === "answer") {
        finalIntent = "shopping";
    }
    // 6. Final card type mapping
    const finalCardType = finalIntent === "shopping"
        ? "shopping"
        : finalIntent === "hotels"
            ? "hotel"
            : finalIntent === "restaurants"
                ? "restaurants"
                : finalIntent === "flights"
                    ? "flights"
                    : finalIntent === "places"
                        ? "places"
                        : finalIntent === "location"
                            ? "location"
                            : finalIntent === "movies"
                                ? "movies"
                                : null;
    return {
        finalIntent,
        finalCardType,
        shouldReturnCards: cardInfo.shouldReturnCards,
        brand: cardInfo.brand,
        category: cardInfo.category,
        price: cardInfo.price,
        city: cardInfo.city,
    };
}
