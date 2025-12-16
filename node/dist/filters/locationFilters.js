/**
 * 🗺️ Location Filters for ALL Fields
 * Filters hotels, restaurants, places by specific location (downtown, neighborhood, etc.)
 */
/**
 * Extract location details from query
 * Examples:
 * - "hotels in slc downtown" → { city: "slc", area: "downtown" }
 * - "restaurants near airport" → { area: "airport" }
 * - "hotels in downtown" → { area: "downtown" }
 */
export function extractLocationDetails(query) {
    const q = query.toLowerCase();
    const details = {};
    // Extract city (common patterns)
    // ✅ FIX: Better regex to handle "near to downtown", "near downtown", "in Park City downtown"
    // Priority: Extract city from merged queries like "hotels near downtown Park City"
    // Pattern 1: Extract city from merged queries like "hotels near downtown Park City"
    // Look for capitalized city name after area keywords (most reliable)
    const cityAfterArea = q.match(/(?:downtown|airport|beach|center|centre|district|area)\s+([A-Z][a-z]+(?:\s+[A-Z][a-z]+)*)/);
    if (cityAfterArea) {
        const city = cityAfterArea[1].trim();
        if (city.length > 2 && city.length < 30) {
            details.city = city.toLowerCase(); // Normalize to lowercase for matching
        }
    }
    // Pattern 2: "[City Name] downtown/airport" (city before area) - lowercase
    if (!details.city) {
        const cityBeforeArea = q.match(/([a-z\s]{3,}?)\s+(?:downtown|airport|beach|center|centre|district|area)/i);
        if (cityBeforeArea) {
            const cityPart = cityBeforeArea[1].trim();
            // Remove common prepositions and area words
            const city = cityPart
                .replace(/^(in|at|near|to|hotels|restaurants|places)\s+/i, '')
                .replace(/\s+(downtown|airport|beach|center|centre|district|area)$/i, '')
                .trim();
            // ✅ FIX: Don't extract single letters, common words, or very short strings
            if (city.length > 2 && city.length < 30 && !city.match(/^(to|downtown|airport|beach|near|in|at|hotels|restaurants|places)$/i)) {
                details.city = city;
            }
        }
    }
    // Pattern 3: "in/at/near [City Name]" (without area) - fallback
    if (!details.city) {
        const cityMatch = q.match(/\b(in|at|near)\s+([a-z\s]{3,}?)(?:\s+(?:downtown|airport|beach|center|centre|district|area))?$/i);
        if (cityMatch) {
            const cityPart = cityMatch[2].trim();
            // Remove common prepositions and area words
            const city = cityPart
                .replace(/^(to)\s+/i, '') // Remove "to" prefix (e.g., "to downtown" → "downtown")
                .replace(/\s+(downtown|airport|beach|center|centre|district|area)$/i, '')
                .trim();
            // ✅ FIX: Don't extract single letters or common words as cities
            if (city.length > 2 && city.length < 30 && !city.match(/^(to|downtown|airport|beach|near|in|at)$/i)) {
                details.city = city;
            }
        }
    }
    // Extract area/neighborhood
    const areaKeywords = [
        'downtown', 'airport', 'beach', 'center', 'centre', 'district',
        'neighborhood', 'neighbourhood', 'area', 'quarter', 'old town',
        'waterfront', 'harbor', 'harbour', 'marina', 'strip', 'boulevard',
        'avenue', 'plaza', 'square', 'market', 'station'
    ];
    for (const keyword of areaKeywords) {
        if (q.includes(keyword)) {
            details.area = keyword;
            break;
        }
    }
    // Extract neighborhood names (common ones)
    const neighborhoodMatch = q.match(/\b(in|at|near)\s+([a-z\s]+?)\s+(downtown|airport|beach|center|district)/i);
    if (neighborhoodMatch) {
        const neighborhood = neighborhoodMatch[2].trim();
        if (neighborhood.length > 0 && neighborhood.length < 30) {
            details.neighborhood = neighborhood;
        }
    }
    return details;
}
/**
 * Check if a location string matches the filter
 */
function locationMatches(locationText, filters) {
    if (!locationText)
        return true; // If no location filter, include all
    const text = locationText.toLowerCase();
    // Check area match
    if (filters.area) {
        const areaLower = filters.area.toLowerCase();
        // Must contain the area keyword
        if (!text.includes(areaLower)) {
            return false;
        }
    }
    // Check neighborhood match
    if (filters.neighborhood) {
        const neighborhoodLower = filters.neighborhood.toLowerCase();
        if (!text.includes(neighborhoodLower)) {
            return false;
        }
    }
    return true;
}
/**
 * Filter hotels by location
 */
export function filterHotelsByLocation(hotels, query) {
    if (!hotels || hotels.length === 0)
        return hotels;
    const locationFilters = extractLocationDetails(query);
    // If no location filter, return all
    if (!locationFilters.area && !locationFilters.neighborhood) {
        return hotels;
    }
    console.log(`🗺️ Location filter: ${JSON.stringify(locationFilters)}`);
    const filtered = hotels.filter((hotel) => {
        const address = (hotel.address || hotel.location || "").toLowerCase();
        const name = (hotel.name || "").toLowerCase();
        const combined = `${address} ${name}`;
        return locationMatches(combined, locationFilters);
    });
    console.log(`📍 Location filtered: ${filtered.length}/${hotels.length} hotels match location criteria`);
    return filtered;
}
/**
 * Filter restaurants by location
 */
export function filterRestaurantsByLocation(restaurants, query) {
    if (!restaurants || restaurants.length === 0)
        return restaurants;
    const locationFilters = extractLocationDetails(query);
    if (!locationFilters.area && !locationFilters.neighborhood) {
        return restaurants;
    }
    console.log(`🗺️ Location filter: ${JSON.stringify(locationFilters)}`);
    const filtered = restaurants.filter((restaurant) => {
        const address = (restaurant.address || restaurant.location || "").toLowerCase();
        const name = (restaurant.name || "").toLowerCase();
        const combined = `${address} ${name}`;
        return locationMatches(combined, locationFilters);
    });
    console.log(`📍 Location filtered: ${filtered.length}/${restaurants.length} restaurants match location criteria`);
    return filtered;
}
/**
 * Filter places by location
 */
export function filterPlacesByLocation(places, query) {
    if (!places || places.length === 0)
        return places;
    const locationFilters = extractLocationDetails(query);
    if (!locationFilters.area && !locationFilters.neighborhood) {
        return places;
    }
    console.log(`🗺️ Location filter: ${JSON.stringify(locationFilters)}`);
    const filtered = places.filter((place) => {
        const location = (place.location || place.address || "").toLowerCase();
        const name = (place.name || "").toLowerCase();
        const combined = `${location} ${name}`;
        return locationMatches(combined, locationFilters);
    });
    console.log(`📍 Location filtered: ${filtered.length}/${places.length} places match location criteria`);
    return filtered;
}
