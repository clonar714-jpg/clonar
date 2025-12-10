/**
 * Phase 3: "Of My Taste" Matching with Embeddings
 * Matches products to user preferences using semantic similarity
 */
import { getUserPreferences } from "./preferenceStorage";
import { getEmbedding, cosine } from "../../embeddings/embeddingClient";
/**
 * Build a preference profile text from user preferences
 * This text will be used to create an embedding for matching
 */
export function buildPreferenceProfile(userPrefs, category) {
    const parts = [];
    // Add brand preferences
    if (userPrefs.brand_preferences && userPrefs.brand_preferences.length > 0) {
        const topBrands = userPrefs.brand_preferences.slice(0, 3).join(", ");
        parts.push(`prefers brands: ${topBrands}`);
    }
    // Add style keywords
    if (userPrefs.style_keywords && userPrefs.style_keywords.length > 0) {
        const styles = userPrefs.style_keywords.slice(0, 3).join(", ");
        parts.push(`prefers ${styles} style`);
    }
    // Add price range
    if (userPrefs.price_range_min || userPrefs.price_range_max) {
        if (userPrefs.price_range_min && userPrefs.price_range_max) {
            parts.push(`prefers price range $${userPrefs.price_range_min} to $${userPrefs.price_range_max}`);
        }
        else if (userPrefs.price_range_max) {
            parts.push(`prefers products under $${userPrefs.price_range_max}`);
        }
        else if (userPrefs.price_range_min) {
            parts.push(`prefers products above $${userPrefs.price_range_min}`);
        }
    }
    // Add category-specific preferences
    if (category && userPrefs.category_preferences) {
        const categoryPrefs = userPrefs.category_preferences;
        const categoryLower = category.toLowerCase();
        for (const [cat, prefs] of Object.entries(categoryPrefs)) {
            if (categoryLower.includes(cat.toLowerCase()) || cat.toLowerCase().includes(categoryLower)) {
                if (prefs.brands && Array.isArray(prefs.brands) && prefs.brands.length > 0) {
                    parts.push(`prefers ${prefs.brands[0]} for ${cat}`);
                }
                if (prefs.style) {
                    parts.push(`prefers ${prefs.style} ${cat}`);
                }
                if (prefs.rating_min) {
                    parts.push(`prefers ${prefs.rating_min} star ${cat}`);
                }
                break;
            }
        }
    }
    // Build final text
    const profileText = parts.length > 0
        ? `User preferences: ${parts.join(". ")}`
        : "";
    return {
        text: profileText,
        confidence: userPrefs.confidence_score || 0,
    };
}
/**
 * Match items (products, hotels, movies, etc.) to user preferences using embeddings
 * Returns items reranked by preference similarity
 * Works for: shopping, hotels, restaurants, flights, places, movies
 */
export async function matchItemsToPreferences(items, userId, intent, category) {
    if (!products || products.length === 0) {
        return products;
    }
    // Skip if invalid user ID
    if (!userId || userId === "global" || userId === "dev-user-id") {
        return products;
    }
    try {
        // Load user preferences
        const userPrefs = await getUserPreferences(userId);
        if (!userPrefs) {
            console.log(`ℹ️ No user preferences found for preference matching`);
            return products;
        }
        // Check confidence threshold
        if (!userPrefs.confidence_score || userPrefs.confidence_score < 0.3) {
            console.log(`ℹ️ User preferences confidence too low (${userPrefs.confidence_score})`);
            return products;
        }
        // Build preference profile
        const profile = buildPreferenceProfile(userPrefs, category);
        if (!profile.text) {
            console.log(`ℹ️ Could not build preference profile`);
            return products;
        }
        console.log(`🎯 Phase 3: Matching ${items.length} items to preferences: "${profile.text}"`);
        // Get preference profile embedding
        const profileEmb = await getEmbedding(profile.text);
        // Score each item against preference profile
        const scored = await Promise.all(items.map(async (item) => {
            // Build item text for embedding (works for all types)
            let itemText = "";
            if (intent === "shopping") {
                itemText = [
                    item.title || item.name || "",
                    item.description || item.snippet || "",
                    item.brand || "",
                    item.price ? `$${item.price}` : "",
                ].filter(Boolean).join(" ");
            }
            else if (intent === "hotels" || intent === "hotel") {
                itemText = [
                    item.name || item.title || "",
                    item.description || item.snippet || "",
                    item.amenities ? (Array.isArray(item.amenities) ? item.amenities.join(" ") : item.amenities) : "",
                    item.rating ? `${item.rating} star` : "",
                    item.price ? `$${item.price}` : "",
                ].filter(Boolean).join(" ");
            }
            else if (intent === "restaurants") {
                itemText = [
                    item.name || item.title || "",
                    item.description || item.snippet || "",
                    item.cuisine || "",
                    item.rating ? `${item.rating} star` : "",
                    item.price ? `$${item.price}` : "",
                ].filter(Boolean).join(" ");
            }
            else if (intent === "movies") {
                itemText = [
                    item.title || item.name || "",
                    item.overview || item.description || "",
                    item.genres ? (Array.isArray(item.genres) ? item.genres.map((g) => g.name || g).join(" ") : item.genres) : "",
                    item.vote_average ? `${item.vote_average} rating` : "",
                    item.release_date ? item.release_date : "",
                ].filter(Boolean).join(" ");
            }
            else if (intent === "places" || intent === "location") {
                itemText = [
                    item.name || item.title || "",
                    item.description || item.snippet || "",
                    item.category || item.type || "",
                    item.rating ? `${item.rating} star` : "",
                ].filter(Boolean).join(" ");
            }
            else {
                // Generic fallback
                itemText = [
                    item.title || item.name || "",
                    item.description || item.snippet || "",
                    item.price ? `$${item.price}` : "",
                ].filter(Boolean).join(" ");
            }
            if (!itemText.trim()) {
                return { ...item, preferenceScore: 0 };
            }
            // Get item embedding
            const itemEmb = await getEmbedding(itemText);
            // Calculate similarity to preference profile
            const similarity = cosine(profileEmb, itemEmb);
            // Additional boosts for exact matches
            let boost = 0;
            // Brand match boost (for shopping)
            if (intent === "shopping" && userPrefs.brand_preferences && userPrefs.brand_preferences.length > 0) {
                const itemTextLower = itemText.toLowerCase();
                const hasBrand = userPrefs.brand_preferences.some(brand => itemTextLower.includes(brand.toLowerCase()));
                if (hasBrand) {
                    boost += 0.2; // Strong boost for brand match
                }
            }
            // Style match boost (for shopping, hotels, restaurants)
            if (userPrefs.style_keywords && userPrefs.style_keywords.length > 0) {
                const itemTextLower = itemText.toLowerCase();
                const hasStyle = userPrefs.style_keywords.some(style => itemTextLower.includes(style.toLowerCase()));
                if (hasStyle) {
                    boost += 0.15; // Boost for style match
                }
            }
            // Price range match boost (for shopping, hotels, restaurants)
            if ((intent === "shopping" || intent === "hotels" || intent === "hotel" || intent === "restaurants") && userPrefs.price_range_max) {
                const priceMatch = item.price?.toString().match(/\$?(\d+)/);
                if (priceMatch) {
                    const itemPrice = parseFloat(priceMatch[1]);
                    if (itemPrice <= userPrefs.price_range_max) {
                        boost += 0.1; // Boost for price match
                    }
                }
            }
            // Rating match boost (for hotels, restaurants, movies)
            if ((intent === "hotels" || intent === "hotel" || intent === "restaurants" || intent === "movies") && userPrefs.category_preferences) {
                const categoryPrefs = userPrefs.category_preferences;
                const relevantCategory = intent === "hotels" || intent === "hotel" ? "hotels" : intent === "restaurants" ? "restaurants" : intent === "movies" ? "movies" : category;
                if (relevantCategory && categoryPrefs[relevantCategory]?.rating_min) {
                    const minRating = categoryPrefs[relevantCategory].rating_min;
                    const itemRating = item.rating || item.vote_average || 0;
                    if (itemRating >= minRating) {
                        boost += 0.15; // Boost for rating match
                    }
                }
            }
            // Final preference score (similarity + boosts)
            const preferenceScore = Math.min(similarity + boost, 1.0);
            return { ...item, preferenceScore };
        }));
        // Sort by preference score (highest first)
        const sorted = scored.sort((a, b) => (b.preferenceScore || 0) - (a.preferenceScore || 0));
        // Log top matches
        if (sorted.length > 0) {
            console.log(`🎯 Phase 3: Top 3 preference matches (scores: ${sorted.slice(0, 3).map(s => (s.preferenceScore || 0).toFixed(3)).join(", ")})`);
        }
        return sorted;
    }
    catch (err) {
        console.error(`❌ Error matching products to preferences: ${err.message}`);
        // Return original products on error
        return products;
    }
}
/**
 * Hybrid reranking: Combine query relevance with preference matching
 * Uses weighted combination of query similarity and preference similarity
 * Works for: shopping, hotels, restaurants, flights, places, movies
 */
export async function hybridRerank(items, query, userId, intent, category, queryWeight = 0.6, preferenceWeight = 0.4) {
    if (!items || items.length === 0) {
        return items;
    }
    try {
        // Get query embedding
        const queryEmb = await getEmbedding(query);
        // Load user preferences
        let profileEmb = null;
        if (userId && userId !== "global" && userId !== "dev-user-id") {
            const userPrefs = await getUserPreferences(userId);
            if (userPrefs && userPrefs.confidence_score && userPrefs.confidence_score >= 0.3) {
                const profile = buildPreferenceProfile(userPrefs, category || intent);
                if (profile.text) {
                    profileEmb = await getEmbedding(profile.text);
                }
            }
        }
        // Score each item
        const scored = await Promise.all(items.map(async (item) => {
            // Build item text (works for all types)
            let itemText = "";
            if (intent === "shopping") {
                itemText = [
                    item.title || item.name || "",
                    item.description || item.snippet || "",
                ].filter(Boolean).join(" ");
            }
            else if (intent === "hotels" || intent === "hotel") {
                itemText = [
                    item.name || item.title || "",
                    item.description || item.snippet || "",
                    item.amenities ? (Array.isArray(item.amenities) ? item.amenities.join(" ") : item.amenities) : "",
                ].filter(Boolean).join(" ");
            }
            else if (intent === "restaurants") {
                itemText = [
                    item.name || item.title || "",
                    item.description || item.snippet || "",
                    item.cuisine || "",
                ].filter(Boolean).join(" ");
            }
            else if (intent === "movies") {
                itemText = [
                    item.title || item.name || "",
                    item.overview || item.description || "",
                    item.genres ? (Array.isArray(item.genres) ? item.genres.map((g) => g.name || g).join(" ") : item.genres) : "",
                ].filter(Boolean).join(" ");
            }
            else {
                // Generic fallback
                itemText = [
                    item.title || item.name || "",
                    item.description || item.snippet || "",
                ].filter(Boolean).join(" ");
            }
            if (!itemText.trim()) {
                return { ...item, hybridScore: 0 };
            }
            // Get item embedding
            const itemEmb = await getEmbedding(itemText);
            // Query similarity score
            const querySimilarity = cosine(queryEmb, itemEmb);
            // Preference similarity score
            let preferenceSimilarity = 0;
            if (profileEmb) {
                preferenceSimilarity = cosine(profileEmb, itemEmb);
            }
            // Hybrid score (weighted combination)
            const hybridScore = querySimilarity * queryWeight +
                preferenceSimilarity * preferenceWeight;
            return { ...item, hybridScore };
        }));
        // Sort by hybrid score
        const sorted = scored.sort((a, b) => (b.hybridScore || 0) - (a.hybridScore || 0));
        return sorted;
    }
    catch (err) {
        console.error(`❌ Error in hybrid reranking: ${err.message}`);
        return products;
    }
}
