// src/refinement/llmRewrite.ts
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

/**
 * 🧠 C11.2 — LLM REWRITER (Perplexity-level)
 * Refines queries using LLM for optimal e-commerce/travel search
 */
export async function llmRewrite(refined: string): Promise<string> {
  try {
    const client = getClient();

    const prompt = `
Rewrite the search query to make it optimal for e-commerce / travel search engines.

Input: "${refined}"

Rules:
- Include the product type or item category
- Include brand if present
- Include budget constraints ONLY if explicitly mentioned in the input (e.g., "under 200", "below $100")
- Include purpose if present ("for running")
- Include gender ("men", "women")
- Include color if relevant
- Remove filler words
- DO NOT add price constraints unless the user explicitly mentioned them
- No sentences. Only output the refined query.

Output only the rewritten query.
`;

    const res = await client.chat.completions.create({
      model: "gpt-4o-mini",
      messages: [{ role: "user", content: prompt }],
      max_tokens: 30,
      temperature: 0.1,
    });

    const rewritten = res.choices[0]?.message?.content?.trim() || refined;
    
    if (rewritten !== refined) {
      console.log(`🤖 LLM rewritten query: "${refined}" → "${rewritten}"`);
    }

    return rewritten;
  } catch (err: any) {
    console.error("❌ LLM rewrite error:", err.message);
    return refined; // Fallback to memory-enhanced query
  }
}

