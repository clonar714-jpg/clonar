// ✅ PHASE 9: Query Repair Engine
// Expands vague phrases, adds missing context, rewrites ambiguous queries
/**
 * Repair user query by expanding vague phrases and adding missing context
 * @param query - Original user query
 * @param slots - Extracted slots for context
 * @param intent - Detected intent
 * @returns Repaired, complete query
 */
export function repairUserQuery(query, slots, intent) {
    let repaired = query.trim();
    const lowerQuery = repaired.toLowerCase();
    // ✅ Expand vague phrases into complete queries
    const vaguePhrases = {
        "cheaper ones": "cheaper options",
        "better ones": "better options",
        "more options": "more choices",
        "similar": "similar items",
        "like this": "items like this",
        "nearby": "places nearby",
        "around here": "places around here",
        "best": "best options",
        "top": "top choices",
        "good": "good options",
    };
    for (const [vague, expanded] of Object.entries(vaguePhrases)) {
        if (lowerQuery === vague || lowerQuery.endsWith(` ${vague}`)) {
            repaired = repaired.replace(new RegExp(vague, "i"), expanded);
        }
    }
    // ✅ Add missing context from slots
    if (slots) {
        // Add location if missing and slot has it
        if (slots.location || slots.city) {
            const location = slots.location || slots.city;
            if (location && !lowerQuery.includes(location.toLowerCase())) {
                // Check if query already has a location indicator
                if (!lowerQuery.match(/\b(in|at|near|from|to)\s+[a-z]+\b/i)) {
                    repaired = `${repaired} in ${location}`;
                }
            }
        }
        // Add category if missing and slot has it
        if (slots.category && !lowerQuery.includes(slots.category.toLowerCase())) {
            // Only add if query doesn't already have a product term
            const hasProductTerm = /\b(shoes|watch|bag|phone|laptop|sneakers|glasses|shirt|dress)\b/i.test(repaired);
            if (!hasProductTerm) {
                repaired = `${slots.category} ${repaired}`;
            }
        }
        // Add brand if missing and slot has it
        if (slots.brand && !lowerQuery.includes(slots.brand.toLowerCase())) {
            // Only add if query doesn't already have a brand
            const hasBrand = /\b(nike|adidas|gucci|puma|apple|samsung|michael kors|rolex)\b/i.test(repaired);
            if (!hasBrand) {
                repaired = `${slots.brand} ${repaired}`;
            }
        }
        // Add price range if missing and slot has it
        if (slots.priceRange) {
            if (slots.priceRange.max && !lowerQuery.includes("under") && !lowerQuery.includes("below")) {
                repaired = `${repaired} under $${slots.priceRange.max}`;
            }
            else if (slots.priceRange.min && !lowerQuery.includes("over") && !lowerQuery.includes("above")) {
                repaired = `${repaired} over $${slots.priceRange.min}`;
            }
        }
        // Add dates for hotels/flights if missing
        if ((intent === "hotels" || intent === "flights") && slots.dates) {
            if (slots.dates.checkIn && !lowerQuery.includes("check in") && !lowerQuery.includes("from")) {
                repaired = `${repaired} check in ${slots.dates.checkIn}`;
            }
            if (slots.dates.checkOut && !lowerQuery.includes("check out") && !lowerQuery.includes("to")) {
                repaired = `${repaired} check out ${slots.dates.checkOut}`;
            }
        }
        // Add people count if missing
        if (slots.peopleCount && !lowerQuery.includes("people") && !lowerQuery.includes("guests")) {
            repaired = `${repaired} for ${slots.peopleCount} people`;
        }
    }
    // ✅ Rewrite ambiguous queries into precise ones
    // Pattern 1: "show me X" → "best X" or "hotels X"
    const showMeMatch = repaired.match(/^(show|find|get|give)\s+me\s+(.+)$/i);
    if (showMeMatch && showMeMatch[2]) {
        const rest = showMeMatch[2];
        if (intent === "shopping") {
            repaired = `best ${rest}`;
        }
        else if (intent === "hotels") {
            repaired = `hotels ${rest}`;
        }
        else if (intent === "places") {
            repaired = `places to visit ${rest}`;
        }
        else {
            repaired = rest;
        }
    }
    // Pattern 2: "what about X" → "best X" or "hotels X"
    const whatAboutMatch = repaired.match(/^what.*about\s+(.+)$/i);
    if (whatAboutMatch && whatAboutMatch[1]) {
        const rest = whatAboutMatch[1];
        if (intent === "shopping") {
            repaired = `best ${rest}`;
        }
        else if (intent === "hotels") {
            repaired = `hotels ${rest}`;
        }
        else {
            repaired = rest;
        }
    }
    // Pattern 3: "i want X" → "X"
    const iWantMatch = repaired.match(/^(i want|i need|i'm looking for)\s+(.+)$/i);
    if (iWantMatch && iWantMatch[2]) {
        repaired = iWantMatch[2];
    }
    // ✅ Ensure proper grammar and structure
    // Capitalize first letter
    if (repaired.length > 0) {
        repaired = repaired.charAt(0).toUpperCase() + repaired.slice(1);
    }
    // Remove extra spaces
    repaired = repaired.replace(/\s{2,}/g, " ").trim();
    // Remove trailing punctuation if not a question
    if (repaired.endsWith(".") && !repaired.includes("?")) {
        repaired = repaired.slice(0, -1);
    }
    // ✅ Intent-specific repairs
    if (intent === "places") {
        // Ensure "places" queries have proper structure
        if (!lowerQuery.includes("places") && !lowerQuery.includes("attractions") && !lowerQuery.includes("things to do")) {
            if (!repaired.toLowerCase().includes("places")) {
                repaired = `places to visit ${repaired}`;
            }
        }
    }
    if (intent === "hotels") {
        // Ensure hotel queries mention "hotel" or "accommodation"
        if (!lowerQuery.includes("hotel") && !lowerQuery.includes("resort") && !lowerQuery.includes("accommodation")) {
            repaired = `hotels ${repaired}`;
        }
    }
    if (intent === "shopping") {
        // Ensure shopping queries have product context
        const hasProduct = /\b(shoes|watch|bag|phone|laptop|sneakers|glasses|shirt|dress|product)\b/i.test(repaired);
        if (!hasProduct && slots.category) {
            repaired = `${slots.category} ${repaired}`;
        }
    }
    return repaired.trim();
}
/**
 * Check if query needs repair
 * @param query - User query
 * @returns true if query is vague or ambiguous
 */
export function needsRepair(query) {
    const lower = query.toLowerCase().trim();
    const vagueIndicators = [
        "cheaper ones",
        "better ones",
        "more options",
        "similar",
        "like this",
        "nearby",
        "around here",
        "show me",
        "find me",
        "what about",
        "i want",
        "i need",
    ];
    return vagueIndicators.some(indicator => lower.includes(indicator)) || lower.length < 5;
}
