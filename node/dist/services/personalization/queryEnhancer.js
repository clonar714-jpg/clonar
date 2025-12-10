/**
 * Phase 2: Query Enhancement with User Preferences
 * Intelligently enhances queries with user preferences from database
 */
import { getUserPreferences } from "./preferenceStorage";
/**
 * Enhance query with user preferences
 * Only enhances when preferences are relevant and don't conflict with query
 */
export async function enhanceQueryWithPreferences(query, userId, options) {
    // Skip if invalid user ID
    if (!userId || userId === "global" || userId === "dev-user-id") {
        return query;
    }
    // Skip if not a relevant intent
    const relevantIntents = ["shopping", "hotels", "restaurants", "flights", "places", "movies"];
    if (!relevantIntents.includes(options.intent)) {
        return query;
    }
    try {
        // Load user preferences
        const userPrefs = await getUserPreferences(userId);
        if (!userPrefs) {
            return query;
        }
        // Check confidence threshold
        const minConfidence = options.minConfidence || 0.3;
        if (!userPrefs.confidence_score || userPrefs.confidence_score < minConfidence) {
            return query;
        }
        const queryLower = query.toLowerCase();
        let enhancedQuery = query;
        // 1. Add brand preferences (for shopping)
        // Only add if:
        // - Query doesn't already mention a brand
        // - Query is general/vague (not very specific)
        // - User has strong brand preference (confidence >= 0.4)
        if (options.intent === "shopping" && userPrefs.brand_preferences && userPrefs.brand_preferences.length > 0) {
            // Check if query already mentions any brand (from preferences or common brands)
            const commonBrands = ["nike", "adidas", "puma", "prada", "gucci", "rolex", "apple", "samsung"];
            const hasBrand = userPrefs.brand_preferences.some(brand => queryLower.includes(brand.toLowerCase())) || commonBrands.some(brand => queryLower.includes(brand));
            // Check if query is specific enough (has 3+ words usually means user knows what they want)
            const queryWords = query.split(/\s+/).filter(w => w.length > 0);
            const isVagueQuery = queryWords.length <= 2;
            if (!hasBrand && (isVagueQuery || userPrefs.confidence_score >= 0.5)) {
                // Add top brand preference
                const topBrand = userPrefs.brand_preferences[0];
                enhancedQuery = `${topBrand} ${enhancedQuery}`;
                console.log(`🎯 Enhanced with brand preference: "${query}" → "${enhancedQuery}"`);
            }
        }
        // 2. Add style keywords (if user has strong style preference)
        // Only add if:
        // - Query doesn't already mention style
        // - User has strong style preference (confidence >= 0.5)
        // - Style is relevant to intent (luxury/budget for shopping/hotels)
        if (userPrefs.style_keywords && userPrefs.style_keywords.length > 0) {
            const topStyle = userPrefs.style_keywords[0];
            const styleKeywords = ["luxury", "budget", "premium", "affordable", "cheap", "expensive", "modern", "vintage", "classic"];
            const hasStyle = queryLower.includes(topStyle.toLowerCase()) ||
                styleKeywords.some(keyword => queryLower.includes(keyword));
            if (!hasStyle && userPrefs.confidence_score >= 0.5) {
                // Only add style for shopping and hotels (not for flights/restaurants unless very strong)
                if (options.intent === "shopping" || options.intent === "hotels" || userPrefs.confidence_score >= 0.7) {
                    enhancedQuery = `${enhancedQuery} ${topStyle}`;
                    console.log(`🎯 Enhanced with style preference: "${query}" → "${enhancedQuery}"`);
                }
            }
        }
        // 3. Add price range (for shopping only, and only if user hasn't specified price)
        // Only add if:
        // - Query doesn't already mention price
        // - User has strong price preference (confidence >= 0.6, since price is more sensitive)
        // - Query is vague (user might want price guidance)
        if (options.intent === "shopping" && userPrefs.price_range_max) {
            const hasPrice = /(under|below|less than|max|maximum|up to|above|over|more than|min|minimum|from)\s*\$?\d+/i.test(query);
            const queryWords = query.split(/\s+/).filter(w => w.length > 0);
            const isVagueQuery = queryWords.length <= 3;
            if (!hasPrice && isVagueQuery && userPrefs.confidence_score >= 0.6) {
                // Only add price if it's a very strong preference (price is sensitive)
                enhancedQuery = `${enhancedQuery} under $${userPrefs.price_range_max}`;
                console.log(`🎯 Enhanced with price preference: "${query}" → "${enhancedQuery}"`);
            }
        }
        // 4. Apply category-specific preferences
        if (options.category && userPrefs.category_preferences) {
            const categoryPrefs = userPrefs.category_preferences;
            const categoryLower = options.category.toLowerCase();
            // Find matching category preference
            for (const [cat, prefs] of Object.entries(categoryPrefs)) {
                if (categoryLower.includes(cat.toLowerCase()) || cat.toLowerCase().includes(categoryLower)) {
                    // Add category-specific brand
                    if (prefs.brands && Array.isArray(prefs.brands) && prefs.brands.length > 0) {
                        const topBrand = prefs.brands[0];
                        if (!enhancedQuery.toLowerCase().includes(topBrand.toLowerCase())) {
                            enhancedQuery = `${topBrand} ${enhancedQuery}`;
                            console.log(`🎯 Enhanced with category brand preference: "${query}" → "${enhancedQuery}"`);
                        }
                    }
                    // Add category-specific style
                    if (prefs.style && !enhancedQuery.toLowerCase().includes(prefs.style.toLowerCase())) {
                        enhancedQuery = `${enhancedQuery} ${prefs.style}`;
                        console.log(`🎯 Enhanced with category style preference: "${query}" → "${enhancedQuery}"`);
                    }
                    // Add category-specific rating (for hotels/restaurants)
                    if ((options.intent === "hotels" || options.intent === "restaurants") && prefs.rating_min) {
                        const hasRating = /\d+\s*star/i.test(query);
                        if (!hasRating) {
                            enhancedQuery = `${enhancedQuery} ${prefs.rating_min} star`;
                            console.log(`🎯 Enhanced with category rating preference: "${query}" → "${enhancedQuery}"`);
                        }
                    }
                    break; // Only apply first matching category
                }
            }
        }
        return enhancedQuery;
    }
    catch (err) {
        console.error(`❌ Error enhancing query with preferences: ${err.message}`);
        // Return original query on error
        return query;
    }
}
/**
 * Extract category from query (for category-specific preferences)
 */
export function extractCategoryFromQuery(query, intent) {
    const queryLower = query.toLowerCase();
    // Shopping categories
    if (intent === "shopping") {
        const shoppingCategories = [
            "glasses", "sunglasses", "eyewear",
            "shoes", "sneakers", "boots",
            "watch", "watches", "timepiece",
            "bag", "purse", "backpack", "handbag",
            "shirt", "tshirt", "t-shirt", "top",
            "dress", "pants", "jeans",
            "laptop", "phone", "smartphone",
            "headphones", "earbuds"
        ];
        for (const category of shoppingCategories) {
            if (queryLower.includes(category)) {
                return category;
            }
        }
    }
    // Hotel categories (already covered by intent)
    if (intent === "hotels" || intent === "hotel") {
        return "hotels";
    }
    // Restaurant categories
    if (intent === "restaurants") {
        return "restaurants";
    }
    return undefined;
}
