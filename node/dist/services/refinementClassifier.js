// src/services/refinementClassifier.ts
// 🚀 High-Confidence Rule-Based Refinement Detection
// Reduces LLM calls for common, unambiguous refinement patterns
// High-confidence refinement patterns
const HIGH_CONFIDENCE_PATTERNS = {
    // Price/luxury modifiers
    priceModifiers: {
        patterns: [
            /^(only|just|show|find|get)\s+(luxury|premium|high-end|expensive|costly)/i,
            /^(only|just|show|find|get)\s+(cheap|cheaper|affordable|budget|economy|low-cost)/i,
            /\b(only|just)\s+(luxury|premium|high-end|expensive|costly)\b/i,
            /\b(only|just)\s+(cheap|cheaper|affordable|budget|economy|low-cost)\b/i,
            /\b(cheaper|cheap|affordable|budget)\s+(ones?|options?|items?|hotels?|products?)\b/i,
            /\b(luxury|premium|high-end|expensive)\s+(ones?|options?|items?|hotels?|products?)\b/i,
        ],
        confidence: 0.95,
        extractModifiers: (query) => {
            const modifiers = [];
            if (/\b(luxury|premium|high-end|expensive|costly)\b/i.test(query))
                modifiers.push('luxury');
            if (/\b(cheap|cheaper|affordable|budget|economy|low-cost)\b/i.test(query))
                modifiers.push('budget');
            return modifiers;
        },
    },
    // Star ratings
    starRatings: {
        patterns: [
            /^(only|just|show|find|get)\s+(\d+)\s*[-]?\s*(star|stars)\b/i,
            /\b(only|just)\s+(\d+)\s*[-]?\s*(star|stars)\b/i,
            /\b(\d+)\s*[-]?\s*(star|stars)\s+(only|just|hotels?)\b/i,
            /\b(5|five)\s*[-]?\s*(star|stars)\b/i,
            /\b(4|four)\s*[-]?\s*(star|stars)\b/i,
            /\b(3|three)\s*[-]?\s*(star|stars)\b/i,
        ],
        confidence: 0.95,
        extractPrice: (query) => {
            const match = query.match(/\b(\d+)\s*[-]?\s*(star|stars)\b/i);
            return match ? `${match[1]} star` : null;
        },
    },
    // Location refinements
    locationRefinements: {
        patterns: [
            /^(near|close to|around)\s+(airport|downtown|beach|center|centre|city center|city centre)/i,
            /\b(near|close to|around)\s+(airport|downtown|beach|center|centre|city center|city centre)\b/i,
            /\b(near|close to|around)\s+([a-zA-Z][a-zA-Z\s]{2,})\b/i, // Generic location
        ],
        confidence: 0.90,
        extractLocation: (query) => {
            const match = query.match(/\b(near|close to|around)\s+([a-zA-Z][a-zA-Z\s]{2,})\b/i);
            return match ? match[2].trim() : null;
        },
    },
    // Vague refinements (high confidence if parent context exists)
    vagueRefinements: {
        patterns: [
            /^(only|just|show|find|get|give me|i want|i need)\s+(more|less|the|ones?|these|those|it|them)\b/i,
            /^(only|just|more|less|the|ones?|these|those|it|them)$/i,
            /\b(only|just)\s+(more|less|the|ones?|these|those|it|them)\b/i,
        ],
        confidence: 0.85, // Lower confidence - needs parent context
        isVague: true,
    },
};
/**
 * Rule-based context extraction with confidence scoring
 */
export function extractContextWithRules(query, parentQuery) {
    const lowerQuery = query.toLowerCase().trim();
    let maxConfidence = 0;
    let bestMatch = null;
    let matchedPattern = null;
    // Check price/luxury modifiers
    for (const pattern of HIGH_CONFIDENCE_PATTERNS.priceModifiers.patterns) {
        if (pattern.test(query)) {
            const modifiers = HIGH_CONFIDENCE_PATTERNS.priceModifiers.extractModifiers(query);
            const price = modifiers.includes('luxury') ? 'luxury' : modifiers.includes('budget') ? 'budget' : null;
            bestMatch = {
                brand: null,
                category: null,
                price: price || null,
                city: null,
                location: null,
                intent: null,
                modifiers: modifiers,
                isRefinement: true,
                needsParentContext: !parentQuery || !extractLocationFromQuery(query),
            };
            maxConfidence = HIGH_CONFIDENCE_PATTERNS.priceModifiers.confidence;
            matchedPattern = 'priceModifiers';
            break; // High confidence, use first match
        }
    }
    // Check star ratings
    if (maxConfidence < 0.95) {
        for (const pattern of HIGH_CONFIDENCE_PATTERNS.starRatings.patterns) {
            if (pattern.test(query)) {
                const price = HIGH_CONFIDENCE_PATTERNS.starRatings.extractPrice(query);
                bestMatch = {
                    brand: null,
                    category: null,
                    price: price,
                    city: null,
                    location: null,
                    intent: null,
                    modifiers: price ? [price] : [],
                    isRefinement: true,
                    needsParentContext: !parentQuery || !extractLocationFromQuery(query),
                };
                maxConfidence = HIGH_CONFIDENCE_PATTERNS.starRatings.confidence;
                matchedPattern = 'starRatings';
                break;
            }
        }
    }
    // Check location refinements
    if (maxConfidence < 0.90) {
        for (const pattern of HIGH_CONFIDENCE_PATTERNS.locationRefinements.patterns) {
            if (pattern.test(query)) {
                const location = HIGH_CONFIDENCE_PATTERNS.locationRefinements.extractLocation(query);
                bestMatch = {
                    brand: null,
                    category: null,
                    price: null,
                    city: location ? normalizeLocation(location) : null,
                    location: location ? normalizeLocation(location) : null,
                    intent: null,
                    modifiers: [],
                    isRefinement: true,
                    needsParentContext: false, // Has location, doesn't need parent
                };
                maxConfidence = HIGH_CONFIDENCE_PATTERNS.locationRefinements.confidence;
                matchedPattern = 'locationRefinements';
                break;
            }
        }
    }
    // Check vague refinements (lower confidence, needs parent)
    if (maxConfidence < 0.85 && parentQuery) {
        for (const pattern of HIGH_CONFIDENCE_PATTERNS.vagueRefinements.patterns) {
            if (pattern.test(query)) {
                bestMatch = {
                    brand: null,
                    category: null,
                    price: null,
                    city: null,
                    location: null,
                    intent: null,
                    modifiers: [],
                    isRefinement: true,
                    needsParentContext: true, // Vague, needs parent context
                };
                maxConfidence = HIGH_CONFIDENCE_PATTERNS.vagueRefinements.confidence;
                matchedPattern = 'vagueRefinements';
                break;
            }
        }
    }
    // If we have a high-confidence match, return it
    if (bestMatch && maxConfidence >= 0.85) {
        return {
            extractedContext: bestMatch,
            confidence: maxConfidence,
            method: 'rules',
        };
    }
    return null; // No high-confidence match, use LLM
}
/**
 * Extract location from query (helper)
 */
function extractLocationFromQuery(query) {
    return /\b(in|at|near|from|to|close to|around)\s+[a-zA-Z][a-zA-Z\s]{2,}/i.test(query);
}
/**
 * Normalize location name
 */
function normalizeLocation(location) {
    return location
        .split(/\s+/)
        .map(word => word.charAt(0).toUpperCase() + word.slice(1).toLowerCase())
        .join(' ');
}
/**
 * Merge query using rule-based logic (when confidence is high)
 */
export function mergeQueryWithRules(currentQuery, parentQuery, extractedContext, intent) {
    // Import here to avoid circular dependency
    const { analyzeCardNeed } = require("../followup/cardAnalyzer");
    const parentSlots = analyzeCardNeed(parentQuery);
    const qLower = currentQuery.toLowerCase();
    let merged = currentQuery;
    // Merge brand if parent has it and follow-up doesn't
    if (parentSlots.brand && !qLower.includes(parentSlots.brand.toLowerCase())) {
        merged = `${parentSlots.brand} ${merged}`;
    }
    // Merge category if parent has it and follow-up doesn't
    if (parentSlots.category && !qLower.includes(parentSlots.category.toLowerCase())) {
        merged = `${merged} ${parentSlots.category}`;
    }
    // Merge city ONLY if:
    // 1. Current query doesn't have any location
    // 2. Current query doesn't explicitly mention a DIFFERENT location
    // 3. It's a travel intent
    // 4. Query is a refinement (needs parent context)
    const isTravelIntent = ["hotels", "flights", "restaurants", "places", "location"].includes(intent);
    const hasLocationInQuery = /\b(in|at|near|from|to)\s+[a-zA-Z][a-zA-Z\s]{2,}/i.test(currentQuery);
    const hasDifferentLocation = hasLocationInQuery &&
        parentSlots.city &&
        !qLower.includes(parentSlots.city.toLowerCase());
    if (parentSlots.city && !hasDifferentLocation) {
        if ((isTravelIntent && (extractedContext.isRefinement || !hasLocationInQuery))) {
            if (!qLower.includes(parentSlots.city.toLowerCase())) {
                merged = `${merged} in ${parentSlots.city}`;
            }
        }
    }
    // Don't merge price from parent if extracted context already has price modifier
    // The extracted context's price takes precedence
    if (!extractedContext.price && parentSlots.price && !qLower.includes(parentSlots.price.toLowerCase())) {
        merged = `${merged} ${parentSlots.price}`;
    }
    return merged.trim();
}
