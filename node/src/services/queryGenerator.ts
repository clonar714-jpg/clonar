

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


function formatHistory(history: any[]): string {
  if (!history || history.length === 0) {
    return "";
  }

  return history
    .slice(-5) 
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
      model: "gpt-4o-mini", 
      messages: [{ role: "user", content: prompt }],
      temperature: 0.3, 
      max_tokens: 50, 
    });

    const generatedQuery = response.choices[0].message.content?.trim() || userQuery;
    
    
    if (generatedQuery.length > 200) {
      console.warn("⚠️ Generated query too long, using original");
      return userQuery;
    }

    
    if (generatedQuery.toLowerCase() !== userQuery.toLowerCase()) {
      console.log(`🔍 Query generation: "${userQuery}" → "${generatedQuery}"`);
      return generatedQuery;
    }

    return userQuery;
  } catch (error: any) {
    console.error("❌ Query generation failed:", error.message);
    
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
  

  const words = query.trim().split(/\s+/);
  const wordCount = words.length;
  const hasHistory = conversationHistory && conversationHistory.length > 0;
  
  
  if (wordCount <= 2) {
    return true;
  }
  

  if (wordCount <= 4 && hasHistory) {
    return true;
  }
  
 
  return false;
}

