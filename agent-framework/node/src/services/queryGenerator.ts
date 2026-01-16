/**
 * ✅ IMPROVEMENT: Query Generation Service
 * 
 * Generates optimized search queries using LLM.
 * Benefits:
 * - Better search results (more specific queries)
 * - Handles vague queries better
 * - Extracts intent from conversation context
 */

import OpenAI from "openai";

let client: OpenAI | null = null;

function getClient(): OpenAI {
  if (!client) {
    const apiKey = process.env.OPENAI_API_KEY;
    if (!apiKey) {
      throw new Error("Missing OPENAI_API_KEY environment variable");
    }
    client = new OpenAI({
      apiKey: apiKey,
    });
  }
  return client;
}

/**
 * Formats conversation history for query generation
 */
function formatHistory(history: any[]): string {
  if (!history || history.length === 0) {
    return "";
  }

  return history
    .slice(-5) // Only use last 5 messages for context
    .map((msg: any) => {
      const query = msg.query || "";
      const summary = msg.summary || msg.answer || "";
      return `Q: ${query}\nA: ${summary}`;
    })
    .join("\n\n");
}

/**
 * Generates an optimized search query from user input
 * @param userQuery - The user's original query
 * @param conversationHistory - Previous conversation messages
 * @returns Optimized search query
 */
export async function generateSearchQuery(
  userQuery: string,
  conversationHistory: any[] = []
): Promise<string> {
  // Skip generation for very short queries (not worth it)
  if (!userQuery || userQuery.trim().length < 3) {
    return userQuery;
  }

  // Skip generation if query is already very specific (has many words)
  const words = userQuery.trim().split(/\s+/);
  if (words.length > 8) {
    console.log("📝 Query already specific, skipping generation");
    return userQuery;
  }

  try {
    const historyText = formatHistory(conversationHistory);
    
    const prompt = historyText
      ? `Based on the conversation and query, generate an optimized search query that will find the best results.

<conversation>
${historyText}
</conversation>

<query>
${userQuery}
</query>

Generate a concise, effective search query (2-8 words) that will find the best results. Focus on:
- Key terms from the query
- Context from the conversation
- Specificity (avoid generic terms)

Return ONLY the search query, nothing else.`
      : `Generate an optimized search query for: "${userQuery}"

Make it concise (2-8 words) and specific. Return ONLY the search query, nothing else.`;

    const response = await getClient().chat.completions.create({
      model: "gpt-4o-mini", // Use cheaper model for query generation
      messages: [{ role: "user", content: prompt }],
      temperature: 0.3, // Low temperature for consistency
      max_tokens: 50, // Short queries only
    });

    const generatedQuery = response.choices[0].message.content?.trim() || userQuery;
    
    // Validate generated query (should be reasonable length)
    if (generatedQuery.length > 200) {
      console.warn("⚠️ Generated query too long, using original");
      return userQuery;
    }

    // Only use generated query if it's different and potentially better
    if (generatedQuery.toLowerCase() !== userQuery.toLowerCase()) {
      console.log(`🔍 Query generation: "${userQuery}" → "${generatedQuery}"`);
      return generatedQuery;
    }

    return userQuery;
  } catch (error: any) {
    console.error("❌ Query generation failed:", error.message);
    // Fallback to original query
    return userQuery;
  }
}

/**
 * Determines if query generation should be used
 * @param query - The user's query
 * @param conversationHistory - Previous conversation
 * @returns True if generation should be used
 */
export function shouldGenerateQuery(
  query: string,
  conversationHistory: any[] = []
): boolean {
  // Generate if:
  // 1. Query is very vague (1-2 words) - always generate
  // 2. Query is short (3-4 words) AND has conversation history
  // 3. Query is already specific (5+ words) - skip generation

  const words = query.trim().split(/\s+/);
  const wordCount = words.length;
  const hasHistory = conversationHistory && conversationHistory.length > 0;
  
  // Very vague queries (1-2 words) - always generate for better results
  if (wordCount <= 2) {
    return true;
  }
  
  // Short queries (3-4 words) - only generate if we have conversation context
  if (wordCount <= 4 && hasHistory) {
    return true;
  }
  
  // Specific queries (5+ words) - skip generation (already good enough)
  return false;
}

