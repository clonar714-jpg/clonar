/**
 * Preference Aggregator Service
 * Aggregates preference signals into user preferences
 */
import { getRecentSignals, updateUserPreferences } from "./preferenceStorage";
/**
 * Aggregate user preferences from signals
 */
export async function aggregateUserPreferences(userId) {
    try {
        // 1. Get recent signals (last 50)
        const signals = await getRecentSignals(userId, 50);
        if (signals.length < 3) {
            // Not enough data yet
            console.log(`ℹ️ Not enough signals for user ${userId} (${signals.length} < 3)`);
            return null;
        }
        // 2. Count occurrences
        const styleCounts = {};
        const priceRanges = [];
        const brandCounts = {};
        const categoryStyleCounts = {};
        const categoryRatingCounts = {};
        signals.forEach(signal => {
            // Count style keywords
            signal.style_keywords?.forEach(style => {
                styleCounts[style] = (styleCounts[style] || 0) + 1;
                // Category-specific styles
                if (signal.intent) {
                    if (!categoryStyleCounts[signal.intent]) {
                        categoryStyleCounts[signal.intent] = {};
                    }
                    categoryStyleCounts[signal.intent][style] =
                        (categoryStyleCounts[signal.intent][style] || 0) + 1;
                }
            });
            // Collect price ranges
            signal.price_mentions?.forEach(mention => {
                const range = parsePriceMention(mention);
                if (range)
                    priceRanges.push(range);
            });
            // Count brands
            signal.brand_mentions?.forEach(brand => {
                brandCounts[brand] = (brandCounts[brand] || 0) + 1;
            });
            // Collect ratings by category
            if (signal.intent && signal.rating_mentions) {
                signal.rating_mentions.forEach(rating => {
                    const ratingNum = parseRating(rating);
                    if (ratingNum) {
                        if (!categoryRatingCounts[signal.intent]) {
                            categoryRatingCounts[signal.intent] = [];
                        }
                        categoryRatingCounts[signal.intent].push(ratingNum);
                    }
                });
            }
        });
        // 3. Calculate confidence scores (30% threshold)
        const totalSignals = signals.length;
        const threshold = totalSignals * 0.3;
        const styleConfidences = Object.entries(styleCounts)
            .filter(([_, count]) => count >= threshold)
            .map(([style, count]) => ({
            style,
            confidence: count / totalSignals,
        }))
            .sort((a, b) => b.confidence - a.confidence); // Sort by confidence
        const styleKeywords = styleConfidences.map(s => s.style);
        // 4. Calculate price range (median approach)
        const priceRange = calculatePriceRange(priceRanges);
        // 5. Top brands (appear in >20% of signals)
        const brandThreshold = totalSignals * 0.2;
        const topBrands = Object.entries(brandCounts)
            .filter(([_, count]) => count >= brandThreshold)
            .sort(([_, a], [__, b]) => b - a)
            .map(([brand]) => brand)
            .slice(0, 10); // Top 10
        // 6. Build category-specific preferences
        const categoryPreferences = {};
        for (const [category, styleCounts] of Object.entries(categoryStyleCounts)) {
            const categoryStyles = Object.entries(styleCounts)
                .filter(([_, count]) => count >= threshold)
                .sort(([_, a], [__, b]) => b - a)
                .map(([style]) => style);
            const categoryRatings = categoryRatingCounts[category];
            const ratingMin = categoryRatings && categoryRatings.length > 0
                ? Math.min(...categoryRatings)
                : undefined;
            if (categoryStyles.length > 0 || ratingMin) {
                categoryPreferences[category] = {
                    ...(categoryStyles.length > 0 && { style: categoryStyles[0] }), // Top style
                    ...(ratingMin && { rating_min: ratingMin }),
                };
            }
        }
        // 7. Calculate overall confidence (capped at 1.0)
        const overallConfidence = Math.min(totalSignals / 20, 1.0);
        // 8. Update user preferences
        const preferences = {
            style_keywords: styleKeywords,
            price_range_min: priceRange?.min,
            price_range_max: priceRange?.max,
            brand_preferences: topBrands,
            category_preferences: Object.keys(categoryPreferences).length > 0 ? categoryPreferences : undefined,
            confidence_score: overallConfidence,
            conversations_analyzed: totalSignals,
        };
        const updated = await updateUserPreferences(userId, preferences);
        console.log(`✅ Aggregated preferences for user ${userId}:`, {
            styles: styleKeywords,
            priceRange: priceRange,
            brands: topBrands.length,
            confidence: overallConfidence,
        });
        return updated;
    }
    catch (err) {
        console.error(`❌ Error aggregating preferences for user ${userId}:`, err.message);
        return null;
    }
}
/**
 * Parse price mention into range
 */
function parsePriceMention(mention) {
    // "$200-$500" -> {min: 200, max: 500}
    const rangeMatch = mention.match(/\$?(\d+)\s*-\s*\$?(\d+)/);
    if (rangeMatch) {
        return {
            min: parseInt(rangeMatch[1]),
            max: parseInt(rangeMatch[2]),
        };
    }
    // "under $100" -> {max: 100}
    const underMatch = mention.match(/under\s*\$?(\d+)/i);
    if (underMatch) {
        return { max: parseInt(underMatch[1]) };
    }
    // "above $500" -> {min: 500}
    const aboveMatch = mention.match(/above\s*\$?(\d+)/i);
    if (aboveMatch) {
        return { min: parseInt(aboveMatch[1]) };
    }
    return null;
}
/**
 * Parse rating mention
 */
function parseRating(rating) {
    const match = rating.match(/(\d+)/);
    return match ? parseFloat(match[1]) : null;
}
/**
 * Calculate aggregated price range from multiple ranges
 */
function calculatePriceRange(ranges) {
    if (ranges.length === 0)
        return null;
    const mins = ranges.map(r => r.min).filter((m) => m !== undefined && m > 0);
    const maxs = ranges.map(r => r.max).filter((m) => m !== undefined && m < Infinity);
    if (mins.length === 0 && maxs.length === 0)
        return null;
    return {
        min: mins.length > 0 ? Math.min(...mins) : undefined,
        max: maxs.length > 0 ? Math.max(...maxs) : undefined,
    };
}
