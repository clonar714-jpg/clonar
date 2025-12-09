/**
 * 🏨 Hotel Provider Abstraction Layer
 * Supports multiple hotel APIs: Google Hotels, TripAdvisor, Booking.com, etc.
 * Future-proof for affiliate APIs
 */
/**
 * 🎯 Perplexity-Style Query Builder for Hotels
 * Removes price constraints and improves location queries
 */
export function buildOptimalHotelQuery(originalQuery, options) {
    let query = originalQuery.toLowerCase().trim();
    // Remove price constraints (we'll filter on backend)
    query = query.replace(/\s*(under|below|less than|max|maximum|up to)\s*\$?\d+/gi, '');
    query = query.replace(/\s*(over|above|more than|min|minimum|from)\s*\$?\d+/gi, '');
    // Improve location queries
    // "hotels near airport slc" → "hotels near Salt Lake City airport"
    if (query.includes('near airport')) {
        // Try to expand airport codes
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
    // Clean up extra spaces
    query = query.replace(/\s+/g, ' ').trim();
    return query;
}
/**
 * Extract filters from hotel query for backend filtering
 */
export function extractHotelFiltersFromQuery(query) {
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
    // Extract rating
    const ratingMatch = query.match(/(\d+)\s*star/i);
    if (ratingMatch) {
        filters.rating = parseInt(ratingMatch[1]);
    }
    // Extract location (basic - can be improved)
    const locationMatch = query.match(/(?:in|near|at)\s+([^,]+)/i);
    if (locationMatch) {
        filters.location = locationMatch[1].trim();
    }
    return filters;
}
