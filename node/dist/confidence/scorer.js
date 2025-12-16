// ✅ PHASE 9: Confidence Scorer
// Computes confidence scores for intents, slots, and cards
/**
 * Compute intent confidence score (0-1)
 * @param query - User query
 * @param detectedIntent - Detected intent
 * @param alternativeIntents - Alternative intents considered
 * @returns Confidence score (0-1)
 */
export function computeIntentConfidence(query, detectedIntent, alternativeIntents) {
    const lowerQuery = query.toLowerCase();
    const lowerIntent = detectedIntent.toLowerCase();
    let confidence = 0.5; // Base confidence
    // ✅ Strong keyword matches increase confidence
    const strongKeywords = {
        shopping: ["buy", "purchase", "price", "shop", "product", "brand"],
        hotels: ["hotel", "resort", "accommodation", "stay", "book"],
        flights: ["flight", "airline", "airport", "departure", "arrival"],
        restaurants: ["restaurant", "food", "eat", "dining", "cafe", "cuisine"],
        places: ["places", "attractions", "things to do", "visit", "tourist"],
        movies: ["movie", "film", "cinema", "theater", "watch movie"],
    };
    const keywords = strongKeywords[lowerIntent] || [];
    const keywordMatches = keywords.filter(kw => lowerQuery.includes(kw)).length;
    confidence += keywordMatches * 0.1; // +0.1 per keyword match
    // ✅ Brand/product matches for shopping
    if (lowerIntent === "shopping") {
        const brands = ["nike", "adidas", "gucci", "puma", "apple", "samsung"];
        const hasBrand = brands.some(brand => lowerQuery.includes(brand));
        if (hasBrand)
            confidence += 0.2;
    }
    // ✅ Location matches for places/hotels
    if (lowerIntent === "places" || lowerIntent === "hotels") {
        const locationPattern = /\b(in|at|near|from|to)\s+[a-z]+\b/i;
        if (locationPattern.test(query)) {
            confidence += 0.15;
        }
    }
    // ✅ Penalize if alternative intents are strong
    if (alternativeIntents && alternativeIntents.length > 0) {
        const alternativeConfidence = alternativeIntents
            .map(alt => computeIntentConfidence(query, alt))
            .reduce((max, conf) => Math.max(max, conf), 0);
        if (alternativeConfidence > confidence) {
            confidence -= 0.2; // Reduce confidence if alternatives are strong
        }
    }
    // ✅ Query length affects confidence (very short queries are less confident)
    if (query.length < 5) {
        confidence -= 0.2;
    }
    else if (query.length > 20) {
        confidence += 0.1; // Longer queries are more specific
    }
    return Math.max(0, Math.min(1, confidence)); // Clamp to [0, 1]
}
/**
 * Compute slot confidence score (0-1)
 * @param slots - Extracted slots
 * @param intent - Detected intent
 * @returns Confidence score (0-1)
 */
export function computeSlotConfidence(slots, intent) {
    if (!slots || Object.keys(slots).length === 0) {
        return 0;
    }
    let confidence = 0;
    const lowerIntent = intent.toLowerCase();
    // ✅ Location/city slot
    if (slots.location || slots.city) {
        confidence += 0.3;
    }
    // ✅ Intent-specific slots
    if (lowerIntent === "shopping") {
        if (slots.category)
            confidence += 0.2;
        if (slots.brand)
            confidence += 0.2;
        if (slots.priceRange)
            confidence += 0.2;
    }
    else if (lowerIntent === "hotels" || lowerIntent === "flights") {
        if (slots.dates)
            confidence += 0.3;
        if (slots.peopleCount)
            confidence += 0.2;
    }
    else if (lowerIntent === "restaurants") {
        if (slots.intentSpecific?.cuisine)
            confidence += 0.2;
        if (slots.intentSpecific?.mealType)
            confidence += 0.1;
    }
    // ✅ Price range slot (universal)
    if (slots.priceRange) {
        confidence += 0.1;
    }
    return Math.max(0, Math.min(1, confidence)); // Clamp to [0, 1]
}
/**
 * Compute card confidence score (0-1)
 * @param card - Card object
 * @param intent - Detected intent
 * @returns Confidence score (0-1)
 */
export function computeCardConfidence(card, intent) {
    if (!card || typeof card !== "object") {
        return 0;
    }
    let confidence = 0.3; // Base confidence for having a card
    const lowerIntent = intent.toLowerCase();
    // ✅ Essential fields
    if (card.title || card.name)
        confidence += 0.2;
    if (card.description)
        confidence += 0.1;
    // ✅ Intent-specific fields
    if (lowerIntent === "shopping") {
        if (card.price)
            confidence += 0.2;
        if (card.brand)
            confidence += 0.1;
        if (card.rating)
            confidence += 0.1;
        if (card.images && Array.isArray(card.images) && card.images.length > 0) {
            confidence += 0.1;
        }
    }
    else if (lowerIntent === "hotels") {
        if (card.rating || card.overall_rating)
            confidence += 0.2;
        if (card.address)
            confidence += 0.1;
        if (card.latitude && card.longitude)
            confidence += 0.1;
        if (card.amenities && Array.isArray(card.amenities)) {
            confidence += 0.1;
        }
    }
    else if (lowerIntent === "restaurants") {
        if (card.rating)
            confidence += 0.2;
        if (card.cuisine)
            confidence += 0.1;
        if (card.address)
            confidence += 0.1;
    }
    else if (lowerIntent === "places") {
        if (card.description)
            confidence += 0.2;
        if (card.latitude && card.longitude)
            confidence += 0.1;
        if (card.rating)
            confidence += 0.1;
    }
    else if (lowerIntent === "flights") {
        if (card.airline)
            confidence += 0.2;
        if (card.departure && card.arrival)
            confidence += 0.2;
        if (card.price)
            confidence += 0.1;
    }
    // ✅ Source quality
    if (card.source) {
        const source = card.source.toLowerCase();
        if (source.includes("official") || source.includes("verified")) {
            confidence += 0.1;
        }
    }
    // ✅ Penalize incomplete cards
    if (!card.title && !card.name && !card.description) {
        confidence = 0;
    }
    return Math.max(0, Math.min(1, confidence)); // Clamp to [0, 1]
}
/**
 * Compute overall response confidence
 * @param intentConfidence - Intent confidence score
 * @param slotConfidence - Slot confidence score
 * @param cardConfidences - Array of card confidence scores
 * @returns Overall confidence score (0-1)
 */
export function computeOverallConfidence(intentConfidence, slotConfidence, cardConfidences) {
    // Weighted average
    const intentWeight = 0.4;
    const slotWeight = 0.2;
    const cardWeight = 0.4;
    const avgCardConfidence = cardConfidences.length > 0
        ? cardConfidences.reduce((sum, conf) => sum + conf, 0) / cardConfidences.length
        : 0;
    const overall = intentConfidence * intentWeight +
        slotConfidence * slotWeight +
        avgCardConfidence * cardWeight;
    return Math.max(0, Math.min(1, overall)); // Clamp to [0, 1]
}
