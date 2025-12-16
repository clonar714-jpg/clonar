// src/services/llmContextExtractor.ts
// 🚀 Production-Grade LLM-Based Context Understanding
// Replaces brittle keyword/regex matching with intelligent semantic understanding
// Similar to how ChatGPT, Perplexity, and Cursor handle context
import OpenAI from "openai";
let client = null;
function getClient() {
    if (!client) {
        const apiKey = process.env.OPENAI_API_KEY;
        if (!apiKey) {
            throw new Error("Missing OPENAI_API_KEY environment variable");
        }
        client = new OpenAI({ apiKey });
    }
    return client;
}
/**
 * 🎯 LLM-Based Context Extraction
 * Intelligently extracts all context from a query using LLM understanding
 * Handles: case sensitivity, typos, variations, implicit context
 */
export async function extractContextWithLLM(query, parentQuery, conversationHistory) {
    try {
        const client = getClient();
        // Build conversation context for LLM
        let conversationContext = "";
        if (conversationHistory && conversationHistory.length > 0) {
            const recentTurns = conversationHistory.slice(-3); // Last 3 turns
            conversationContext = recentTurns
                .map((turn) => `User: ${turn.query || ""}\nAssistant: ${turn.summary || turn.answer || ""}`)
                .join("\n\n");
        }
        const parentContext = parentQuery ? `\nPrevious query: "${parentQuery}"` : "";
        const prompt = `You are a context extraction system for a search assistant (like ChatGPT/Perplexity).

Extract ALL relevant context from the user's query. Be intelligent and handle:
- Case variations (Bangkok, bangkok, BANGKOK)
- Typos and variations
- Implicit context (if query is vague, infer from conversation)
- Location variations (city names, areas, neighborhoods)
- Brand variations (Nike, nike, NIKE)
- Price mentions (under $100, cheaper, expensive, 5-star, luxury, budget)

Current query: "${query}"
${parentContext}
${conversationContext ? `\nRecent conversation:\n${conversationContext}` : ""}

Extract and return ONLY a JSON object with this exact structure:
{
  "brand": "brand name or null",
  "category": "product category or null (e.g., shoes, hotels, restaurants)",
  "price": "price mention or null (e.g., 'under $100', 'cheap', 'luxury', '5-star')",
  "city": "city name or null",
  "location": "general location or null (city, area, neighborhood, etc.)",
  "intent": "what user is looking for (e.g., 'hotels', 'shoes', 'restaurants')",
  "modifiers": ["array", "of", "modifiers", "like", "luxury", "cheap", "5-star"],
  "isRefinement": true/false,
  "needsParentContext": true/false
}

CRITICAL RULES (follow in strict order):
1. If query explicitly mentions a location/city, ALWAYS extract it and set needsParentContext: false (query is complete)
2. If query is vague (e.g., "only 5 star", "cheaper ones", "luxury") AND has NO location, set needsParentContext: true
3. NEVER infer location from parent query if current query explicitly mentions a DIFFERENT location
4. If parent query exists and current query is vague AND has no location, you may infer context from parent
5. For city/location: normalize to standard format (e.g., "bangkok" → "Bangkok", "singapore" → "Singapore")
6. Be case-insensitive but return normalized values
7. Extract ALL modifiers (5-star, luxury, cheap, budget, etc.)
8. If query has explicit location (e.g., "in singapore", "in paris"), set isRefinement: false (it's a new query, not a refinement)

Return ONLY the JSON object, no other text.`;
        const result = await client.chat.completions.create({
            model: "gpt-4o-mini",
            messages: [{ role: "user", content: prompt }],
            temperature: 0.1, // Low temperature for consistent extraction
            max_tokens: 300,
            response_format: { type: "json_object" },
        });
        const content = result.choices[0]?.message?.content?.trim() || "{}";
        const extracted = JSON.parse(content);
        // Normalize extracted values
        if (extracted.city) {
            extracted.city = normalizeCityName(extracted.city);
        }
        if (extracted.location) {
            extracted.location = normalizeCityName(extracted.location);
        }
        if (extracted.brand) {
            extracted.brand = normalizeBrandName(extracted.brand);
        }
        console.log(`🧠 LLM Context Extraction: "${query}" →`, extracted);
        return extracted;
    }
    catch (err) {
        console.error("❌ LLM context extraction error:", err.message);
        // Fallback to basic extraction
        return fallbackExtraction(query, parentQuery);
    }
}
/**
 * 🎯 LLM-Based Query Merging
 * Intelligently merges parent query context with current query
 * Handles all edge cases: case sensitivity, typos, implicit context
 */
export async function mergeQueryContextWithLLM(currentQuery, parentQuery, extractedContext, intent) {
    try {
        // ✅ PRODUCTION FIX: If current query has explicit location, NEVER merge with parent location
        const currentQueryLower = currentQuery.toLowerCase();
        const hasExplicitLocation = /\b(in|at|near|from|to)\s+[a-zA-Z][a-zA-Z\s]{2,}/i.test(currentQuery);
        // Extract location from current query if present
        const currentLocationMatch = currentQuery.match(/\b(in|at|near|from|to)\s+([a-zA-Z][a-zA-Z\s]{2,})/i);
        const currentLocation = currentLocationMatch ? currentLocationMatch[2].toLowerCase().trim() : null;
        // Extract location from parent query if present
        const parentLocationMatch = parentQuery.match(/\b(in|at|near|from|to)\s+([a-zA-Z][a-zA-Z\s]{2,})/i);
        const parentLocation = parentLocationMatch ? parentLocationMatch[2].toLowerCase().trim() : null;
        // If current query has explicit location and it's different from parent, return as-is
        if (hasExplicitLocation && currentLocation && parentLocation && currentLocation !== parentLocation) {
            console.log(`🔒 Location conflict detected: current="${currentLocation}", parent="${parentLocation}" - skipping merge`);
            return currentQuery;
        }
        // If query doesn't need parent context, return as-is
        if (!extractedContext.needsParentContext && !extractedContext.isRefinement) {
            return currentQuery;
        }
        const client = getClient();
        const prompt = `You are a query enhancement system for a search assistant (like ChatGPT/Perplexity).

Task: Intelligently merge the current query with context from the previous query.

Current query: "${currentQuery}"
Previous query: "${parentQuery}"
Intent: ${intent}
Extracted context: ${JSON.stringify(extractedContext, null, 2)}

CRITICAL RULES (follow in strict order):
1. NEVER add location from previous query if current query explicitly mentions a DIFFERENT location
2. NEVER add location from previous query if current query already has a location (even if vague)
3. If current query is vague (e.g., "only 5 star", "cheaper", "luxury ones") AND has NO location, merge with previous query's context
4. Preserve explicit mentions in current query (don't override) - this is the HIGHEST priority
5. Add missing context from previous query (location, brand, category) ONLY if current query doesn't have it
6. Handle case variations intelligently
7. Create a natural, searchable query
8. For travel intents (hotels, restaurants, places), ONLY add location from previous query if current query has NO location mentioned

Examples:
- Current: "only 5 star hotels", Previous: "hotels in bangkok" → "5 star hotels in Bangkok" (vague, no location)
- Current: "cheaper ones", Previous: "nike shoes" → "cheaper nike shoes" (no location needed)
- Current: "luxury hotels", Previous: "hotels in bangkok" → "luxury hotels in Bangkok" (vague, no location)
- Current: "hotels in paris", Previous: "hotels in bangkok" → "hotels in paris" (explicit location, NEVER override)
- Current: "things to do in singapore", Previous: "things to do in bali" → "things to do in singapore" (explicit location, NEVER add bali)
- Current: "places to visit in singapore", Previous: "places in bali" → "places to visit in singapore" (explicit location, NEVER add bali)

Return ONLY the merged query, no explanation.`;
        const result = await client.chat.completions.create({
            model: "gpt-4o-mini",
            messages: [{ role: "user", content: prompt }],
            temperature: 0.1,
            max_tokens: 100,
        });
        const merged = result.choices[0]?.message?.content?.trim() || currentQuery;
        // Remove quotes if LLM added them
        const cleaned = merged.replace(/^["']|["']$/g, "");
        if (cleaned !== currentQuery) {
            console.log(`🔗 LLM Query Merging: "${currentQuery}" + "${parentQuery}" → "${cleaned}"`);
        }
        return cleaned;
    }
    catch (err) {
        console.error("❌ LLM query merging error:", err.message);
        // Fallback to rule-based merging
        return fallbackMerge(currentQuery, parentQuery, extractedContext, intent);
    }
}
/**
 * Fallback extraction (when LLM fails)
 */
function fallbackExtraction(query, parentQuery) {
    const lower = query.toLowerCase();
    // Basic extraction
    const cityMatch = lower.match(/\b(in|at|near|from)\s+([a-zA-Z][a-zA-Z\s]{2,})/);
    const city = cityMatch ? normalizeCityName(cityMatch[2].trim()) : null;
    const priceMatch = lower.match(/(under|below|cheap|expensive|luxury|budget|\d+\s*star)/i);
    const price = priceMatch ? priceMatch[0] : null;
    const isRefinement = /^(only|just|more|less|cheaper|expensive|costlier|luxury|budget|premium|the|ones?|these|those|it|them)$/i.test(query.trim()) ||
        /^(show me|find|get|give me|i want|i need)\s+(more|less|cheaper|expensive|luxury|budget|premium|the|ones?|these|those|it|them)/i.test(query);
    return {
        brand: null,
        category: null,
        price,
        city,
        location: city,
        intent: null,
        modifiers: [],
        isRefinement,
        needsParentContext: isRefinement && !city,
    };
}
/**
 * Fallback merging (when LLM fails)
 */
function fallbackMerge(currentQuery, parentQuery, extractedContext, intent) {
    let merged = currentQuery;
    // Extract city from parent if current doesn't have it
    if (extractedContext.needsParentContext || extractedContext.isRefinement) {
        const parentCityMatch = parentQuery.match(/\b(in|at|near|from)\s+([a-zA-Z][a-zA-Z\s]{2,})/i);
        if (parentCityMatch && !extractedContext.city) {
            const parentCity = normalizeCityName(parentCityMatch[2].trim());
            merged = `${merged} in ${parentCity}`;
        }
    }
    return merged;
}
/**
 * Normalize city names (handle case variations)
 */
function normalizeCityName(city) {
    if (!city)
        return city;
    // Capitalize first letter of each word
    return city
        .split(/\s+/)
        .map(word => word.charAt(0).toUpperCase() + word.slice(1).toLowerCase())
        .join(' ');
}
/**
 * Normalize brand names
 */
function normalizeBrandName(brand) {
    if (!brand)
        return brand;
    // Handle common brand variations
    const brandMap = {
        'rayban': 'Ray-Ban',
        'ray-ban': 'Ray-Ban',
        'mk': 'Michael Kors',
        'michael kors': 'Michael Kors',
        'lv': 'Louis Vuitton',
        'louis vuitton': 'Louis Vuitton',
    };
    const lower = brand.toLowerCase();
    return brandMap[lower] || brand.charAt(0).toUpperCase() + brand.slice(1).toLowerCase();
}
