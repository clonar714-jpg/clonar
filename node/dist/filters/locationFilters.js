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
    const cityMatch = q.match(/\b(in|at|near)\s+([a-z\s]+?)(?:\s+(?:downtown|airport|beach|center|centre|district|area))?/i);
    if (cityMatch) {
        const cityPart = cityMatch[2].trim();
        // Remove common area words to get city
        const city = cityPart
            .replace(/\s+(downtown|airport|beach|center|centre|district|area)$/i, '')
            .trim();
        if (city.length > 0 && city.length < 30) {
            details.city = city;
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
