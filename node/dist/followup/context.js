/**
 * Merges the user's new follow-up query with remembered context
 * (like Perplexity's slot memory).
 */
export function mergeQueryWithContext(query, slots) {
    let q = query.trim();
    // Keep original casing for brand + category
    const qLower = q.toLowerCase();
    // Brand
    if (slots.brand && !qLower.includes(slots.brand.toLowerCase())) {
        if (!q.toLowerCase().startsWith(slots.brand.toLowerCase())) {
            q = `${slots.brand} ${q}`;
        }
    }
    // Category
    if (slots.category && !qLower.includes(slots.category.toLowerCase())) {
        q = `${q} ${slots.category}`;
    }
    // City
    if (slots.city && !qLower.includes(slots.city.toLowerCase())) {
        q = `${q} in ${slots.city}`;
    }
    // Price
    if (slots.price && !qLower.includes(slots.price.toLowerCase())) {
        q = `${q} ${slots.price}`;
    }
    return q.trim();
}
