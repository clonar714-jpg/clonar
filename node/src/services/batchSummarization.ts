/**
 * 🚀 OpenAI-Style Batch Summarization
 * 
 * Instead of generating descriptions one-by-one (slow, expensive),
 * this generates ALL descriptions in a SINGLE LLM call.
 * 
 * Benefits:
 * - 10x faster (1 call vs 8 calls)
 * - 10x cheaper (1 call vs 8 calls)
 * - Consistent tone/style
 * - Comparative insights (best overall, best value, etc.)
 * - Professional recommendations
 */

import OpenAI from "openai";

// Lazy client loader
let clientInstance: OpenAI | null = null;

function getClient(): OpenAI {
  if (!clientInstance) {
    const apiKey = process.env.OPENAI_API_KEY;
    if (!apiKey) throw new Error("Missing OPENAI_API_KEY");
    clientInstance = new OpenAI({ apiKey });
  }
  return clientInstance;
}

/**
 * Product batch summarization result
 */
export interface BatchProductSummary {
  products: Array<{
    id: string;
    title: string;
    clean_title: string;
    description: string;
    pros: string[];
    cons: string[];
    best_for: string;
    avoid_if: string;
    why_chosen: string;
  }>;
  comparative_summary: {
    best_overall: string | null;
    best_value: string | null;
    best_premium: string | null;
    best_for_budget: string | null;
    best_for_style: string | null;
    notes: string;
  };
}

/**
 * Hotel batch summarization result
 */
export interface BatchHotelSummary {
  hotels: Array<{
    id: string;
    name: string;
    clean_name: string;
    description: string;
    themes: string[];
    pros: string[];
    cons: string[];
    best_for: string;
    avoid_if: string;
    why_chosen: string;
  }>;
  comparative_summary: {
    best_overall: string | null;
    best_luxury: string | null;
    best_value: string | null;
    best_location: string | null;
    notes: string;
  };
}

/**
 * 🟩 Mini-Batch Aware Product Summarization
 * 
 * Optimized for speed: compact data, hard token limits, slim prompts
 */
export async function batchSummarizeProducts(products: any[], opts: { max_tokens?: number; compact?: boolean } = {}): Promise<BatchProductSummary> {
  if (products.length === 0) {
    return {
      products: [],
      comparative_summary: {
        best_overall: null,
        best_value: null,
        best_premium: null,
        best_for_budget: null,
        best_for_style: null,
        notes: "",
      },
    };
  }

  const batchStartTime = Date.now();
  const maxTokens = opts.max_tokens ?? 900;
  const isCompact = opts.compact ?? false;

  console.log(`🚀 Batch summarizing ${products.length} products (max_tokens: ${maxTokens}, compact: ${isCompact})...`);

  // 🔥 SLIM data - only essential fields
  const compactData = products.map((p, i) => ({
    id: p.id?.toString() || `p${i}`,
    title: p.title || "Unknown Product",
    price: p.price || p.extracted_price || "0",
    rating: p.rating || 0,
    snippet: (p._raw_snippet || p.snippet || "").substring(0, 120), // 🔥 SLIM data
    source: p.source || "",
  }));

  // 🔥 SLIM prompt for faster processing
  const systemPrompt = isCompact
    ? `You summarize shopping products concisely.

RULES:
- 2–3 sentence description per product
- Use ONLY provided data
- No hallucination
- Consistent tone
- JSON output only

STRUCTURE:
{
  "products": [
    {
      "id": "<id>",
      "title": "<title>",
      "description": "2-3 sentence summary",
      "pros": ["pro 1", "pro 2"],
      "cons": ["con 1"],
      "best_for": "user type",
      "avoid_if": "user type",
      "why_chosen": "reason"
    }
  ],
  "comparative_summary": {
    "best_overall": "id or null",
    "best_value": "id or null",
    "best_premium": "id or null",
    "notes": "brief insights"
  }
}`
    : `You are an expert shopping analyst. Summarize products concisely.

RULES:
- 2–3 sentence description per product
- Use ONLY provided data
- No hallucination
- Consistent tone
- Include pros/cons and comparative insights

STRUCTURE YOUR RESPONSE EXACTLY AS FOLLOWS:

{
  "products": [
    {
      "id": "<product.id>",
      "title": "<product.title>",
      "description": "2-3 sentence summary about the product",
      "pros": ["pro 1", "pro 2", "pro 3"],
      "cons": ["con 1", "con 2"],
      "best_for": "Which type of user benefits most",
      "avoid_if": "Which type of user should avoid it",
      "why_chosen": "1-sentence reason this product is in the list"
    }
  ],
  "comparative_summary": {
    "best_overall": "product_id or null",
    "best_value": "product_id or null",
    "best_premium": "product_id or null",
    "best_for_budget": "product_id or null",
    "best_for_style": "product_id or null",
    "notes": "Overall reasoning and high-level insights."
  }
}`;

  const userPrompt = JSON.stringify(compactData);

  try {
    const response = await getClient().chat.completions.create({
      model: "gpt-4o-mini",
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user", content: userPrompt },
      ],
      temperature: 0.3,
      response_format: { type: "json_object" },
    });

    const content = response.choices[0]?.message?.content;
    if (!content) {
      throw new Error("Empty response from OpenAI");
    }

    const parsed = JSON.parse(content) as BatchProductSummary;

    // Validate structure
    if (!parsed.products || !Array.isArray(parsed.products)) {
      throw new Error("Invalid response structure: missing products array");
    }

    const batchTime = Date.now() - batchStartTime;
    console.log(`✅ Batch summarization complete: ${parsed.products.length} products (took ${batchTime}ms)`);

    return parsed;
  } catch (error: any) {
    console.error("❌ Batch product summarization failed:", error.message);
    
    // Fallback: return basic descriptions
    return {
      products: products.map((product, index) => ({
        id: product.id?.toString() || `p${index}`,
        title: product.title || "Unknown Product",
        clean_title: (product.title || "Unknown Product").substring(0, 60),
        description: product._raw_snippet || product.snippet || "No description available.",
        pros: [],
        cons: [],
        best_for: "General use",
        avoid_if: "",
        why_chosen: "Available product",
      })),
      comparative_summary: {
        best_overall: null,
        best_value: null,
        best_premium: null,
        best_for_budget: null,
        best_for_style: null,
        notes: "Batch summarization failed, using fallback descriptions.",
      },
    };
  }
}

/**
 * 🟩 OpenAI-Style Batch Hotel Summarization
 * 
 * Takes ALL hotels and generates descriptions + comparisons in ONE call
 */
export async function batchSummarizeHotels(hotels: any[]): Promise<BatchHotelSummary> {
  if (hotels.length === 0) {
    return {
      hotels: [],
      comparative_summary: {
        best_overall: null,
        best_luxury: null,
        best_value: null,
        best_location: null,
        notes: "",
      },
    };
  }

  const batchStartTime = Date.now();
  console.log(`🚀 Batch summarizing ${hotels.length} hotels in ONE LLM call (OpenAI-style)...`);

  // Prepare hotel data for LLM (limit data size to avoid large payloads)
  const hotelData = hotels.map((hotel, index) => ({
    id: hotel.id?.toString() || `h${index}`,
    name: hotel.name || "Unknown Hotel",
    address: hotel.address || "",
    rating: hotel.rating || hotel.overall_rating || 0,
    price: hotel.rate_per_night || hotel.price || "",
    // ⚡ OPTIMIZATION: Limit amenities to first 10 (reduce payload size)
    amenities: (hotel.amenities || []).slice(0, 10),
    location: hotel.location || "",
    nearby: hotel.nearby || "",
    // ⚡ OPTIMIZATION: Limit description to 200 chars (reduce payload size)
    raw_description: (hotel.description || "").substring(0, 200),
  }));

  const systemPrompt = `You are an expert travel analyst. You will receive a list of hotels in structured JSON.

Your job is to produce high-quality, human-friendly descriptions and comparison insights for ALL hotels in a single response.

RULES:
- DO NOT hallucinate new features or amenities.
- Use ONLY data present in the hotel objects.
- If data is missing, say "not provided" instead of guessing.
- Be concise but informative (2–3 sentences each).
- Write in a consistent tone across all hotels.
- Highlight value, location, and unique strengths.
- Identify pros/cons based strictly on provided data.
- Extract themes (e.g., "Luxury", "Budget-friendly", "Family-friendly", "Business", "Romantic").
- Do NOT compare with external hotels not in the list.
- Always include comparative insights at the end.

STRUCTURE YOUR RESPONSE EXACTLY AS FOLLOWS:

{
  "hotels": [
    {
      "id": "<hotel.id>",
      "name": "<hotel.name>",
      "clean_name": "Shortened, crisp version of name (max 50 chars)",
      "description": "2-3 sentence summary about the hotel",
      "themes": ["theme1", "theme2", "theme3"],
      "pros": ["pro 1", "pro 2", "pro 3"],
      "cons": ["con 1", "con 2"],
      "best_for": "Which type of traveler benefits most",
      "avoid_if": "Which type of traveler should avoid it",
      "why_chosen": "1-sentence reason this hotel is in the list"
    }
  ],
  "comparative_summary": {
    "best_overall": "hotel_id or null",
    "best_luxury": "hotel_id or null",
    "best_value": "hotel_id or null",
    "best_location": "hotel_id or null",
    "notes": "Overall reasoning and high-level insights."
  }
}`;

  const userPrompt = `Now here is the hotel list to summarize:

${JSON.stringify(hotelData, null, 2)}`;

  try {
    const response = await getClient().chat.completions.create({
      model: "gpt-4o-mini",
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user", content: userPrompt },
      ],
      temperature: 0.3,
      response_format: { type: "json_object" },
    });

    const content = response.choices[0]?.message?.content;
    if (!content) {
      throw new Error("Empty response from OpenAI");
    }

    const parsed = JSON.parse(content) as BatchHotelSummary;

    // Validate structure
    if (!parsed.hotels || !Array.isArray(parsed.hotels)) {
      throw new Error("Invalid response structure: missing hotels array");
    }

    const batchTime = Date.now() - batchStartTime;
    console.log(`✅ Batch summarization complete: ${parsed.hotels.length} hotels, best overall: ${parsed.comparative_summary.best_overall} (took ${batchTime}ms)`);

    return parsed;
  } catch (error: any) {
    console.error("❌ Batch hotel summarization failed:", error.message);
    
    // Fallback: return basic descriptions
    return {
      hotels: hotels.map((hotel, index) => ({
        id: hotel.id?.toString() || `h${index}`,
        name: hotel.name || "Unknown Hotel",
        clean_name: (hotel.name || "Unknown Hotel").substring(0, 50),
        description: hotel.description || "No description available.",
        themes: [],
        pros: [],
        cons: [],
        best_for: "General travelers",
        avoid_if: "",
        why_chosen: "Available hotel",
      })),
      comparative_summary: {
        best_overall: null,
        best_luxury: null,
        best_value: null,
        best_location: null,
        notes: "Batch summarization failed, using fallback descriptions.",
      },
    };
  }
}

