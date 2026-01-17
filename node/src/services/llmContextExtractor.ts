

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
  location: string | null; 
  intent: string | null; 
  modifiers: string[]; 
  isRefinement: boolean; 
  needsParentContext: boolean; 
}

export interface ContextExtractionResult {
  context: ExtractedContext;
  confidence: number; 
  method: 'rules' | 'llm' | 'fallback';
}


export async function extractContextWithLLM(
  query: string,
  parentQuery?: string | null,
  conversationHistory?: any[]
): Promise<ContextExtractionResult> {
  try {
    const client = getClient();
    
    
    let conversationContext = "";
    if (conversationHistory && conversationHistory.length > 0) {
      const recentTurns = conversationHistory.slice(-3); 
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
      temperature: 0.1, 
      max_tokens: 300,
      response_format: { type: "json_object" },
    });

    const content = result.choices[0]?.message?.content?.trim() || "{}";
    const extracted = JSON.parse(content) as ExtractedContext;
    
    
    if (extracted.city) {
      extracted.city = normalizeCityName(extracted.city);
    }
    if (extracted.location) {
      extracted.location = normalizeCityName(extracted.location);
    }
    if (extracted.brand) {
      extracted.brand = normalizeBrandName(extracted.brand);
    }
    
    
    const confidence = extracted.isRefinement && extracted.needsParentContext ? 0.75 : 0.85;
    
    if (process.env.NODE_ENV === 'development') {
      console.log(`🧠 LLM Context Extraction: "${query}" →`, extracted, `(confidence: ${confidence})`);
    }
    
    return {
      context: extracted,
      confidence,
      method: 'llm',
    };
  } catch (err: any) {
    console.error("❌ LLM context extraction error:", err.message);
    
    const fallback = fallbackExtraction(query, parentQuery);
    return {
      context: fallback,
      confidence: 0.5, 
      method: 'fallback',
    };
  }
}


export async function mergeQueryContextWithLLM(
  currentQuery: string,
  parentQuery: string,
  extractedContext: ExtractedContext,
  intent: string
): Promise<string> {
  try {
    
    const currentQueryLower = currentQuery.toLowerCase();
    const hasExplicitLocation = /\b(in|at|near|from|to)\s+[a-zA-Z][a-zA-Z\s]{2,}/i.test(currentQuery);
    
    
    const currentLocationMatch = currentQuery.match(/\b(in|at|near|from|to)\s+([a-zA-Z][a-zA-Z\s]{2,})/i);
    const currentLocation = currentLocationMatch ? currentLocationMatch[2].toLowerCase().trim() : null;
    
    
    const parentLocationMatch = parentQuery.match(/\b(in|at|near|from|to)\s+([a-zA-Z][a-zA-Z\s]{2,})/i);
    const parentLocation = parentLocationMatch ? parentLocationMatch[2].toLowerCase().trim() : null;
    
    
    if (hasExplicitLocation && currentLocation && parentLocation && currentLocation !== parentLocation) {
      console.log(`🔒 Location conflict detected: current="${currentLocation}", parent="${parentLocation}" - skipping merge`);
      return currentQuery;
    }
    
    
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
    
    
    const cleaned = merged.replace(/^["']|["']$/g, "");
    
    if (cleaned !== currentQuery) {
      console.log(`🔗 LLM Query Merging: "${currentQuery}" + "${parentQuery}" → "${cleaned}"`);
    }
    
    return cleaned;
  } catch (err: any) {
    console.error("❌ LLM query merging error:", err.message);
    
    return fallbackMerge(currentQuery, parentQuery, extractedContext, intent);
  }
}


function fallbackExtraction(query: string, parentQuery?: string | null): ExtractedContext {
  const lower = query.toLowerCase();
  
 
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


function fallbackMerge(
  currentQuery: string,
  parentQuery: string,
  extractedContext: ExtractedContext,
  intent: string
): string {
  let merged = currentQuery;
  
  
  if (extractedContext.needsParentContext || extractedContext.isRefinement) {
    const parentCityMatch = parentQuery.match(/\b(in|at|near|from)\s+([a-zA-Z][a-zA-Z\s]{2,})/i);
    if (parentCityMatch && !extractedContext.city) {
      const parentCity = normalizeCityName(parentCityMatch[2].trim());
      merged = `${merged} in ${parentCity}`;
    }
  }
  
  return merged;
}


function normalizeCityName(city: string): string {
  if (!city) return city;
  

  return city
    .split(/\s+/)
    .map(word => word.charAt(0).toUpperCase() + word.slice(1).toLowerCase())
    .join(' ');
}

function normalizeBrandName(brand: string): string {
  if (!brand) return brand;
  
  
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

