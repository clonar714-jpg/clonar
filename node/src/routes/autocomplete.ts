import express from "express";
import { Request, Response } from "express";
import OpenAI from "openai";

let clientInstance: OpenAI | null = null;

function getOpenAIClient(): OpenAI {
  if (!clientInstance) {
    const apiKey = process.env.OPENAI_API_KEY;
    if (!apiKey) {
      throw new Error("Missing OPENAI_API_KEY environment variable");
    }
    clientInstance = new OpenAI({
      apiKey: apiKey,
    });
  }
  return clientInstance;
}

const router = express.Router();


router.post("/", async (req: Request, res: Response) => {
  try {
    const { query } = req.body;

    if (!query || typeof query !== "string" || query.trim().length === 0) {
      return res.json({ suggestions: [] });
    }

    const trimmedQuery = query.trim();

    
    if (trimmedQuery.length < 2) {
      return res.json({ suggestions: [] });
    }

    const prompt = `
You are an intelligent search assistant that generates relevant search suggestions for shopping, hotels, flights, and general queries.

User is typing: "${trimmedQuery}"

Generate 4-5 search suggestions that:
1. Complete or extend the user's current query naturally
2. Are specific and actionable (not generic)
3. Predict the user's intent based on what they've typed so far
4. Include variations (e.g., "nike shoes" → "nike shoes for men", "nike shoes sale", "nike shoes for women", "nike shoes for kids")
5. Are relevant to shopping, travel, or general search

Examples:
- "nike" → ["nike shoes", "nike air max", "nike running shoes", "nike store"]
- "nike shoes" → ["nike shoes for men", "nike shoes sale", "nike shoes for women", "nike shoes for kids"]
- "hotels" → ["hotels near me", "hotels in new york", "hotels with pool", "hotels booking"]
- "iphone" → ["iphone 15", "iphone 15 pro", "iphone case", "iphone charger"]

Return ONLY a JSON array of strings (4-5 suggestions), no other text or markdown.
Example format: ["suggestion 1", "suggestion 2", "suggestion 3", "suggestion 4"]
`;

    const client = getOpenAIClient();
    const response = await client.chat.completions.create({
      model: "gpt-4o-mini",
      temperature: 0.7,
      messages: [
        {
          role: "user",
          content: prompt,
        },
      ],
      response_format: { type: "json_object" },
    });

    const content = response.choices[0].message?.content;
    if (!content) {
      throw new Error("Failed to generate suggestions from LLM");
    }

    let suggestions: string[] = [];

    try {
      const parsed = JSON.parse(content);
      
      if (Array.isArray(parsed)) {
        suggestions = parsed.slice(0, 5);
      } else if (parsed.suggestions && Array.isArray(parsed.suggestions)) {
        suggestions = parsed.suggestions.slice(0, 5);
      } else if (parsed.array && Array.isArray(parsed.array)) {
        suggestions = parsed.array.slice(0, 5);
      }
    } catch (parseError) {
      
      const lines = content
        .split("\n")
        .map((line) => line.trim())
        .filter((line) => line.length > 0 && !line.startsWith("```"));
      
      suggestions = lines
        .map((line) => line.replace(/^[-*•\d.]\s*/, "").replace(/["'`]/g, "").trim())
        .filter((line) => line.length > 0)
        .slice(0, 5);
    }

    
    if (suggestions.length === 0) {
      suggestions = generateFallbackSuggestions(trimmedQuery);
    }

    res.json({ suggestions });
  } catch (err: any) {
    console.error("❌ Error generating autocomplete suggestions:", err);
    
    const { query } = req.body;
    const trimmedQuery = query?.trim() || "";
    res.json({
      suggestions: generateFallbackSuggestions(trimmedQuery),
    });
  }
});


function generateFallbackSuggestions(query: string): string[] {
  const lowerQuery = query.toLowerCase();
  const suggestions: string[] = [];

  if (lowerQuery.includes("shoe") || lowerQuery.includes("sneaker")) {
    suggestions.push(`${query} for men`, `${query} for women`, `${query} sale`, `${query} for kids`);
  } else if (lowerQuery.includes("nike")) {
    suggestions.push("nike shoes", "nike air max", "nike running shoes", "nike store");
  } else if (lowerQuery.includes("hotel")) {
    suggestions.push("hotels near me", "hotels in new york", "hotels with pool", "hotels booking");
  } else if (lowerQuery.includes("iphone")) {
    suggestions.push("iphone 15", "iphone 15 pro", "iphone case", "iphone charger");
  } else {
    
    suggestions.push(
      `${query} near me`,
      `${query} sale`,
      `${query} for men`,
      `${query} for women`
    );
  }

  return suggestions.slice(0, 5);
}


router.post("/location", async (req: Request, res: Response) => {
  try {
    const { query } = req.body;

    if (!query || typeof query !== "string" || query.trim().length === 0) {
      return res.json({ predictions: [] });
    }

    const trimmedQuery = query.trim();

    
    if (trimmedQuery.length < 2) {
      return res.json({ predictions: [] });
    }

    const apiKey = process.env.GOOGLE_MAPS_BACKEND_KEY;
    
    if (!apiKey) {
      console.warn("⚠️ GOOGLE_MAPS_BACKEND_KEY not configured for location autocomplete");
      return res.json({ predictions: [] });
    }

    
    const autocompleteUrl = `https://maps.googleapis.com/maps/api/place/autocomplete/json?input=${encodeURIComponent(trimmedQuery)}&key=${apiKey}&types=(cities)`;
    
    const response = await fetch(autocompleteUrl);
    
    if (!response.ok) {
      console.error(`❌ Google Places Autocomplete API HTTP error: ${response.status} ${response.statusText}`);
      return res.json({ predictions: [] });
    }

    const data = await response.json();
    
    if (data.status === 'OK' && data.predictions && Array.isArray(data.predictions)) {
      const predictions = data.predictions.map((prediction: any) => ({
        description: prediction.description,
        place_id: prediction.place_id,
        structured_formatting: prediction.structured_formatting,
      }));
      
      res.json({ predictions });
    } else {
      console.warn(`⚠️ Places Autocomplete failed - Status: ${data.status}, Error: ${data.error_message || 'Unknown error'}`);
      res.json({ predictions: [] });
    }
  } catch (err: any) {
    console.error("❌ Error fetching location autocomplete:", err);
    res.json({ predictions: [] });
  }
});

export default router;

