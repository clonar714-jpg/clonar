/**
 * Preference Extraction Service
 * Extracts user preferences from queries and results
 */
// Style keyword patterns
const STYLE_KEYWORDS = {
    luxury: ["luxury", "premium", "high-end", "5-star", "upscale", "exclusive", "deluxe", "boutique"],
    budget: ["budget", "affordable", "cheap", "economy", "low-cost", "inexpensive", "value"],
    modern: ["modern", "contemporary", "sleek", "minimalist", "cutting-edge"],
    vintage: ["vintage", "classic", "retro", "antique", "traditional"],
    eco: ["eco-friendly", "sustainable", "green", "organic", "environmentally friendly"],
    designer: ["designer", "branded", "name-brand", "high-fashion"],
};
// Price patterns
const PRICE_PATTERNS = [
    { pattern: /\$(\d+)\s*-\s*\$(\d+)/, extract: (match) => ({ min: parseInt(match[1]), max: parseInt(match[2]) }) },
    { pattern: /under\s*\$(\d+)/i, extract: (match) => ({ max: parseInt(match[1]) }) },
    { pattern: /above\s*\$(\d+)/i, extract: (match) => ({ min: parseInt(match[1]) }) },
    { pattern: /(\d+)\s*-\s*(\d+)\s*dollars/i, extract: (match) => ({ min: parseInt(match[1]), max: parseInt(match[2]) }) },
    { pattern: /cheap|affordable|inexpensive/i, extract: () => ({ max: 100 }) },
    { pattern: /expensive|costly|high-end/i, extract: () => ({ min: 200 }) },
];
// Rating patterns
const RATING_PATTERNS = [
    { pattern: /(\d+)\s*[-*]?\s*star/i, extract: (match) => parseInt(match[1]) },
    { pattern: /(\d+)\s*out\s*of\s*(\d+)/i, extract: (match) => parseFloat(match[1]) / parseFloat(match[2]) * 5 },
];
/**
 * Extract style keywords from text
 */
export function extractStyleKeywords(query, cards = []) {
    const found = new Set();
    const text = (query + " " +
        cards.map(c => c.title || c.name || "").join(" ") +
        " " +
        cards.map(c => c.description || "").join(" ")).toLowerCase();
    for (const [style, keywords] of Object.entries(STYLE_KEYWORDS)) {
        if (keywords.some(kw => text.includes(kw.toLowerCase()))) {
            found.add(style);
        }
    }
    return Array.from(found);
}
/**
 * Extract price range from text
 */
export function extractPriceRange(query, cards = []) {
    const text = query + " " + cards.map(c => c.price?.toString() || "").join(" ");
    const ranges = [];
    for (const { pattern, extract } of PRICE_PATTERNS) {
        const match = text.match(pattern);
        if (match) {
            const range = extract(match);
            if (range)
                ranges.push(range);
        }
    }
    // Also check card prices
    const cardPrices = cards
        .map(c => {
        const price = typeof c.price === 'number' ? c.price : parseFloat(c.price);
        return isNaN(price) ? null : price;
    })
        .filter((p) => p !== null);
    if (cardPrices.length > 0) {
        const minPrice = Math.min(...cardPrices);
        const maxPrice = Math.max(...cardPrices);
        ranges.push({ min: minPrice, max: maxPrice });
    }
    if (ranges.length === 0)
        return null;
    // Aggregate ranges
    const min = Math.min(...ranges.map(r => r.min || 0).filter(m => m > 0));
    const max = Math.max(...ranges.map(r => r.max || Infinity).filter(m => m < Infinity));
    return { min: min > 0 ? min : undefined, max: max < Infinity ? max : undefined };
}
/**
 * Extract brands from text and cards
 */
export function extractBrands(query, cards = []) {
    // Common brand names (expand as needed)
    const commonBrands = [
        "Rolex", "Omega", "Tag Heuer", "Cartier", "Patek Philippe",
        "Nike", "Adidas", "Puma", "Reebok",
        "Apple", "Samsung", "Sony",
        "BMW", "Mercedes", "Audi", "Tesla",
        "Gucci", "Prada", "Louis Vuitton", "Chanel",
        "Marriott", "Hilton", "Hyatt", "Four Seasons",
    ];
    const found = new Set();
    const text = (query + " " + cards.map(c => c.title || c.name || c.brand || "").join(" ")).toLowerCase();
    for (const brand of commonBrands) {
        if (text.includes(brand.toLowerCase())) {
            found.add(brand);
        }
    }
    // Also check card brand field
    cards.forEach(c => {
        if (c.brand && typeof c.brand === 'string') {
            found.add(c.brand);
        }
    });
    return Array.from(found);
}
/**
 * Extract rating mentions
 */
export function extractRatings(query, cards = []) {
    const found = [];
    const text = query + " " + cards.map(c => c.rating?.toString() || "").join(" ");
    for (const { pattern, extract } of RATING_PATTERNS) {
        const match = text.match(pattern);
        if (match) {
            const rating = extract(match);
            if (rating) {
                found.push(`${rating}-star`);
            }
        }
    }
    // Also check card ratings
    cards.forEach(c => {
        if (c.rating && typeof c.rating === 'number' && c.rating >= 4) {
            found.push(`${Math.round(c.rating)}-star`);
        }
    });
    return [...new Set(found)];
}
/**
 * Main extraction function
 */
export function extractPreferenceSignals(query, intent, cards = []) {
    const style_keywords = extractStyleKeywords(query, cards);
    const priceRange = extractPriceRange(query, cards);
    const brands = extractBrands(query, cards);
    const ratings = extractRatings(query, cards);
    // Format price mentions
    const price_mentions = [];
    if (priceRange) {
        if (priceRange.min && priceRange.max) {
            price_mentions.push(`$${priceRange.min}-$${priceRange.max}`);
        }
        else if (priceRange.min) {
            price_mentions.push(`above $${priceRange.min}`);
        }
        else if (priceRange.max) {
            price_mentions.push(`under $${priceRange.max}`);
        }
    }
    return {
        style_keywords,
        price_mentions,
        brand_mentions: brands,
        rating_mentions: ratings,
    };
}
