// =======================================================================
// C4 — ANSWER ENGINE (Perplexity-grade): ALWAYS RETURNS TEXT + STRUCTURE
// =======================================================================

import OpenAI from "openai";
import { Response } from "express";
import { SSE } from "../utils/sse";
import axios from "axios";

let client: OpenAI | null = null;

function getClient() {
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

// =======================================================================
// WEB SEARCH (For Live Results)
// =======================================================================

/**
 * Search the web using SerpAPI to get live, current information
 */
async function searchWeb(query: string): Promise<{ snippets: string[], sources: any[] }> {
  const serpKey = process.env.SERPAPI_KEY;
  
  if (!serpKey) {
    console.warn("⚠️ SERPAPI_KEY not found, skipping web search");
    return { snippets: [], sources: [] };
  }

  try {
    const serpUrl = "https://serpapi.com/search.json";
    const params = {
      engine: "google",
      q: query,
      api_key: serpKey,
      num: 5, // Get top 5 results
      hl: "en",
      gl: "us",
    };

    console.log(`🔍 Searching web for: "${query}"`);
    const response = await axios.get(serpUrl, { params, timeout: 10000 });
    
    const organicResults = response.data.organic_results || [];
    const snippets: string[] = [];
    const sources: any[] = [];

    // Extract snippets and sources from search results
    for (const result of organicResults.slice(0, 5)) {
      if (result.snippet) {
        snippets.push(result.snippet);
      }
      if (result.title && result.link) {
        sources.push({
          title: result.title,
          link: result.link,
        });
      }
    }

    console.log(`✅ Found ${snippets.length} web search results`);
    return { snippets, sources };
  } catch (error: any) {
    console.error("❌ Web search failed:", error.message);
    return { snippets: [], sources: [] };
  }
}

// =======================================================================
// FALLBACK BUILDER
// =======================================================================

function buildFallbackAnswer(query: string) {
  return {
    answer: `Here's a helpful overview regarding "${query}".`,
    summary: `Here's a helpful overview regarding "${query}".`,
    sources: [] as any[],
    locations: [] as any[],
    destination_images: [] as string[],
  };
}

// =======================================================================
// NON-STREAMED ANSWER
// =======================================================================

export async function getAnswerNonStream(query: string, history: any[]) {
  // ✅ STEP 1: Search the web for live, current information
  const webResults = await searchWeb(query);
  const webContext = webResults.snippets.length > 0
    ? `\n\nCURRENT WEB INFORMATION:\n${webResults.snippets.join('\n\n')}\n`
    : '';

  const system = `
You are a Perplexity-style answer engine.
Produce clean, concise, factual answers using CURRENT, LIVE information from the web.

FORMAT RULES:
- NO markdown symbols like **, ##, *, >
- NO code blocks
- Write a contextual overview paragraph (2-4 sentences, 50-100 words) that:
  * Sets expectations about what the user will see
  * Mentions key categories/types/options available
  * Provides context about the topic
  * Uses a conversational, informative tone
  * Example: "Salt Lake City has everything from luxury downtown hotels to budget-friendly chains and airport stays, so the best option depends on your budget, whether you want to be downtown, and if you need things like free breakfast or an airport shuttle. Here are some good, representative choices in a few common categories."
- Include factual data
- NEVER mention that you are an AI
- NEVER say "as an AI model"
- Do not hallucinate numbers
- Keep it crisp and neutral
- Use the CURRENT WEB INFORMATION provided below to answer with LIVE, UP-TO-DATE facts
- If web information is provided, prioritize it over your training data
- For current events, dates, or recent information, ONLY use the web information provided
- For places queries: Mention key highlights and what the destination offers, then let the place cards show the details.
- For shopping queries: Mention variety of styles/categories available and what makes them good choices.
- For hotel queries: Mention different types/categories available (luxury, budget, downtown, airport, etc.) and what factors matter.

IMPORTANT: Use conversation context for follow-up queries.
- If the user asks a follow-up question (e.g., "show me luxury ones", "more costlier", "cheaper options", "the red one"), you MUST understand it in the context of the previous conversation
- For follow-up queries, reference the previous query's topic/subject to provide a complete answer
- Example: If previous query was "hand made chairs" and user asks "more costlier", understand it as "more costlier handmade chairs"
- Example: If previous query was "hotels in Miami" and user asks "luxury ones", understand it as "luxury hotels in Miami"
- Example: If previous query was "nike shoes" and user asks "under $100", understand it as "nike shoes under $100"
- Only treat queries as independent if they are clearly starting a new topic (e.g., switching from "chairs" to "watches")
- Provide a fresh answer that incorporates the context from previous messages
${webContext}
`;

  try {
    // ✅ FIX: Format conversation history properly (user query + assistant answer pairs)
    const messages: any[] = [
      { role: "system", content: system }
    ];
    
    // Build proper conversation history with alternating user/assistant messages
    if (history && history.length > 0) {
      for (const h of history) {
        // Add user query
        if (h.query) {
          messages.push({
            role: "user",
            content: h.query
          });
        }
        
        // Add assistant answer with context about what was shown
        if (h.summary || h.answer) {
          let assistantContent = h.summary || h.answer || "";
          
          // ✅ Add context about what products/cards were shown (helps LLM understand follow-ups)
          if (h.cards && Array.isArray(h.cards) && h.cards.length > 0) {
            const cardTitles = h.cards.slice(0, 5).map((card: any) => card.title || card.name || '').filter(Boolean);
            if (cardTitles.length > 0) {
              assistantContent += `\n\n[Previous results included: ${cardTitles.join(', ')}]`;
            }
          }
          
          messages.push({
            role: "assistant",
            content: assistantContent
          });
        }
      }
    }
    
    // Add current query
    messages.push({ role: "user", content: query });
    
    const res = await getClient().chat.completions.create({
      model: "gpt-4o-mini",
      temperature: 0.3,
      max_tokens: 150, // ✅ Perplexity-style: 2-4 sentences contextual overview (50-100 words)
      messages: messages
    });

    const content = res.choices[0]?.message?.content || "";
    if (!content.trim()) return buildFallbackAnswer(query);

    return {
      answer: content,
      summary: content,
      sources: webResults.sources, // ✅ Include web search sources
      locations: [] as any[],
      destination_images: [] as string[],
    };
  } catch (err: any) {
    console.error("❌ Answer generation failed:", err);
    return buildFallbackAnswer(query);
  }
}

// =======================================================================
// STREAMING ANSWER (PERPLEXITY-STYLE)
// =======================================================================

export async function getAnswerStream(query: string, history: any[], res: Response) {
  // ✅ STEP 1: Search the web for live, current information
  const webResults = await searchWeb(query);
  const webContext = webResults.snippets.length > 0
    ? `\n\nCURRENT WEB INFORMATION:\n${webResults.snippets.join('\n\n')}\n`
    : '';

  const system = `
You produce Perplexity-style streamed answers.
Plain text only. No markdown. No symbols like *, **, ##.
Short intro (1-2 lines, MAX 50 words) → bullets (MAX 3-4) → facts → finish.
Use the CURRENT WEB INFORMATION provided below to answer with LIVE, UP-TO-DATE facts.
If web information is provided, prioritize it over your training data.
For current events, dates, or recent information, ONLY use the web information provided.
For places queries: Keep the overview brief. Do NOT list all places in detail - just mention the destination offers various attractions, then let the place cards show the details.

IMPORTANT: Use conversation context for follow-up queries.
- If the user asks a follow-up question (e.g., "show me luxury ones", "more costlier", "cheaper options"), you MUST understand it in the context of the previous conversation
- For follow-up queries, reference the previous query's topic/subject to provide a complete answer
- Example: If previous query was "hand made chairs" and user asks "more costlier", understand it as "more costlier handmade chairs"
- Example: If previous query was "hotels in Miami" and user asks "luxury ones", understand it as "luxury hotels in Miami"
- Only treat queries as independent if they are clearly starting a new topic
- Provide a fresh answer that incorporates the context from previous messages
${webContext}
`;

  const sse = new SSE(res);
  sse.init();

  try {
    // ✅ FIX: Format conversation history properly (user query + assistant answer pairs)
    const messages: any[] = [
      { role: "system", content: system }
    ];
    
    // Build proper conversation history with alternating user/assistant messages
    if (history && history.length > 0) {
      for (const h of history) {
        // Add user query
        if (h.query) {
          messages.push({
            role: "user",
            content: h.query
          });
        }
        
        // Add assistant answer with context about what was shown
        if (h.summary || h.answer) {
          let assistantContent = h.summary || h.answer || "";
          
          // ✅ Add context about what products/cards were shown (helps LLM understand follow-ups)
          if (h.cards && Array.isArray(h.cards) && h.cards.length > 0) {
            const cardTitles = h.cards.slice(0, 5).map((card: any) => card.title || card.name || '').filter(Boolean);
            if (cardTitles.length > 0) {
              assistantContent += `\n\n[Previous results included: ${cardTitles.join(', ')}]`;
            }
          }
          
          messages.push({
            role: "assistant",
            content: assistantContent
          });
        }
      }
    }
    
    // Add current query
    messages.push({ role: "user", content: query });
    
    const stream = await getClient().chat.completions.create({
      model: "gpt-4o-mini",
      stream: true,
      temperature: 0.3,
      messages: messages
    });

    let fullAnswer = "";

    for await (const chunk of stream) {
      const delta = chunk.choices?.[0]?.delta?.content;
      if (delta) {
        fullAnswer += delta;
        sse.send("message", delta);
      }
    }

    // Send end event with complete answer
    sse.send("end", {
      intent: "answer",
      summary: fullAnswer || `Here's a quick overview of "${query}".`,
      answer: fullAnswer || `Here's a quick overview of "${query}".`,
      sources: webResults.sources, // ✅ Include web search sources
      locations: [],
      destination_images: [],
      cards: [],
      cardType: null,
    });

    sse.close();
  } catch (err: any) {
    console.error("❌ Streaming failed:", err);
    
    const fallbackText = `Here's a quick overview of "${query}".`;
    sse.send("message", fallbackText);
    sse.send("end", {
      intent: "answer",
      summary: fallbackText,
      answer: fallbackText,
      sources: webResults.sources, // ✅ Include web search sources even on error
      locations: [],
      destination_images: [],
      cards: [],
      cardType: null,
    });
    sse.close();
  }
}
