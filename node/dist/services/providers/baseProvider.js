/**
 * 🏗️ Unified Provider Abstraction Layer
 * Works for ALL fields: shopping, hotels, flights, restaurants, places, etc.
 * Future-proof for ANY affiliate API (Shopify, TripAdvisor, Kiwi, etc.)
 */
/**
 * 🎯 Universal Query Optimizer (Perplexity-style)
 * Works for ALL field types
 */
export class QueryOptimizer {
    /**
     * Build optimal query for any field type
     * Removes constraints that APIs don't support, improves natural language
     */
    static optimize(query, fieldType) {
        let optimized = query.toLowerCase().trim();
        // Remove price constraints (filter on backend)
        optimized = optimized.replace(/\s*(under|below|less than|max|maximum|up to)\s*\$?\d+/gi, '');
        optimized = optimized.replace(/\s*(over|above|more than|min|minimum|from)\s*\$?\d+/gi, '');
        // Field-specific optimizations
        switch (fieldType) {
            case 'shopping':
                optimized = this.optimizeShopping(optimized);
                break;
            case 'hotels':
                optimized = this.optimizeHotels(optimized);
                break;
            case 'flights':
                optimized = this.optimizeFlights(optimized);
                break;
            case 'restaurants':
                optimized = this.optimizeRestaurants(optimized);
                break;
            case 'places':
                optimized = this.optimizePlaces(optimized);
                break;
        }
        // Clean up extra spaces
        optimized = optimized.replace(/\s+/g, ' ').trim();
        return optimized;
    }
    static optimizeShopping(query) {
        // Convert gender queries: "nike shoes for men" → "nike men's shoes"
        if (query.includes(' for men') || query.includes(' for male')) {
            query = query.replace(/\s+for\s+(men|male)/gi, '');
            if (!query.includes("men's") && !query.includes("mens")) {
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
        return query;
    }
    static optimizeHotels(query) {
        // Improve location queries: "hotels near airport slc" → "hotels near Salt Lake City airport"
        if (query.includes('near airport')) {
            const airportCodes = {
                'slc': 'Salt Lake City',
                'jfk': 'New York',
                'lax': 'Los Angeles',
                'sfo': 'San Francisco',
                'ord': 'Chicago',
                'dfw': 'Dallas',
                'atl': 'Atlanta',
                'miami': 'Miami',
            };
            for (const [code, city] of Object.entries(airportCodes)) {
                if (query.includes(code)) {
                    query = query.replace(code, `${city} ${code}`);
                    break;
                }
            }
        }
        return query;
    }
    static optimizeFlights(query) {
        // Expand airport codes
        const airportCodes = {
            'slc': 'Salt Lake City',
            'jfk': 'New York JFK',
            'lax': 'Los Angeles',
            'sfo': 'San Francisco',
            'ord': 'Chicago O\'Hare',
            'dfw': 'Dallas',
            'atl': 'Atlanta',
            'miami': 'Miami',
        };
        for (const [code, city] of Object.entries(airportCodes)) {
            if (query.includes(code) && !query.includes(city)) {
                query = query.replace(code, `${city} ${code}`);
            }
        }
        return query;
    }
    static optimizeRestaurants(query) {
        // Remove cuisine type constraints if they're too specific (APIs handle this better)
        // Keep the query as-is for restaurants
        return query;
    }
    static optimizePlaces(query) {
        // Improve location queries
        if (query.includes('near airport')) {
            const airportCodes = {
                'slc': 'Salt Lake City',
                'jfk': 'New York',
                'lax': 'Los Angeles',
            };
            for (const [code, city] of Object.entries(airportCodes)) {
                if (query.includes(code)) {
                    query = query.replace(code, `${city} ${code}`);
                    break;
                }
            }
        }
        return query;
    }
}
/**
 * Extract filters from query for backend filtering
 * Works for all field types
 */
export function extractFilters(query, fieldType) {
    const filters = {};
    // Price filters (shopping, hotels)
    const priceMaxMatch = query.match(/(under|below|less than|max|maximum|up to)\s*\$?(\d+)/i);
    if (priceMaxMatch) {
        filters.priceMax = parseInt(priceMaxMatch[2]);
    }
    const priceMinMatch = query.match(/(over|above|more than|min|minimum|from)\s*\$?(\d+)/i);
    if (priceMinMatch) {
        filters.priceMin = parseInt(priceMinMatch[2]);
    }
    // Gender filters (shopping)
    if (fieldType === 'shopping') {
        if (/men|male|mens/i.test(query)) {
            filters.gender = 'men';
        }
        else if (/women|woman|female|girls|womens/i.test(query)) {
            filters.gender = 'women';
        }
    }
    // Rating filters (hotels, restaurants)
    if (fieldType === 'hotels' || fieldType === 'restaurants') {
        const ratingMatch = query.match(/(\d+)\s*star/i);
        if (ratingMatch) {
            filters.rating = parseInt(ratingMatch[1]);
        }
    }
    // Location extraction
    const locationMatch = query.match(/(?:in|near|at)\s+([^,]+)/i);
    if (locationMatch) {
        filters.location = locationMatch[1].trim();
    }
    // Category extraction (shopping)
    if (fieldType === 'shopping') {
        const categories = ['shoes', 'sneakers', 'boots', 'shirt', 'tshirt', 't-shirt', 'glasses', 'sunglasses', 'watch', 'watches', 'bag', 'purse', 'backpack', 'dress', 'laptop', 'phone', 'headphones'];
        for (const cat of categories) {
            if (new RegExp(`\\b${cat}\\b`, 'i').test(query)) {
                filters.category = cat;
                break;
            }
        }
    }
    // Brand extraction (shopping)
    if (fieldType === 'shopping') {
        const brands = ['nike', 'adidas', 'puma', 'reebok', 'new balance', 'balmain', 'rayban', 'ray-ban', 'gucci', 'oakley', 'apple', 'samsung', 'sony', 'hp', 'macbook', 'fossil', 'michael kors', 'mk', 'prada'];
        for (const brand of brands) {
            if (new RegExp(`\\b${brand}\\b`, 'i').test(query)) {
                filters.brand = brand;
                break;
            }
        }
    }
    return filters;
}
/**
 * Apply backend filters to results
 * Generic function that works for all field types
 */
export function applyBackendFilters(results, filters, fieldType) {
    let filtered = [...results];
    // Price filters
    if (filters.priceMax) {
        filtered = filtered.filter((item) => {
            const price = parseFloat(item.price || item.extracted_price || "0");
            return price > 0 && price <= filters.priceMax;
        });
    }
    if (filters.priceMin) {
        filtered = filtered.filter((item) => {
            const price = parseFloat(item.price || item.extracted_price || "0");
            return price >= filters.priceMin;
        });
    }
    // Gender filter (shopping)
    if (fieldType === 'shopping' && filters.gender) {
        filtered = filtered.filter((item) => {
            const title = (item.title || item.name || "").toLowerCase();
            const category = (item.category || "").toLowerCase();
            if (filters.gender === "men") {
                return /men|male|mens/i.test(title) || /men|male/i.test(category);
            }
            else if (filters.gender === "women") {
                return /women|woman|female|girls|womens/i.test(title) || /women|female/i.test(category);
            }
            return true;
        });
    }
    // Rating filter (hotels, restaurants)
    if ((fieldType === 'hotels' || fieldType === 'restaurants') && filters.rating) {
        filtered = filtered.filter((item) => {
            const rating = parseFloat(item.rating || "0");
            return rating >= filters.rating;
        });
    }
    // Category filter (shopping)
    if (fieldType === 'shopping' && filters.category) {
        filtered = filtered.filter((item) => {
            const title = (item.title || item.name || "").toLowerCase();
            const category = (item.category || "").toLowerCase();
            return title.includes(filters.category) || category.includes(filters.category);
        });
    }
    // Brand filter (shopping)
    if (fieldType === 'shopping' && filters.brand) {
        filtered = filtered.filter((item) => {
            const title = (item.title || item.name || "").toLowerCase();
            const brand = (item.brand || "").toLowerCase();
            return title.includes(filters.brand) || brand.includes(filters.brand);
        });
    }
    return filtered;
}
