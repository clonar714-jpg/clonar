// src/routes/generateSuggestions.ts
import express from "express";
import OpenAI from "openai";
// Lazy-load OpenAI client
let clientInstance = null;
function getOpenAIClient() {
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
/* =====================================================
   PERPLEXITY-STYLE FOLLOW-UP GENERATOR (FINAL VERSION)
   ===================================================== */
router.post("/", async (req, res) => {
    try {
        const { query, answer, results, intent, conversationHistory } = req.body;
        // Safety defaults
        let safeQuery = query || "";
        let safeAnswer = answer || "";
        let safeIntent = intent || "answer";
        let safeResults = Array.isArray(results) ? results : [];
        // ✅ Extract intent and results from conversation history if not provided
        if ((!safeIntent || safeIntent === "answer") && conversationHistory && conversationHistory.length > 0) {
            const lastTurn = conversationHistory[conversationHistory.length - 1];
            if (lastTurn.intent && lastTurn.intent !== "answer") {
                safeIntent = lastTurn.intent;
            }
            else if (lastTurn.resultType && lastTurn.resultType !== "answer") {
                safeIntent = lastTurn.resultType;
            }
        }
        // ✅ Extract results from conversation history if not provided
        if (safeResults.length === 0 && conversationHistory && conversationHistory.length > 0) {
            const lastTurn = conversationHistory[conversationHistory.length - 1];
            if (lastTurn.cards && Array.isArray(lastTurn.cards) && lastTurn.cards.length > 0) {
                safeResults = lastTurn.cards;
            }
            else if (lastTurn.products && Array.isArray(lastTurn.products) && lastTurn.products.length > 0) {
                safeResults = lastTurn.products.map((p) => ({
                    title: p.title,
                    price: p.price,
                    source: p.source,
                }));
            }
            else if (lastTurn.hotelResults && Array.isArray(lastTurn.hotelResults) && lastTurn.hotelResults.length > 0) {
                safeResults = lastTurn.hotelResults;
            }
            else if (lastTurn.rawResults && Array.isArray(lastTurn.rawResults) && lastTurn.rawResults.length > 0) {
                safeResults = lastTurn.rawResults;
            }
        }
        /* -------------------------------------------------------
           1. Build a product/hotel/restaurant summary for the LLM
           ------------------------------------------------------- */
        let resultSummary = "";
        if (safeResults.length > 0) {
            resultSummary = safeResults
                .slice(0, 6)
                .map((item, i) => {
                return `${i + 1}. ${item.title || item.name || "Item"} - price: ${item.price || "N/A"}, source: ${item.source || item.website || "Unknown"}`;
            })
                .join("\n");
        }
        /* -------------------------------------------------------
           2. Build Perplexity-style system prompt
           ------------------------------------------------------- */
        const systemPrompt = `
You are an AI assistant that generates highly relevant follow-up questions
for search queries, similar to Perplexity.ai.

RULES:
- Follow-ups must be specific, not generic.
- MUST relate to the product/hotel/restaurant context.
- SHOULD push the user deeper into exploration.
- Think: "What would the user naturally ask next?"
- DO NOT output generic phrases like:
    - "Tell me more"
    - "Learn more"
    - "Best options?"
- MUST return exactly 3 suggestions.
- Return ONLY a JSON array of strings.

CONTEXT YOU MUST USE:

User Query: "${safeQuery}"
Detected Intent: ${safeIntent}

AI Answer Summary:
"${safeAnswer}"

Products/Hotels/Items shown:
${resultSummary || "(No items shown)"}

Conversation history:
${JSON.stringify(conversationHistory || [], null, 2)}
`;
        /* -------------------------------------------------------
           3. LLM call
           ------------------------------------------------------- */
        let suggestions = [];
        try {
            const client = getOpenAIClient();
            const response = await client.chat.completions.create({
                model: "gpt-4o-mini",
                temperature: 0.4,
                messages: [
                    { role: "system", content: systemPrompt },
                    {
                        role: "user",
                        content: `Generate 3 follow-up suggestions following the rules. Return ONLY a JSON array of strings, no other text.`,
                    },
                ],
            });
            const content = response.choices[0].message.content || "";
            // Try to parse JSON array
            try {
                const parsed = JSON.parse(content);
                if (Array.isArray(parsed)) {
                    suggestions = parsed.filter((s) => typeof s === "string").slice(0, 3);
                }
            }
            catch (e) {
                // If not JSON, try to extract suggestions from text
                const lines = content.split("\n").filter((line) => line.trim().length > 0);
                suggestions = lines.slice(0, 3).map((line) => line.replace(/^[-*•]\s*/, "").trim());
            }
        }
        catch (err) {
            console.error("❌ LLM suggestion generation error:", err.message || err);
        }
        /* -------------------------------------------------------
           4. If LLM fails → Use template system
           ------------------------------------------------------- */
        if (suggestions.length === 0) {
            suggestions = generateTemplateSuggestions({
                query: safeQuery,
                answer: safeAnswer,
                results: safeResults,
                intent: safeIntent,
            });
        }
        return res.json({ suggestions });
    }
    catch (err) {
        console.error("❌ Error generating suggestions:", err);
        return res.json({
            suggestions: [
                "Can you refine your question?",
                "Want alternatives?",
                "Need comparisons?",
            ],
        });
    }
});
/* =====================================================
   TEMPLATE ENGINE — for fallback or empty LLM suggestions
   ===================================================== */
function generateTemplateSuggestions({ query, results, intent }) {
    const q = query.toLowerCase();
    // SHOPPING TEMPLATES
    if (intent === "shopping" || q.includes("buy") || q.includes("shoes") || q.includes("glasses") || q.includes("phone") || q.includes("laptop")) {
        return [
            `Compare top options under this budget`,
            `Which models offer the best durability?`,
            `Are there color/size variations available?`,
        ];
    }
    // HOTEL TEMPLATES
    if (intent === "hotel" || q.includes("hotel") || q.includes("stay")) {
        return [
            `Hotels near city center?`,
            `Best budget-friendly options?`,
            `Where do guests rate highest for cleanliness?`,
        ];
    }
    // RESTAURANTS TEMPLATES
    if (intent === "restaurants" || q.includes("restaurant") || q.includes("food") || q.includes("pizza") || q.includes("dining")) {
        return [
            `Popular dishes there?`,
            `Price range?`,
            `Is reservation needed?`,
        ];
    }
    // FLIGHTS TEMPLATES
    if (intent === "flights" || q.includes("flight") || q.includes("airline")) {
        return [
            `Cheapest options available?`,
            `Best departure times?`,
            `Direct flights only?`,
        ];
    }
    // LOCATION TEMPLATES
    if (intent === "location" || q.includes("visit") || q.includes("attractions") || q.includes("travel")) {
        return [
            `Best time to visit?`,
            `Major attractions?`,
            `Local transportation options?`,
        ];
    }
    // GENERIC ANSWER TEMPLATES
    return [
        `Want a comparison?`,
        `Need examples?`,
        `Should I break this down further?`,
    ];
}
export default router;
