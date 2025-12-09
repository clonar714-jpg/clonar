// src/services/placesSectionGenerator.ts
import OpenAI from "openai";
let client = null;
function getClient() {
    if (!client) {
        const apiKey = process.env.OPENAI_API_KEY;
        if (!apiKey)
            throw new Error("Missing OPENAI_API_KEY");
        client = new OpenAI({ apiKey });
    }
    return client;
}
/**
 * 🎯 LLM Section Generator (Perplexity Style)
 * Groups tourist places into structured sections like:
 * - Top Cities & Cultural Sites
 * - Nature & Adventure
 * - Islands & Beach Destinations
 */
export function buildPlacesSectionPrompt(countryOrCity) {
    return `
You are an expert travel curator. Group tourist places for ${countryOrCity} into structured sections.

Return JSON with this format:
{
  "sections": [
    { "title": "Top Cities & Cultural Sites", "types": ["city", "landmark", "temple"] },
    { "title": "Nature & Adventure", "types": ["national_park", "waterfall", "mountain"] },
    { "title": "Islands & Beach Destinations", "types": ["island", "beach"] }
  ]
}

Only return JSON. No markdown, no code blocks.
`;
}
export async function generatePlacesSections(countryOrCity) {
    try {
        const prompt = buildPlacesSectionPrompt(countryOrCity);
        const res = await getClient().chat.completions.create({
            model: "gpt-4o-mini",
            messages: [{ role: "user", content: prompt }],
            temperature: 0.3,
            max_tokens: 300,
        });
        const content = res.choices[0]?.message?.content?.trim() || "{}";
        // Remove markdown code blocks if present
        const cleaned = content.replace(/```json\n?/g, "").replace(/```\n?/g, "").trim();
        const parsed = JSON.parse(cleaned);
        // Validate structure
        if (!parsed.sections || !Array.isArray(parsed.sections)) {
            return getDefaultSections();
        }
        return parsed;
    }
    catch (err) {
        console.error("❌ Places section generation error:", err.message);
        return getDefaultSections();
    }
}
function getDefaultSections() {
    return {
        sections: [
            { title: "Top Cities & Cultural Sites", types: ["city", "landmark", "temple", "museum"] },
            { title: "Nature & Adventure", types: ["national_park", "waterfall", "mountain", "hiking"] },
            { title: "Islands & Beach Destinations", types: ["island", "beach", "coast"] },
            { title: "Historic & Heritage Sites", types: ["heritage", "monument", "palace", "fort"] },
        ],
    };
}
