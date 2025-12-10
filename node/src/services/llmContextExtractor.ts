// src/services/llmContextExtractor.ts
// 🚀 Production-Grade LLM-Based Context Understanding
// Replaces brittle keyword/regex matching with intelligent semantic understanding
// Similar to how ChatGPT, Perplexity, and Cursor handle context

import OpenAI from "openai";

let client: OpenAI | null = null;

function getClient(): OpenAI {
  if (!client) {
    const apiKey = process.env.OPENAI_API_KEY;
    if (!apiKey) {
      throw new Error("Missing OPENAI_API_KEY environment variable");
    }
    client = new OpenAI({ apiKey });
  }
  return client;
}

export interface ExtractedContext {
  brand: string | null;
  category: string | null;
  price: string | null;
  city: string | null;
  location: string | null; // General location (city, area, etc.)
  intent: string | null; // What the user is looking for
  modifiers: string[]; // Additional modifiers (luxury, cheap, 5-star, etc.)
  isRefinement: boolean; // Is this a refinement of previous query?
  needsParentContext: boolean; // Does this query need context from parent?
}

/**
 * 🎯 LLM-Based Context Extraction
 * Intelligently extracts all context from a query using LLM understanding
 * Handles: case sensitivity, typos, variations, implicit context
 */
export async function extractContextWithLLM(
  query: string,
  parentQuery?: string | null,
  conversationHistory?: any[]
): Promise<ExtractedContext> {
  try {
    const client = getClient();
    
    // Build conversation context for LLM
    let conversationContext = "";
    if (conversationHistory && conversationHistory.length > 0) {
      const recentTurns = conversationHistory.slice(-3); // Last 3 turns
      conversationContext = recentTurns
        .map((turn: any) => `User: ${turn.query || ""}\nAssistant: ${turn.summary || turn.answer || ""}`)
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

Rules:
1. If query is vague (e.g., "only 5 star", "cheaper ones", "luxury"), set needsParentContext: true
2. If query explicitly mentions location, extract it (handle any case/variation)
3. If parent query exists and current query is vague, infer context from parent
4. For city/location: normalize to standard format (e.g., "bangkok" → "Bangkok")
5. Be case-insensitive but return normalized values
6. Extract ALL modifiers (5-star, luxury, cheap, budget, etc.)

Return ONLY the JSON object, no other text.`;

    const result = await client.chat.completions.create({
      model: "gpt-4o-mini",
      messages: [{ role: "user", content: prompt }],
      temperature: 0.1, // Low temperature for consistent extraction
      max_tokens: 300,
      response_format: { type: "json_object" },
    });

    const content = result.choices[0]?.message?.content?.trim() || "{}";
    const extracted = JSON.parse(content) as ExtractedContext;
    
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
  } catch (err: any) {
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
export async function mergeQueryContextWithLLM(
  currentQuery: string,
  parentQuery: string,
  extractedContext: ExtractedContext,
  intent: string
): Promise<string> {
  try {
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

Rules:
1. If current query is vague (e.g., "only 5 star", "cheaper", "luxury ones"), merge with previous query's context
2. Preserve explicit mentions in current query (don't override)
3. Add missing context from previous query (location, brand, category)
4. Handle case variations intelligently
5. Create a natural, searchable query
6. For travel intents (hotels, restaurants, places), ALWAYS preserve location from previous query if missing

Examples:
- Current: "only 5 star hotels", Previous: "hotels in bangkok" → "5 star hotels in Bangkok"
- Current: "cheaper ones", Previous: "nike shoes" → "cheaper nike shoes"
- Current: "luxury hotels", Previous: "hotels in bangkok" → "luxury hotels in Bangkok"
- Current: "hotels in paris", Previous: "hotels in bangkok" → "hotels in paris" (don't override explicit location)

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
  } catch (err: any) {
    console.error("❌ LLM query merging error:", err.message);
    // Fallback to rule-based merging
    return fallbackMerge(currentQuery, parentQuery, extractedContext, intent);
  }
}

/**
 * Fallback extraction (when LLM fails)
 */
function fallbackExtraction(query: string, parentQuery?: string | null): ExtractedContext {
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
function fallbackMerge(
  currentQuery: string,
  parentQuery: string,
  extractedContext: ExtractedContext,
  intent: string
): string {
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
function normalizeCityName(city: string): string {
  if (!city) return city;
  
  // Capitalize first letter of each word
  return city
    .split(/\s+/)
    .map(word => word.charAt(0).toUpperCase() + word.slice(1).toLowerCase())
    .join(' ');
}

/**
 * Normalize brand names
 */
function normalizeBrandName(brand: string): string {
  if (!brand) return brand;
  
  // Handle common brand variations
  const brandMap: Record<string, string> = {
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

