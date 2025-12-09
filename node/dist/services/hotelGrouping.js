// src/services/hotelGrouping.ts
/**
 * 🏨 Hotel Grouping Engine (Perplexity-style)
 * Groups hotels into categories: Luxury, Midrange, Boutique, Budget
 */
export function groupHotels(hotels) {
    const luxury = [];
    const midrange = [];
    const budget = [];
    const boutique = [];
    for (const h of hotels) {
        const rating = Number(h.rating || h.overall_rating || 0);
        const hotelClass = Number(h.hotel_class || h.extracted_hotel_class || 0);
        const price = Number(String(h.price || h.rate_per_night?.lowest || "0").replace(/[^\d]/g, "")) || 0;
        const name = (h.name || h.title || "").toLowerCase();
        // Boutique rule (Perplexity-style heuristics)
        const isBoutique = name.includes("boutique") ||
            name.includes("monaco") ||
            name.includes("kimpton") ||
            name.includes("loft") ||
            name.includes("inn") ||
            name.includes("suites") ||
            name.includes("b&b") ||
            name.includes("bed and breakfast");
        // Luxury
        if (rating >= 4.5 || hotelClass >= 4 || price >= 200) {
            luxury.push(h);
            continue;
        }
        // Boutique overrides category
        if (isBoutique) {
            boutique.push(h);
            continue;
        }
        // Midrange
        if (rating >= 4.0 || hotelClass >= 3 || (price >= 100 && price < 200)) {
            midrange.push(h);
            continue;
        }
        // Budget
        budget.push(h);
    }
    return {
        luxury,
        midrange,
        boutique,
        budget,
    };
}
