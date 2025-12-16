// ✅ PHASE 9: Card Relevance Filter
// Removes irrelevant cards and empty cards
/**
 * Filter out irrelevant cards based on intent
 * @param intent - Primary intent
 * @param cards - Array of cards to filter
 * @param secondaryIntents - Optional secondary intents
 * @returns Filtered array of relevant cards
 */
export function filterOutIrrelevantCards(intent, cards, secondaryIntents) {
    if (!Array.isArray(cards) || cards.length === 0) {
        return [];
    }
    const filtered = [];
    const lowerIntent = intent.toLowerCase();
    for (const card of cards) {
        // ✅ Remove empty cards
        if (!card || typeof card !== "object") {
            continue;
        }
        // Check if card has essential fields
        const hasTitle = card.title || card.name || card.description;
        if (!hasTitle) {
            continue;
        }
        // ✅ Remove cards not matching primary or secondary intents
        let isRelevant = false;
        // Check against primary intent
        if (lowerIntent === "shopping") {
            // Shopping cards should have price, product info, or shopping-related fields
            isRelevant = !!(card.price ||
                card.title ||
                card.name ||
                card.brand ||
                card.category ||
                card.source?.includes("shop") ||
                card.source?.includes("amazon") ||
                card.source?.includes("ebay"));
        }
        else if (lowerIntent === "hotels") {
            // Hotel cards should have hotel-related fields
            isRelevant = !!(card.name ||
                card.title ||
                card.rating ||
                card.address ||
                card.latitude ||
                card.longitude ||
                card.type === "hotel" ||
                card.type === "lodging" ||
                card.source?.includes("hotel") ||
                card.source?.includes("booking"));
        }
        else if (lowerIntent === "flights") {
            // Flight cards should have flight-related fields
            isRelevant = !!(card.airline ||
                card.departure ||
                card.arrival ||
                card.price ||
                card.type === "flight" ||
                card.source?.includes("flight") ||
                card.source?.includes("airline"));
        }
        else if (lowerIntent === "restaurants") {
            // Restaurant cards should have restaurant-related fields
            isRelevant = !!(card.name ||
                card.title ||
                card.rating ||
                card.cuisine ||
                card.address ||
                card.type === "restaurant" ||
                card.type === "food" ||
                card.source?.includes("restaurant") ||
                card.source?.includes("yelp"));
        }
        else if (lowerIntent === "places") {
            // Place cards should have location-related fields
            isRelevant = !!(card.title ||
                card.name ||
                card.description ||
                card.address ||
                card.latitude ||
                card.longitude ||
                card.type === "place" ||
                card.type === "attraction" ||
                card.source?.includes("place") ||
                card.source?.includes("tripadvisor"));
        }
        else {
            // For other intents, accept any card with basic info
            isRelevant = !!(card.title || card.name || card.description);
        }
        // Check against secondary intents if provided
        if (!isRelevant && secondaryIntents && secondaryIntents.length > 0) {
            for (const secondaryIntent of secondaryIntents) {
                const lowerSecondary = secondaryIntent.toLowerCase();
                if (lowerSecondary === "shopping" && (card.price || card.brand)) {
                    isRelevant = true;
                    break;
                }
                if (lowerSecondary === "hotels" && (card.rating || card.address)) {
                    isRelevant = true;
                    break;
                }
                if (lowerSecondary === "places" && (card.latitude || card.longitude)) {
                    isRelevant = true;
                    break;
                }
            }
        }
        if (isRelevant) {
            filtered.push(card);
        }
    }
    return filtered;
}
/**
 * Remove duplicate cards based on title/name
 * @param cards - Array of cards
 * @returns Array with duplicates removed
 */
export function removeDuplicateCards(cards) {
    if (!Array.isArray(cards) || cards.length === 0) {
        return [];
    }
    const seen = new Set();
    const unique = [];
    for (const card of cards) {
        const identifier = (card.title || card.name || card.id || JSON.stringify(card)).toLowerCase().trim();
        if (!seen.has(identifier)) {
            seen.add(identifier);
            unique.push(card);
        }
    }
    return unique;
}
/**
 * Validate card structure
 * @param card - Card to validate
 * @returns true if card is valid
 */
export function isValidCard(card) {
    if (!card || typeof card !== "object") {
        return false;
    }
    // Must have at least one of: title, name, description
    const hasContent = !!(card.title || card.name || card.description);
    if (!hasContent) {
        return false;
    }
    // Check for obviously invalid data
    if (card.title === "[object Object]" || card.name === "[object Object]") {
        return false;
    }
    return true;
}
