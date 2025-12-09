// ==================================================================
// FOLLOW-UP GENERATOR — Perplexity-style hybrid engine
// ==================================================================
import { findClosestTemplates, getContextEmbedding, } from "./embeddingBank";
import { fillSlots, } from "./templates";
import { analyzeCardNeed, } from "./cardAnalyzer";
import { updateBehaviorState, inferUserGoal, } from "./behaviorTracker";
import { getEmbedding, cosine } from "../embeddings/embeddingClient";
// ==================================================================
// MAIN FOLLOW-UP GENERATION FUNCTION
// ==================================================================
export async function generateFollowUps(input) {
    const { query, answer, intent, prevBehaviorState, lastFollowUp, parentQuery } = input;
    // STEP 1 — Analyze card type, brand, price, city, etc.
    const cardAnalysis = analyzeCardNeed(query);
    // STEP 2 — Update behavior state
    const behaviorState = updateBehaviorState(prevBehaviorState, {
        intent,
        cardType: cardAnalysis.cardType,
        brand: cardAnalysis.brand,
        category: cardAnalysis.category,
        price: cardAnalysis.price,
        city: cardAnalysis.city,
        followUp: query,
    });
    // STEP 3 — Predict user goal (comparison/filter/performance/etc.)
    const userGoal = inferUserGoal(behaviorState);
    // STEP 4 — Create embedding from combined context (query + answer)
    const ctxEmbedding = await getContextEmbedding({
        query,
        answer,
        intent,
    });
    // STEP 5 — Get top semantic templates (10 strongest matches)
    const semanticMatches = await findClosestTemplates(ctxEmbedding, 10, cardAnalysis.cardType);
    // STEP 6 — Combine:
    // 1) semantic match score
    // 2) template weight
    // 3) behavior goal boost
    //
    const scoredSuggestions = [];
    for (const match of semanticMatches) {
        let score = match.score;
        // Boost templates matching user behavior trend
        if (userGoal && match.template.text.toLowerCase().includes(userGoal)) {
            score += 0.15;
        }
        // Boost templates matching detected category
        if (cardAnalysis.category &&
            match.template.category === cardAnalysis.category) {
            score += 0.10;
        }
        // Boost brand-specific follow-ups (if brand exists)
        if (cardAnalysis.brand &&
            match.template.text.toLowerCase().includes("{{brand}}")) {
            score += 0.10;
        }
        scoredSuggestions.push({ template: match.template, score });
    }
    // STEP 7 — Sort and take top 3
    let top3 = scoredSuggestions
        .sort((a, b) => b.score - a.score)
        .slice(0, 5) // Get top 5 for filtering
        .map((item) => fillSlots(item.template, {
        brand: cardAnalysis.brand,
        category: cardAnalysis.category,
        price: cardAnalysis.price,
        city: cardAnalysis.city,
    }));
    // ✅ FOLLOW-UP PATCH: Deduplication and semantic filtering
    let filtered = top3;
    // 1️⃣ Remove exact duplicate of last follow-up
    if (lastFollowUp) {
        filtered = filtered.filter((s) => s.toLowerCase().trim() !== lastFollowUp.toLowerCase().trim());
    }
    // 2️⃣ Remove suggestions identical to the original query
    if (parentQuery) {
        filtered = filtered.filter((s) => s.toLowerCase().trim() !== parentQuery.toLowerCase().trim());
    }
    // Also check against current query
    filtered = filtered.filter((s) => s.toLowerCase().trim() !== query.toLowerCase().trim());
    // 3️⃣ Semantic similarity filtering (remove similar follow-ups)
    if (lastFollowUp && filtered.length > 0) {
        try {
            const lastEmb = await getEmbedding(lastFollowUp);
            const filteredBySimilarity = [];
            for (const suggestion of filtered) {
                const sugEmb = await getEmbedding(suggestion);
                const similarity = cosine(lastEmb, sugEmb);
                // Only keep if similarity is below threshold (not too similar)
                if (similarity < 0.85) {
                    filteredBySimilarity.push(suggestion);
                }
            }
            filtered = filteredBySimilarity;
        }
        catch (err) {
            console.error("❌ Semantic filtering error:", err.message);
            // Continue with filtered list if embedding fails
        }
    }
    // 4️⃣ Return top 3 after filtering
    const finalSuggestions = filtered.slice(0, 3);
    return {
        suggestions: finalSuggestions,
        behaviorState,
        cardAnalysis,
    };
}
