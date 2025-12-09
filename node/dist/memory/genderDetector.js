// src/memory/genderDetector.ts
/**
 * Detect gender from query
 */
export function detectGender(query) {
    const lower = query.toLowerCase();
    if (lower.includes("men") || lower.includes("male") || lower.includes("mens")) {
        return "men";
    }
    if (lower.includes("women") || lower.includes("woman") || lower.includes("womens") ||
        lower.includes("girl") || lower.includes("female")) {
        return "women";
    }
    return null;
}
