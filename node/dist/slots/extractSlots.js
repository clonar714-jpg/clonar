// ✅ PHASE 8: Slot Extraction Engine
// Extracts structured parameters from queries
/**
 * Extract slots from query
 * @param query - User query
 * @param intent - Detected intent for context
 * @returns Extracted slots
 */
export function extractSlots(query, intent) {
    const lowerQuery = query.toLowerCase().trim();
    const slots = {};
    // ✅ Extract location/city
    const locationMatch = lowerQuery.match(/\b(in|at|near|from|to)\s+([a-z\s]+?)(?:\s|$|,|\.)/i);
    if (locationMatch) {
        const location = locationMatch[2].trim();
        // Filter out common stop words
        const stopWords = ["the", "a", "an", "and", "or", "but", "in", "on", "at", "to", "for", "of", "with"];
        const locationWords = location.split(" ").filter(w => !stopWords.includes(w.toLowerCase()));
        if (locationWords.length > 0) {
            slots.location = locationWords.join(" ");
            slots.city = slots.location;
        }
    }
    // ✅ Extract price range
    const pricePatterns = [
        /\b(under|below|less than|max)\s*\$?(\d+)/i,
        /\b(over|above|more than|min)\s*\$?(\d+)/i,
        /\$\s*(\d+)\s*(?:to|-|and)\s*\$?\s*(\d+)/i,
        /\b(\d+)\s*(?:to|-|and)\s*(\d+)\s*(?:dollars?|usd|price)/i,
    ];
    for (const pattern of pricePatterns) {
        const match = lowerQuery.match(pattern);
        if (match) {
            if (match[1] && (match[1].toLowerCase().includes("under") || match[1].toLowerCase().includes("below"))) {
                slots.priceRange = {
                    max: parseInt(match[2]),
                    currency: "USD",
                };
            }
            else if (match[1] && (match[1].toLowerCase().includes("over") || match[1].toLowerCase().includes("above"))) {
                slots.priceRange = {
                    min: parseInt(match[2]),
                    currency: "USD",
                };
            }
            else if (match[1] && match[2]) {
                slots.priceRange = {
                    min: parseInt(match[1]),
                    max: parseInt(match[2]),
                    currency: "USD",
                };
            }
            break;
        }
    }
    // ✅ Extract dates (for hotels/flights)
    if (intent === "hotels" || intent === "flights") {
        const datePatterns = [
            /\b(check\s*in|arrival|from)\s*:?\s*(\d{1,2}[\/\-]\d{1,2}[\/\-]?\d{0,4})/i,
            /\b(check\s*out|departure|to|return)\s*:?\s*(\d{1,2}[\/\-]\d{1,2}[\/\-]?\d{0,4})/i,
            /\b(\d{1,2}[\/\-]\d{1,2})\s*(?:to|-|and)\s*(\d{1,2}[\/\-]\d{1,2})/i,
        ];
        const dates = {};
        for (const pattern of datePatterns) {
            const match = lowerQuery.match(pattern);
            if (match) {
                if (match[1] && (match[1].toLowerCase().includes("check in") || match[1].toLowerCase().includes("arrival"))) {
                    dates.checkIn = match[2];
                }
                else if (match[1] && (match[1].toLowerCase().includes("check out") || match[1].toLowerCase().includes("departure"))) {
                    dates.checkOut = match[2];
                }
                else if (match[1] && match[2]) {
                    dates.checkIn = match[1];
                    dates.checkOut = match[2];
                }
            }
        }
        if (Object.keys(dates).length > 0) {
            slots.dates = dates;
        }
    }
    // ✅ Extract category (for shopping)
    if (intent === "shopping") {
        const categories = [
            "shoes", "sneakers", "boots", "sandals", "heels",
            "watch", "watches", "timepiece",
            "bag", "bags", "purse", "handbag", "backpack",
            "glasses", "sunglasses", "eyewear",
            "shirt", "shirts", "dress", "dresses", "hoodie",
            "jeans", "pants", "shorts", "jacket", "coat",
            "phone", "smartphone", "laptop", "tablet", "headphones",
            "camera", "tv", "television", "speaker",
        ];
        for (const category of categories) {
            const regex = new RegExp(`\\b${category}\\b`, "i");
            if (regex.test(lowerQuery)) {
                slots.category = category;
                break;
            }
        }
    }
    // ✅ Extract brand
    const brands = [
        "michael kors", "mk", "gucci", "puma", "nike", "adidas", "reebok",
        "balmain", "rayban", "ray-ban", "oakley", "gap", "prada", "versace",
        "apple", "samsung", "sony", "canon", "dyson", "dior", "chanel",
        "louis vuitton", "lv", "hermes", "burberry", "tiffany", "cartier",
        "rolex", "omega", "tag heuer", "fossil", "seiko", "citizen",
    ];
    for (const brand of brands) {
        const regex = new RegExp(`\\b${brand.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\b`, "i");
        if (regex.test(lowerQuery)) {
            slots.brand = brand;
            break;
        }
    }
    // ✅ Extract people count
    const peopleMatch = lowerQuery.match(/\b(for|with)\s+(\d+)\s*(?:people|person|guest|adult)/i);
    if (peopleMatch) {
        slots.peopleCount = parseInt(peopleMatch[2]);
    }
    // ✅ Intent-specific parameters
    slots.intentSpecific = {};
    if (intent === "hotels") {
        // Extract hotel-specific slots
        if (lowerQuery.includes("luxury") || lowerQuery.includes("5 star")) {
            slots.intentSpecific.rating = 5;
        }
        else if (lowerQuery.includes("budget") || lowerQuery.includes("cheap")) {
            slots.intentSpecific.rating = 2;
        }
        if (lowerQuery.includes("pool")) {
            slots.intentSpecific.amenities = ["pool"];
        }
        if (lowerQuery.includes("spa")) {
            slots.intentSpecific.amenities = [...(slots.intentSpecific.amenities || []), "spa"];
        }
    }
    if (intent === "flights") {
        // Extract flight-specific slots
        const fromMatch = lowerQuery.match(/\bfrom\s+([a-z\s]+?)(?:\s+to|\s|$)/i);
        const toMatch = lowerQuery.match(/\bto\s+([a-z\s]+?)(?:\s|$|,|\.)/i);
        if (fromMatch) {
            slots.intentSpecific.from = fromMatch[1].trim();
        }
        if (toMatch) {
            slots.intentSpecific.to = toMatch[1].trim();
        }
    }
    if (intent === "restaurants") {
        // Extract restaurant-specific slots
        if (lowerQuery.includes("breakfast")) {
            slots.intentSpecific.mealType = "breakfast";
        }
        else if (lowerQuery.includes("lunch")) {
            slots.intentSpecific.mealType = "lunch";
        }
        else if (lowerQuery.includes("dinner")) {
            slots.intentSpecific.mealType = "dinner";
        }
        const cuisineMatch = lowerQuery.match(/\b(italian|chinese|japanese|thai|mexican|indian|french|american)\b/i);
        if (cuisineMatch) {
            slots.intentSpecific.cuisine = cuisineMatch[1].toLowerCase();
        }
    }
    return slots;
}
