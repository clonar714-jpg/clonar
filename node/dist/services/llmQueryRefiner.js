// src/services/llmQueryRefiner.ts
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
 * 🚀 C6 PATCH #2 — LLM Query Refinement
 * Refines user queries to maximize high-quality search results
 */
export async function refineQuery(query, intent) {
    try {
        const client = getClient();
        const prompt = `
You refine user queries for web search engines.
Task: Rewrite the query to maximize high-quality results for ${intent}.

Keep it short.
Examples:
- "nike shoes under 200" → "best nike running shoes under $200"
- "rayban glasses" → "rayban unisex polarized sunglasses best price"
- "balmain shirt" → "balmain men's designer t-shirt online deals"

Rewrite: "${query}"
`;
        const result = await client.chat.completions.create({
            model: "gpt-4o-mini",
            messages: [{ role: "user", content: prompt }],
            temperature: 0.2,
            max_tokens: 50,
        });
        const refined = result.choices[0]?.message?.content?.trim() || query;
        console.log(`🔧 Query refined: "${query}" → "${refined}"`);
        return refined;
    }
    catch (err) {
        console.error("❌ Query refinement error:", err.message);
        return query; // Fallback to original query
    }
}
