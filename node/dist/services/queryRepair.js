/**
 * 🔮 LLM Query Repair (Perplexity-style)
 * Fixes typos, merges broken words, and infers intended queries BEFORE search
 */
import OpenAI from "openai";
// Lazy-load OpenAI client
let clientInstance = null;
function getOpenAIClient() {
    if (!clientInstance) {
        const apiKey = process.env.OPENAI_API_KEY;
        if (!apiKey) {
            throw new Error("Missing OPENAI_API_KEY environment variable");
        }
        clientInstance = new OpenAI({ apiKey });
    }
    return clientInstance;
}
/**
 * Repair a search query using LLM (Perplexity-style)
 * Fixes typos, merges broken words, and infers the intended query
 *
 * Examples:
 * - "wicke dfor good movie" → "wicked for good movie"
 * - "su per man" → "superman"
 * - "spider man" → "spider-man"
 * - "nike shos" → "nike shoes"
 * - "hiltn htels" → "hilton hotels"
 */
export async function repairQuery(rawQuery, domain) {
    if (!rawQuery || !rawQuery.trim()) {
        return rawQuery;
    }
    try {
        const client = getOpenAIClient();
        // Domain-specific context for better repair
        const domainContext = domain === "movies"
            ? "movie titles, film names"
            : domain === "shopping"
                ? "product names, brands, shopping terms"
                : domain === "hotels"
                    ? "hotel names, locations, travel terms"
                    : domain === "places" || domain === "restaurants"
                        ? "place names, restaurant names, locations"
                        : "search terms";
        const systemPrompt = `You are a search query corrector for an AI search engine (like Perplexity).

Your task: Fix typos, merge broken words, and infer the intended search query.

CRITICAL RULES:
1. Fix obvious typos (e.g., "wicke" → "wicked", "shos" → "shoes")
2. Merge broken words (e.g., "wicke dfor" → "wicked for", "su per man" → "superman")
3. Infer the intended ${domainContext} even if the query is wrong
4. Do NOT simplify or shorten the query
5. Do NOT add extra words that weren't implied
6. Preserve the original intent and meaning
7. Return ONLY the corrected search query (no explanations, no markdown)

Examples:
- "wicke dfor good movie" → "wicked for good movie"
- "su per man" → "superman"
- "spider man" → "spider-man"
- "nike shos" → "nike shoes"
- "hiltn htels" → "hilton hotels"
- "og movie 2025" → "og movie 2025" (no change if already correct)
- "rental family" → "rental family" (no change if valid)

Return ONLY the corrected query.`;
        const response = await client.chat.completions.create({
            model: "gpt-4o-mini",
            messages: [
                { role: "system", content: systemPrompt },
                { role: "user", content: rawQuery },
            ],
            temperature: 0.1, // Low temperature for consistent corrections
            max_tokens: 100, // Query repair should be short
        });
        const repaired = response.choices[0]?.message?.content?.trim() || rawQuery;
        // Remove any markdown or quotes if present
        const cleaned = repaired
            .replace(/^["']|["']$/g, "") // Remove surrounding quotes
            .replace(/```[\w]*\n?/g, "") // Remove code blocks
            .trim();
        if (cleaned !== rawQuery) {
            console.log(`🔮 Query repair: "${rawQuery}" → "${cleaned}"`);
        }
        return cleaned || rawQuery; // Fallback to original if empty
    }
    catch (error) {
        console.warn(`⚠️ Query repair failed for "${rawQuery}":`, error.message);
        return rawQuery; // Fallback to original query on error
    }
}
/**
 * Token-based query reconstruction (Google-style)
 * Merges adjacent tokens if their combined embedding is similar to known titles/terms
 *
 * This is a secondary repair step that works alongside LLM repair
 */
export async function reconstructQueryTokens(query, referenceEmbeddings) {
    // For now, this is a placeholder for future token-based reconstruction
    // The LLM repair should handle most cases, but this can be enhanced later
    // with actual embedding-based token merging
    const tokens = query.toLowerCase().split(/\s+/);
    if (tokens.length < 2) {
        return query; // No merging needed for single token
    }
    // Simple heuristic: merge common broken patterns
    const merged = tokens.reduce((acc, token, index) => {
        if (index === 0) {
            return token;
        }
        const prevToken = tokens[index - 1];
        const combined = `${prevToken}${token}`;
        // Check if combined token looks like a valid word (basic heuristic)
        // This can be enhanced with actual embedding similarity later
        if (combined.length <= 12 && /^[a-z]+$/.test(combined)) {
            // Check if it's a common pattern (e.g., "wicked", "superman")
            const commonPatterns = [
                "wicked", "superman", "spiderman", "batman", "ironman",
                "nike", "adidas", "hilton", "marriott"
            ];
            if (commonPatterns.some(pattern => pattern.includes(combined) || combined.includes(pattern))) {
                return acc.replace(new RegExp(`${prevToken}\\s+${token}$`), combined);
            }
        }
        return acc + " " + token;
    }, tokens[0]);
    if (merged !== query) {
        console.log(`🔧 Token reconstruction: "${query}" → "${merged}"`);
    }
    return merged;
}
