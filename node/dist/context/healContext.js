// ✅ PHASE 8: Context Healing
// Reinterprets vague follow-ups and fills missing data from session history
/**
 * Heal follow-up query by filling missing context from session history
 * @param query - The follow-up query (may be vague)
 * @param sessionHistory - Previous session(s) for context
 * @returns Improved, complete query
 */
export function healFollowUp(query, sessionHistory) {
    if (!sessionHistory || sessionHistory.length === 0) {
        return query;
    }
    const lastSession = sessionHistory[sessionHistory.length - 1];
    const lowerQuery = query.toLowerCase().trim();
    // ✅ Reinterpret vague follow-ups
    let healedQuery = query;
    // "cheaper ones" → "cheaper [product/hotel] in [location]"
    if (lowerQuery.includes("cheaper") ||
        lowerQuery.includes("cheap") ||
        lowerQuery.includes("affordable")) {
        const lastIntent = lastSession.intent || lastSession.cardType;
        const lastCategory = lastSession.slots?.category || "";
        const lastLocation = lastSession.slots?.city || lastSession.slots?.location || "";
        if (lastIntent === "shopping" && lastCategory) {
            healedQuery = `cheaper ${lastCategory}${lastLocation ? ` in ${lastLocation}` : ""}`;
        }
        else if (lastIntent === "hotels" && lastLocation) {
            healedQuery = `cheaper hotels in ${lastLocation}`;
        }
    }
    // "better ones" → "better [product/hotel] in [location]"
    if (lowerQuery.includes("better") ||
        lowerQuery.includes("best")) {
        const lastIntent = lastSession.intent || lastSession.cardType;
        const lastCategory = lastSession.slots?.category || "";
        const lastLocation = lastSession.slots?.city || lastSession.slots?.location || "";
        if (lastIntent === "shopping" && lastCategory) {
            healedQuery = `better ${lastCategory}${lastLocation ? ` in ${lastLocation}` : ""}`;
        }
        else if (lastIntent === "hotels" && lastLocation) {
            healedQuery = `better hotels in ${lastLocation}`;
        }
    }
    // "more options" → "[product/hotel] in [location]"
    if (lowerQuery.includes("more") ||
        lowerQuery.includes("other") ||
        lowerQuery.includes("alternatives")) {
        const lastIntent = lastSession.intent || lastSession.cardType;
        const lastCategory = lastSession.slots?.category || "";
        const lastLocation = lastSession.slots?.city || lastSession.slots?.location || "";
        if (lastIntent === "shopping" && lastCategory) {
            healedQuery = `${lastCategory}${lastLocation ? ` in ${lastLocation}` : ""}`;
        }
        else if (lastIntent === "hotels" && lastLocation) {
            healedQuery = `hotels in ${lastLocation}`;
        }
    }
    // "in [location]" → fill with last location if missing
    if (lowerQuery.includes(" in ") && !lowerQuery.match(/ in [a-z]+/)) {
        const lastLocation = lastSession.slots?.city || lastSession.slots?.location || "";
        if (lastLocation) {
            healedQuery = query.replace(/ in $/, ` in ${lastLocation}`);
        }
    }
    // ✅ Use last session slots to fill missing data
    if (lastSession.slots) {
        const slots = lastSession.slots;
        // Add location if missing
        if (!lowerQuery.match(/\b(in|at|near)\s+[a-z]+\b/i) && slots.city) {
            if (!healedQuery.includes(slots.city)) {
                healedQuery = `${healedQuery} in ${slots.city}`;
            }
        }
        // Add price range if missing and query mentions price
        if ((lowerQuery.includes("cheap") || lowerQuery.includes("affordable")) &&
            slots.price && !healedQuery.includes("$")) {
            const priceNum = typeof slots.price === "number" ? slots.price : parseInt(slots.price.toString());
            if (priceNum) {
                healedQuery = `${healedQuery} under $${priceNum}`;
            }
        }
        // Add brand if missing and query mentions product
        if (slots.brand && !healedQuery.includes(slots.brand)) {
            const hasProduct = lowerQuery.match(/\b(shoes|watch|bag|phone|laptop|sneakers)\b/);
            if (hasProduct) {
                healedQuery = `${slots.brand} ${healedQuery}`;
            }
        }
        // Add category if missing
        if (slots.category && !healedQuery.includes(slots.category)) {
            const lastIntent = lastSession.intent || lastSession.cardType;
            if (lastIntent === "shopping" && !lowerQuery.match(/\b(shoes|watch|bag|phone|laptop)\b/)) {
                healedQuery = `${slots.category} ${healedQuery}`;
            }
        }
    }
    return healedQuery.trim();
}
/**
 * Extract context from session history for query enhancement
 * @param sessionHistory - Previous session(s)
 * @returns Context object with slots and intent
 */
export function extractContextFromHistory(sessionHistory) {
    if (!sessionHistory || sessionHistory.length === 0) {
        return {};
    }
    const lastSession = sessionHistory[sessionHistory.length - 1];
    return {
        intent: lastSession.intent || lastSession.cardType,
        cardType: lastSession.cardType || lastSession.intent,
        slots: lastSession.slots || {},
    };
}
