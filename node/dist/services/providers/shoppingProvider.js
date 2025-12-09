/**
 * 🏪 Shopping Provider Abstraction Layer
 * Supports multiple shopping APIs: SerpAPI, Shopify, Amazon, etc.
 * Future-proof for affiliate APIs
 */
/**
 * 🎯 Perplexity-Style Query Builder
 * Removes price constraints and improves gender/category queries for better API results
 */
export function buildOptimalQuery(originalQuery, options) {
    let query = originalQuery.toLowerCase().trim();
    // Remove price constraints (we'll filter on backend)
    query = query.replace(/\s*(under|below|less than|max|maximum|up to)\s*\$?\d+/gi, '');
    // Convert gender queries to more natural form
    // "nike shoes for men" → "nike men's shoes"
    if (query.includes(' for men') || query.includes(' for male')) {
        query = query.replace(/\s+for\s+(men|male)/gi, '');
        if (!query.includes("men's") && !query.includes("mens")) {
            // Insert "men's" before the product category
            const categoryMatch = query.match(/\b(shoes|sneakers|boots|shirt|tshirt|t-shirt|glasses|sunglasses|watch|watches|bag|purse|backpack)\b/i);
            if (categoryMatch) {
                query = query.replace(categoryMatch[0], `men's ${categoryMatch[0]}`);
            }
            else {
                query = `men's ${query}`;
            }
        }
    }
    if (query.includes(' for women') || query.includes(' for woman') || query.includes(' for female')) {
        query = query.replace(/\s+for\s+(women|woman|female|girls)/gi, '');
        if (!query.includes("women's") && !query.includes("womens")) {
            const categoryMatch = query.match(/\b(shoes|sneakers|boots|shirt|tshirt|t-shirt|glasses|sunglasses|watch|watches|bag|purse|backpack|dress)\b/i);
            if (categoryMatch) {
                query = query.replace(categoryMatch[0], `women's ${categoryMatch[0]}`);
            }
            else {
                query = `women's ${query}`;
            }
        }
    }
    // Clean up extra spaces
    query = query.replace(/\s+/g, ' ').trim();
    return query;
}
/**
 * Extract filters from query for backend filtering
 */
export function extractFiltersFromQuery(query) {
    const filters = {};
    // Extract price
    const priceMatch = query.match(/(under|below|less than|max|maximum|up to)\s*\$?(\d+)/i);
    if (priceMatch) {
        filters.priceMax = parseInt(priceMatch[2]);
    }
    const priceMinMatch = query.match(/(over|above|more than|min|minimum|from)\s*\$?(\d+)/i);
    if (priceMinMatch) {
        filters.priceMin = parseInt(priceMinMatch[2]);
    }
    // Extract gender
    if (/men|male|mens/i.test(query)) {
        filters.gender = 'men';
    }
    else if (/women|woman|female|girls|womens/i.test(query)) {
        filters.gender = 'women';
    }
    // Extract category
    const categories = ['shoes', 'sneakers', 'boots', 'shirt', 'tshirt', 't-shirt', 'glasses', 'sunglasses', 'watch', 'watches', 'bag', 'purse', 'backpack', 'dress', 'laptop', 'phone', 'headphones'];
    for (const cat of categories) {
        if (new RegExp(`\\b${cat}\\b`, 'i').test(query)) {
            filters.category = cat;
            break;
        }
    }
    // Extract brand (common brands)
    const brands = ['nike', 'adidas', 'puma', 'reebok', 'new balance', 'balmain', 'rayban', 'ray-ban', 'gucci', 'oakley', 'apple', 'samsung', 'sony', 'hp', 'macbook', 'fossil', 'michael kors', 'mk', 'prada'];
    for (const brand of brands) {
        if (new RegExp(`\\b${brand}\\b`, 'i').test(query)) {
            filters.brand = brand;
            break;
        }
    }
    return filters;
}
