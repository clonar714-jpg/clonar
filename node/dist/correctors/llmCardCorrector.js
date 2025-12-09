// src/correctors/llmCardCorrector.ts
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
 * 🟦 C8.3 — LLM CORRECTION CHECK
 * Validates that cards match the answer summary
 * Removes irrelevant items that don't align with the LLM's answer
 */
export async function correctCards(query, answer, cards) {
    if (!cards || cards.length === 0)
        return [];
    // Skip correction if we have very few cards (don't want to remove more)
    if (cards.length <= 2) {
        return cards;
    }
    try {
        const client = getClient();
        const prompt = `
You are validating product relevance.

Query: "${query}"
Answer summary: "${answer}"

List ONLY item numbers (comma-separated) that are irrelevant or wrong.

Items:
${cards.map((c, i) => `${i + 1}. ${c.title || c.name || "Unknown"}`).join("\n")}

Rules:
- Remove unrelated categories
- Remove items violating price rules
- Remove wrong gender
- Keep only items that correctly match the answer
- Be strict: if the answer says "running shoes", remove non-running shoes
- If the answer says "Balmain shirt", remove non-shirts and non-Balmain items

Reply example: "2, 5" or "none"
`;
        const res = await client.chat.completions.create({
            model: "gpt-4o-mini",
            messages: [{ role: "user", content: prompt }],
            max_tokens: 20,
            temperature: 0,
        });
        const output = res.choices[0]?.message?.content?.trim() || "none";
        if (output.toLowerCase() === "none" || output.toLowerCase() === "all relevant") {
            console.log("✅ LLM correction: All cards are relevant");
            return cards;
        }
        // Parse indexes to remove
        const indexes = output
            .split(",")
            .map((n) => parseInt(n.trim()) - 1)
            .filter((n) => !isNaN(n) && n >= 0 && n < cards.length);
        if (indexes.length === 0) {
            console.log("✅ LLM correction: No items to remove");
            return cards;
        }
        const filtered = cards.filter((_, idx) => !indexes.includes(idx));
        console.log(`🔧 LLM correction: Removed ${indexes.length} irrelevant items (${filtered.length} remaining)`);
        return filtered;
    }
    catch (err) {
        console.error("❌ LLM correction error:", err.message);
        return cards; // Fallback to original cards
    }
}
