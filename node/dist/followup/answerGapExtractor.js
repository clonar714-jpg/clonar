// ==================================================================
// ANSWER GAP EXTRACTOR - Extract unanswered aspects from answer
// ==================================================================
// This module extracts reasoning gaps from the answer to generate
// thoughtful follow-ups based on what wasn't covered.
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
 * Extracts unanswered aspects from the answer to generate reasoning-based follow-ups
 */
export async function extractAnswerGaps(query, answer, cards) {
    if (!answer || answer.trim().length === 0) {
        return {
            unansweredAspects: [],
            missingDetails: [],
            potentialFollowUps: [],
        };
    }
    try {
        const system = `You are a reasoning gap analyzer. Extract unanswered aspects from an answer to generate thoughtful follow-up questions.

Your task:
1. Identify what the answer DID NOT cover
2. Identify missing details that would help the user
3. Generate potential follow-up questions that fill these gaps

Rules:
- Focus on reasoning gaps, not just missing information
- Consider what a user might naturally wonder after reading the answer
- Generate 3-5 potential follow-ups
- Make them specific and actionable
- Avoid generic questions like "tell me more"

Return ONLY a JSON object with this structure:
{
  "unansweredAspects": ["aspect1", "aspect2"],
  "missingDetails": ["detail1", "detail2"],
  "potentialFollowUps": ["follow-up question 1", "follow-up question 2", "follow-up question 3"]
}`;
        const user = `Query: "${query}"
Answer: "${answer}"
${cards && cards.length > 0 ? `\nCards shown: ${cards.slice(0, 3).map((c) => c.title || c.name || '').join(', ')}` : ''}

Extract unanswered aspects and generate thoughtful follow-ups.`;
        const response = await getClient().chat.completions.create({
            model: "gpt-4o-mini",
            temperature: 0.3,
            max_tokens: 300,
            messages: [
                { role: "system", content: system },
                { role: "user", content: user },
            ],
        });
        const content = response.choices[0]?.message?.content || "";
        if (!content.trim()) {
            return {
                unansweredAspects: [],
                missingDetails: [],
                potentialFollowUps: [],
            };
        }
        // Parse JSON response
        try {
            const parsed = JSON.parse(content);
            return {
                unansweredAspects: parsed.unansweredAspects || [],
                missingDetails: parsed.missingDetails || [],
                potentialFollowUps: parsed.potentialFollowUps || [],
            };
        }
        catch {
            // Fallback: extract follow-ups from text
            const lines = content.split('\n').filter(l => l.trim());
            const followUps = [];
            for (const line of lines) {
                if (line.includes('?') || line.includes('follow')) {
                    const match = line.match(/"([^"]+)"/);
                    if (match)
                        followUps.push(match[1]);
                }
            }
            return {
                unansweredAspects: [],
                missingDetails: [],
                potentialFollowUps: followUps.slice(0, 5),
            };
        }
    }
    catch (error) {
        console.error("❌ Answer gap extraction failed:", error.message);
        return {
            unansweredAspects: [],
            missingDetails: [],
            potentialFollowUps: [],
        };
    }
}
