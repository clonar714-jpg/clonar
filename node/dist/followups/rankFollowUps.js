// ✅ PHASE 9: Follow-Up Ranking Engine
// Ranks follow-ups by relevance and diversity
/**
 * Rank follow-ups by relevance and diversity
 * @param followUps - Array of follow-up suggestions
 * @param intent - Detected intent
 * @param slots - Extracted slots
 * @returns Ranked array of follow-ups (top ones first)
 */
export function rankFollowUps(followUps, intent, slots) {
    if (!Array.isArray(followUps) || followUps.length === 0) {
        return [];
    }
    // ✅ Remove useless follow-ups
    const uselessPatterns = [
        /^(yes|no|ok|sure|maybe|thanks|thank you)$/i,
        /^(what|how|why|when|where)\s*$/i, // Single question words
        /^(show|find|get)\s+me\s*$/i, // Incomplete commands
    ];
    const filtered = followUps.filter(followUp => {
        const trimmed = followUp.trim();
        if (trimmed.length < 3)
            return false; // Too short
        // Check against useless patterns
        for (const pattern of uselessPatterns) {
            if (pattern.test(trimmed)) {
                return false;
            }
        }
        return true;
    });
    // ✅ Score each follow-up
    const scored = filtered.map(followUp => {
        let score = 0;
        const lower = followUp.toLowerCase();
        // ✅ Intent relevance scoring
        if (intent === "shopping") {
            if (lower.includes("price") || lower.includes("cost"))
                score += 3;
            if (lower.includes("compare") || lower.includes("alternative"))
                score += 2;
            if (lower.includes("review") || lower.includes("rating"))
                score += 2;
            if (lower.includes("buy") || lower.includes("purchase"))
                score += 1;
        }
        else if (intent === "hotels") {
            if (lower.includes("map") || lower.includes("location"))
                score += 3;
            if (lower.includes("amenity") || lower.includes("feature"))
                score += 2;
            if (lower.includes("deal") || lower.includes("discount"))
                score += 2;
            if (lower.includes("nearby") || lower.includes("attraction"))
                score += 2;
        }
        else if (intent === "places") {
            if (lower.includes("map") || lower.includes("location"))
                score += 3;
            if (lower.includes("how to") || lower.includes("get there"))
                score += 2;
            if (lower.includes("best time") || lower.includes("when"))
                score += 2;
            if (lower.includes("tour") || lower.includes("guide"))
                score += 2;
        }
        else if (intent === "restaurants") {
            if (lower.includes("menu") || lower.includes("dish"))
                score += 3;
            if (lower.includes("review") || lower.includes("rating"))
                score += 2;
            if (lower.includes("reservation") || lower.includes("book"))
                score += 2;
            if (lower.includes("cuisine") || lower.includes("type"))
                score += 2;
        }
        else if (intent === "flights") {
            if (lower.includes("price") || lower.includes("deal"))
                score += 3;
            if (lower.includes("time") || lower.includes("schedule"))
                score += 2;
            if (lower.includes("airline") || lower.includes("route"))
                score += 2;
        }
        // ✅ Slot relevance scoring
        if (slots) {
            if (slots.location || slots.city) {
                if (lower.includes("nearby") || lower.includes("around"))
                    score += 1;
            }
            if (slots.category) {
                if (lower.includes(slots.category.toLowerCase()))
                    score += 1;
            }
            if (slots.brand) {
                if (lower.includes(slots.brand.toLowerCase()))
                    score += 1;
            }
        }
        // ✅ Diversity scoring (prefer questions over statements)
        if (lower.includes("?") || lower.startsWith("what") || lower.startsWith("how") ||
            lower.startsWith("why") || lower.startsWith("when") || lower.startsWith("where")) {
            score += 1;
        }
        // ✅ Length scoring (prefer medium-length follow-ups)
        if (followUp.length >= 10 && followUp.length <= 50) {
            score += 1;
        }
        else if (followUp.length < 5 || followUp.length > 100) {
            score -= 1; // Penalize very short or very long
        }
        return { followUp, score };
    });
    // ✅ Sort by score (descending)
    scored.sort((a, b) => b.score - a.score);
    // ✅ Promote diverse follow-ups (remove similar ones)
    const diverse = [];
    const seenKeywords = new Set();
    for (const { followUp, score } of scored) {
        // Extract key words
        const keywords = followUp
            .toLowerCase()
            .split(/\s+/)
            .filter(w => w.length > 3)
            .slice(0, 3); // Top 3 keywords
        // Check if too similar to existing follow-ups
        const isSimilar = keywords.some(kw => seenKeywords.has(kw));
        if (!isSimilar || diverse.length < 3) {
            // Add if not similar, or if we need more diversity
            diverse.push(followUp);
            keywords.forEach(kw => seenKeywords.add(kw));
        }
        // Limit to top 5
        if (diverse.length >= 5) {
            break;
        }
    }
    // ✅ Ensure minimum 3 follow-ups if available
    if (diverse.length < 3 && filtered.length >= 3) {
        // Add top-scored ones that weren't added yet
        for (const { followUp } of scored) {
            if (!diverse.includes(followUp)) {
                diverse.push(followUp);
                if (diverse.length >= 3)
                    break;
            }
        }
    }
    return diverse.length > 0 ? diverse : filtered.slice(0, 5);
}
