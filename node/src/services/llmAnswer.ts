// =======================================================================
// C4 — ANSWER ENGINE (Perplexity-grade): ALWAYS RETURNS TEXT + STRUCTURE
// =======================================================================

import OpenAI from "openai";
import { Response } from "express";
import { SSE } from "../utils/sse";
import axios from "axios";
import { parseStructuredAnswer, ParsedAnswer } from "./answerParser";

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

import { generateSearchQuery, shouldGenerateQuery } from "./queryGenerator";
import { summarizeDocuments } from "./documentSummarizer";

/**
 * Search the web using SerpAPI to get live, current information
 * ✅ IMPROVEMENT: Now uses query generation and document summarization
 * Exported for evidence card fetching in decision queries
 */
export async function searchWeb(
  query: string,
  conversationHistory: any[] = [],
  enableSummarization: boolean = true
): Promise<{ snippets: string[], sources: any[] }> {
  const serpKey = process.env.SERPAPI_KEY;
  
  if (!serpKey) {
    console.warn("⚠️ SERPAPI_KEY not found, skipping web search");
    return { snippets: [], sources: [] };
  }

  try {
    // ✅ IMPROVEMENT: Generate optimized search query
    let searchQuery = query;
    if (shouldGenerateQuery(query, conversationHistory)) {
      try {
        searchQuery = await generateSearchQuery(query, conversationHistory);
      } catch (err: any) {
        console.warn("⚠️ Query generation failed, using original query:", err.message);
      }
    }

    const serpUrl = "https://serpapi.com/search.json";
    const params = {
      engine: "google",
      q: searchQuery,
      api_key: serpKey,
      num: 5, // Get top 5 results
      hl: "en",
      gl: "us",
    };

    console.log(`🔍 Searching web for: "${query}"${searchQuery !== query ? ` → "${searchQuery}"` : ''}`);
    const response = await axios.get(serpUrl, { params, timeout: 10000 });
    
    const organicResults = response.data.organic_results || [];
    let snippets: string[] = [];
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

    // ✅ IMPROVEMENT: Summarize long snippets if enabled
    if (enableSummarization && snippets.length > 0) {
      try {
        const originalLength = snippets.reduce((sum, s) => sum + s.length, 0);
        snippets = await summarizeDocuments(snippets, query);
        const newLength = snippets.reduce((sum, s) => sum + s.length, 0);
        const reduction = Math.round((1 - newLength / originalLength) * 100);
        console.log(`📝 Summarized snippets: ${originalLength} chars → ${newLength} chars (${reduction}% reduction)`);
      } catch (err: any) {
        console.warn("⚠️ Snippet summarization failed, using original snippets:", err.message);
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
    sections: [] as any[],
    uiRequirements: {
      needsImages: false,
      needsMaps: false,
      needsCards: false,
      needsLocationCards: false,
      needsDestinationImages: false,
    },
    metadata: {},
  };
}

/**
 * ✅ COMPARE INVARIANT: Filter decision-style language from COMPARE answers
 * Rewrites recommendation/decision phrases into neutral analytical language
 * ✅ CONTEXTUAL_COMPARE: Enhanced filtering for contextual comparisons with decisionAllowed = false
 */
export function filterCompareAnswer(answerText: string, decisionAllowed: boolean = true, isContextualCompare: boolean = false): string {
  if (!answerText) return answerText;
  
  let filtered = answerText;
  
  // ✅ CONTEXTUAL_COMPARE: Block placeholder summaries
  if (isContextualCompare) {
    const placeholderPatterns = [
      /^Here are the results for/i,
      /^Here's a quick overview/i,
      /^Here's a helpful overview/i,
    ];
    for (const pattern of placeholderPatterns) {
      if (pattern.test(answerText)) {
        // Replace with a neutral analytical opening
        answerText = answerText.replace(pattern, 'Here are the key differences:');
      }
    }
  }

  // Remove or rewrite decision/recommendation phrases
  const decisionPhrases = [
    { pattern: /\byou should\b/gi, replacement: 'One option is' },
    { pattern: /\byour choice depends\b/gi, replacement: 'The choice depends' },
    { pattern: /\bbest for\b/gi, replacement: 'suited for' },
    { pattern: /\bideal for\b/gi, replacement: 'well-suited for' },
    { pattern: /\brecommended\b/gi, replacement: 'notable' },
    { pattern: /\bultimately\b/gi, replacement: 'In summary' },
    { pattern: /\bbetter overall\b/gi, replacement: 'different overall' },
    { pattern: /\bbest choice\b/gi, replacement: 'one option' },
    { pattern: /\bthe winner\b/gi, replacement: 'one option' },
    { pattern: /\bI recommend\b/gi, replacement: 'One consideration is' },
    { pattern: /\bI'd recommend\b/gi, replacement: 'One consideration is' },
    { pattern: /\bwould recommend\b/gi, replacement: 'would note' },
    { pattern: /\bfor you\b/gi, replacement: 'for this use case' },
    { pattern: /\bfor your\b/gi, replacement: 'for this' },
  ];
  
  // ✅ CONTEXTUAL_COMPARE: If decisionAllowed = false, add stricter patterns
  if (!decisionAllowed) {
    decisionPhrases.push(
      { pattern: /\bbetter\b/gi, replacement: 'differs' },
      { pattern: /\bbest\b/gi, replacement: 'notable' },
      { pattern: /\bsuperior\b/gi, replacement: 'different' },
      { pattern: /\bwinner\b/gi, replacement: 'option' },
      { pattern: /\bshould choose\b/gi, replacement: 'could consider' },
      { pattern: /\bideal\b/gi, replacement: 'suitable' },
    );
  }
  
  for (const { pattern, replacement } of decisionPhrases) {
    filtered = filtered.replace(pattern, replacement);
  }
  
  // Remove recommendation-style conclusions at the end
  // Look for patterns like "Ultimately, X is better" or "In conclusion, you should choose X"
  const conclusionPatterns = [
    /(?:ultimately|in conclusion|overall|finally|to conclude)[^.]*\./gi,
    /(?:you should|I recommend|best choice|ideal choice)[^.]*\./gi,
  ];
  
  for (const pattern of conclusionPatterns) {
    filtered = filtered.replace(pattern, '');
  }
  
  // Ensure the answer ends with a neutral summary, not a recommendation
  // If the last sentence contains decision language, rewrite it
  const sentences = filtered.split(/[.!?]+/).filter(s => s.trim().length > 0);
  if (sentences.length > 0) {
    const lastSentence = sentences[sentences.length - 1];
    const hasDecisionLanguage = /\b(should|recommend|best|ideal|winner|choose)\b/i.test(lastSentence);
    
    if (hasDecisionLanguage) {
      // Rewrite last sentence to be neutral
      let neutralLast = lastSentence
        .replace(/\b(should|recommend|best|ideal|winner)\b/gi, 'notable')
        .replace(/\bchoose\b/gi, 'consider');
      
      // If it's still too recommendation-like, replace with a neutral summary
      if (/\b(should|recommend|best|ideal|winner)\b/i.test(neutralLast)) {
        neutralLast = 'These are the key differences to consider.';
      }
      
      sentences[sentences.length - 1] = neutralLast;
      filtered = sentences.join('. ') + '.';
    }
  }
  
  // Clean up any double spaces or punctuation issues
  filtered = filtered.replace(/\s+/g, ' ').trim();
  
  return filtered;
}

// =======================================================================
// NON-STREAMED ANSWER
// =======================================================================

export async function getAnswerNonStream(
  query: string, 
  history: any[], 
  isClarificationOnly: boolean = false,
  confidenceBand?: "high" | "medium" | "low",
  userGoal?: "browse" | "compare" | "choose" | "decide" | "learn" | "locate",
  answerPlan?: any,
  answerSketch?: any, // ✅ PERPLEXITY UPGRADE: Early answer commitment
  reasoningLevel?: "minimal" | "balanced" | "deep", // ✅ PERPLEXITY UPGRADE: Reasoning density control
  reuseWebResults?: { snippets: string[], sources: any[] }, // ✅ Improvement 2: Skip second web search on regeneration
  responseIntent?: string, // ✅ PERPLEXITY-STYLE: Intent for structured answer generation
  dataRequirements?: { // ✅ LLM-DRIVEN: Data sources decided by LLM
    needsWebSearch: boolean;
    needsShoppingAPI: boolean;
    needsHotelAPI: boolean;
    needsRestaurantAPI: boolean;
    needsFlightAPI: boolean;
    needsMovieAPI: boolean;
    needsPlaceAPI: boolean;
    reason: string;
  }
) {
  // ✅ PERPLEXITY-STYLE: Always do web search (Perplexity always searches the web)
  // ✅ SIMPLIFIED: Remove conditional logic - always search for live, current information
  let webResults: { snippets: string[], sources: any[] } = { snippets: [], sources: [] };
  
  if (reuseWebResults) {
    console.log("♻️ Reusing web results from initial search (regeneration pass)");
    webResults = reuseWebResults;
  } else {
    console.log("🔍 Perplexity-style: Searching web for current information...");
    webResults = await searchWeb(query, history, true); // Enable summarization
  }
  
  const webContext = webResults.snippets.length > 0
    ? `\n\nCURRENT WEB INFORMATION:\n${webResults.snippets.join('\n\n')}\n`
    : '';

  // ✅ CLARIFICATION-ONLY MODE: No examples, no assumptions, no guesses
  if (isClarificationOnly) {
    const clarificationSystem = `
You must ask ONE short clarification question.
Do NOT give examples.
Do NOT guess location.
Do NOT provide recommendations.
Do NOT make assumptions.
Just ask what information is needed to answer the query.
Keep it to ONE sentence maximum.
`;

    try {
      const messages: any[] = [
        { role: "system", content: clarificationSystem },
        { role: "user", content: query }
      ];
      
      const res = await getClient().chat.completions.create({
        model: "gpt-4o-mini",
        temperature: 0.3,
        max_tokens: 50,
        messages: messages
      });

      const content = res.choices[0]?.message?.content || "";
      return {
        answer: content || "Could you provide more details?",
        summary: content || "Could you provide more details?",
        sources: [],
        locations: [],
        destination_images: [],
      };
    } catch (err: any) {
      console.error("❌ Clarification generation failed:", err);
      return {
        answer: "Could you provide more details?",
        summary: "Could you provide more details?",
        sources: [],
        locations: [],
        destination_images: [],
      };
    }
  }

  // ✅ COMPARE INVARIANT: Special instructions for comparison queries
  const isCompareQuery = userGoal === "compare";
  const answerPlanSubIntent = answerPlan?.subIntent;
  const isContextualCompare = answerPlanSubIntent === "contextual_compare";
  const decisionAllowed = answerPlan?.decisionAllowed !== false; // Default to true if not specified
  
  const compareInstructions = isCompareQuery ? `
- CRITICAL FOR COMPARISON QUERIES: You must provide a purely analytical and descriptive comparison.
- Do NOT include recommendations, decision guidance, or user-directed conclusions.
- Do NOT use phrases like: "you should", "your choice depends", "best for", "ideal for", "recommended", "ultimately", "better overall", "best choice".
- End with a neutral summary of differences, NOT a suggestion or conclusion.
- Tone must match: "Here are the key differences between A and B" - analytical and factual only.
- Focus on objective differences: features, specifications, performance metrics, use cases.
- Do NOT declare winners or make recommendations.
${isContextualCompare ? `
- ✅ CONTEXTUAL_COMPARE: This is a comparison of abstract concepts (categories, formats, technologies).
- Explain differences in context. Do not choose a winner. Do not recommend unless explicitly asked.
- You MUST provide at least 3 distinct comparison dimensions (e.g., technical specs, use cases, advantages, limitations).
- NEVER generate placeholder summaries like "Here are the results for..." - provide actual analytical content.
- Focus on explaining HOW these concepts differ, not WHICH one to choose.
` : ''}
${!decisionAllowed ? `
- ✅ GUARDRAIL: Decision language is BLOCKED. Do NOT use any language implying a final verdict, recommendation, or choice.
- Do NOT say: "better", "best", "recommended", "should choose", "ideal", "winner", "superior".
- Use neutral language: "differs in", "has different", "varies in", "distinguishes by".
` : ''}
` : '';

  // ✅ PERPLEXITY-STYLE: Always generate structured answers (like Perplexity)
  // Perplexity always provides detailed, structured answers with sections
  const system = `
You are Perplexity AI. Generate detailed, comprehensive answers using CURRENT, LIVE information from the web.

ANSWER STRUCTURE (ALWAYS FOLLOW THIS):
1. Opening Paragraph (2-3 sentences)
   - Set context and introduce the topic
   - Provide background information
   - State the purpose of the answer

2. Categorized Sections (3-6 sections)
   - Use clear section headings (title case, on their own line)
   - Each section: 2-4 items with specific details
   - Include specific names, prices, features when available

3. Conclusion Paragraph (2-3 sentences)
   - Summarize key points
   - Provide guidance or next steps
   - End with encouragement or actionable advice

SECTION ORGANIZATION BY QUERY TYPE:
- Shopping queries: Organize by product type (e.g., "Running Shoes", "Lifestyle Sneakers", "Basketball Shoes")
- Hotel queries: Organize by price range (e.g., "Luxury Hotels", "Mid-Range Hotels", "Budget-Friendly Options")
- Comparison queries: Organize by comparison dimensions (e.g., "Design and Build Quality", "Display", "Performance", "Camera Capabilities")
- Learning queries: Organize by concept aspects (e.g., "What is OLED?", "What is AMOLED?", "Key Differences")
- General queries: Organize by topic aspects or categories

CONTENT REQUIREMENTS (CRITICAL):
- ✅ Include SPECIFIC names: Mention actual product names, hotel names, movie titles, brands, etc.
- ✅ Include prices when available: "$130", "around $160", "Starting around $1,999", "priced at $299"
- ✅ Include specific features: Mention key specs, amenities, characteristics, technical details
- ✅ Be detailed: Each section should have 2-4 items with comprehensive details
- ✅ Use factual, current information from web search (prioritize web info over training data)
- ✅ Length: 300-500 words for commerce queries, 200-400 words for general queries

EXAMPLE STRUCTURE for "hotels in Salt Lake City":

Salt Lake City, the capital of Utah, is known for its stunning natural beauty and vibrant downtown area. Whether you're visiting for business or leisure, the city offers a diverse range of accommodations to suit every traveler's needs and budget.

Luxury Hotels
The Grand America Hotel stands out as one of the city's premier luxury accommodations, offering elegant rooms starting around $250 per night. This five-star hotel features a full-service spa, multiple dining options, and is located in the heart of downtown. The Kimpton Hotel Monaco Salt Lake City provides a boutique luxury experience with rates around $200 per night, featuring unique design elements and a rooftop bar with stunning city views.

Mid-Range Hotels
Courtyard by Marriott Salt Lake City Airport offers comfortable accommodations near the airport with rates around $120 per night. The hotel features modern rooms, a fitness center, and complimentary airport shuttle service. Crystal Inn Hotel & Suites provides excellent value in downtown Salt Lake City, with spacious suites starting around $100 per night, including complimentary breakfast and free parking.

Budget-Friendly Options
My Place Hotel offers extended-stay accommodations with kitchenettes, starting around $80 per night. The hotel provides a convenient location with easy access to downtown attractions. Little America Hotel provides classic comfort at affordable rates around $90 per night, featuring well-appointed rooms and a central location.

Salt Lake City's hotel scene caters to every type of traveler, from luxury seekers to budget-conscious visitors. The city's central location makes it an ideal base for exploring Utah's natural wonders, while downtown hotels offer easy access to restaurants, shopping, and cultural attractions.

FORMAT RULES:
- NO markdown symbols like **, ##, *, >
- NO code blocks
- Use plain text with clear section headings (title case, on their own line)
- Write in a conversational, informative tone (like Perplexity)
- Include factual data from web search
- NEVER mention that you are an AI
- NEVER say "as an AI model"
- Do not hallucinate numbers or prices
- Use the CURRENT WEB INFORMATION provided below to answer with LIVE, UP-TO-DATE facts
- If web information is provided, prioritize it over your training data
- For current events, dates, or recent information, ONLY use the web information provided
${compareInstructions}

IMPORTANT: Use conversation context for follow-up queries.
- If the user asks a follow-up question (e.g., "show me luxury ones", "more costlier", "cheaper options"), you MUST understand it in the context of the previous conversation
- For follow-up queries, reference the previous query's topic/subject to provide a complete answer
- Example: If previous query was "hand made chairs" and user asks "more costlier", understand it as "more costlier handmade chairs"
- Example: If previous query was "hotels in Miami" and user asks "luxury ones", understand it as "luxury hotels in Miami"
- Only treat queries as independent if they are clearly starting a new topic
- Provide a fresh answer that incorporates the context from previous messages

${webContext}

---

CRITICAL: After your answer, include UI requirements in this exact format:

UI_REQUIREMENTS:
{
  "needsImages": true/false,
  "needsMaps": true/false,
  "needsCards": true/false,
  "needsLocationCards": true/false,
  "needsDestinationImages": true/false,
  "reason": "brief explanation of why these UI elements are needed"
}

DECISION RULES for UI elements:
- needsImages: true if answer mentions products/hotels/movies that would benefit from visual representation
- needsMaps: true if answer mentions locations, hotels, restaurants, or places that need geographic visualization
- needsCards: true if answer lists specific items (products, hotels, movies) that should be shown as cards
- needsLocationCards: true if answer mentions places/attractions that need location-based cards
- needsDestinationImages: true if answer mentions destinations/travel locations that need destination images
- Be intelligent: Only set to true if the UI element genuinely enhances the answer
- Example: "hotels in Salt Lake City" → needsMaps: true, needsCards: true, needsImages: true
- Example: "what is Docker" → needsMaps: false, needsCards: false, needsImages: false
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
      max_tokens: 1200, // ✅ PERPLEXITY-STYLE: Always 300-500 words (1200 tokens)
      messages: messages
    });

    const content = res.choices[0]?.message?.content || "";
    if (!content.trim()) return buildFallbackAnswer(query);

    // ✅ PERPLEXITY-STYLE: Parse structured answer with UI requirements
    const parsed = parseStructuredAnswer(content);
    
    console.log(`📝 Parsed answer: ${parsed.sections.length} sections, UI requirements:`, parsed.uiRequirements);

    return {
      answer: parsed.answer,
      summary: parsed.summary,
      sources: webResults.sources, // ✅ Include web search sources
      locations: [] as any[],
      destination_images: [] as string[],
      // ✅ PERPLEXITY-STYLE: Include parsed structure
      sections: parsed.sections,
      uiRequirements: parsed.uiRequirements,
      metadata: parsed.metadata,
    };
  } catch (err: any) {
    console.error("❌ Answer generation failed:", err);
    return buildFallbackAnswer(query);
  }
}

// =======================================================================
// STREAMING ANSWER (PERPLEXITY-STYLE)
// =======================================================================

export async function getAnswerStream(
  query: string, 
  history: any[], 
  res: Response,
  answerSketch?: any, // ✅ PERPLEXITY UPGRADE: Early answer commitment
  reasoningLevel?: "minimal" | "balanced" | "deep", // ✅ PERPLEXITY UPGRADE: Reasoning density control
  userGoal?: "browse" | "compare" | "choose" | "decide" | "learn" | "locate" // ✅ COMPARE INVARIANT: For answer filtering
) {
  // ✅ STEP 1: Search the web for live, current information
  // ✅ IMPROVEMENT: Pass conversation history for query generation and enable summarization
  const webResults = await searchWeb(query, history, true);
  const webContext = webResults.snippets.length > 0
    ? `\n\nCURRENT WEB INFORMATION:\n${webResults.snippets.join('\n\n')}\n`
    : '';

  // ✅ PERPLEXITY UPGRADE: Apply reasoning density control and stance guidance
  let verbosityGuidance = "";
  if (reasoningLevel === "minimal") {
    verbosityGuidance = "Keep your answer VERY brief (1-2 sentences, 30-50 words). Lead with the verdict/stance immediately. Skip detailed reasoning unless critical.";
  } else if (reasoningLevel === "deep") {
    verbosityGuidance = "Provide detailed reasoning (4-6 sentences, 100-150 words). Explain the 'why' behind your answer. Include context and nuance.";
  } else {
    verbosityGuidance = "Provide balanced reasoning (2-4 sentences, 50-100 words). Include key points without excessive detail.";
  }

  let stanceGuidance = "";
  if (answerSketch) {
    if (answerSketch.stance === "lean_yes") {
      stanceGuidance = "Lead with a positive stance. Start with 'Yes' or 'Recommended' if appropriate.";
    } else if (answerSketch.stance === "lean_no") {
      stanceGuidance = "Lead with a negative stance. Start with 'No' or 'Not recommended' if appropriate.";
    } else if (answerSketch.stance === "depends") {
      stanceGuidance = "Lead with 'It depends' and explain the key dimensions that matter.";
    } else {
      stanceGuidance = "Provide a clear explanation without taking a stance.";
    }
  }

  // ✅ COMPARE INVARIANT: Special instructions for comparison queries
  const isCompareQuery = userGoal === "compare";
  // Note: For streaming, answerPlan is not passed, so we can't detect contextual_compare here
  // The filtering will happen post-processing
  const compareInstructions = isCompareQuery ? `
- CRITICAL FOR COMPARISON QUERIES: You must provide a purely analytical and descriptive comparison.
- Do NOT include recommendations, decision guidance, or user-directed conclusions.
- Do NOT use phrases like: "you should", "your choice depends", "best for", "ideal for", "recommended", "ultimately", "better overall", "best choice".
- End with a neutral summary of differences, NOT a suggestion or conclusion.
- Tone must match: "Here are the key differences between A and B" - analytical and factual only.
- Focus on objective differences: features, specifications, performance metrics, use cases.
- Do NOT declare winners or make recommendations.
` : '';

  const system = `
You produce Perplexity-style streamed answers.
Plain text only. No markdown. No symbols like *, **, ##.
✅ PERPLEXITY UPGRADE: ${stanceGuidance}
✅ PERPLEXITY UPGRADE: ${verbosityGuidance}
${compareInstructions}
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
    let firstSentenceSent = false;
    let buffer = "";

    // ✅ PERPLEXITY UPGRADE: Streaming order optimization
    // Send verdict/stance sentence FIRST, then supporting reasoning
    for await (const chunk of stream) {
      const delta = chunk.choices?.[0]?.delta?.content;
      if (delta) {
        fullAnswer += delta;
        buffer += delta;
        
        // ✅ PERPLEXITY UPGRADE: Detect first sentence (verdict/stance)
        if (!firstSentenceSent && (buffer.includes('.') || buffer.includes('?') || buffer.length > 100)) {
          // Send first sentence immediately (verdict/stance)
          const firstSentenceEnd = buffer.indexOf('.');
          if (firstSentenceEnd > 0) {
            const firstSentence = buffer.substring(0, firstSentenceEnd + 1);
            sse.send("verdict", firstSentence); // ✅ PERPLEXITY UPGRADE: Send verdict first
            buffer = buffer.substring(firstSentenceEnd + 1);
            firstSentenceSent = true;
          } else if (buffer.length > 100) {
            // Fallback: send first 100 chars if no period found
            sse.send("verdict", buffer.substring(0, 100));
            buffer = buffer.substring(100);
            firstSentenceSent = true;
          }
        }
        
        // ✅ PERPLEXITY UPGRADE: Send remaining content as supporting reasoning
        if (firstSentenceSent && buffer.length > 0) {
          sse.send("message", buffer);
          buffer = "";
        }
      }
    }
    
    // ✅ PERPLEXITY UPGRADE: Send any remaining buffer
    if (buffer.length > 0) {
      sse.send("message", buffer);
    }

    // ✅ COMPARE INVARIANT: Filter decision-style language from COMPARE answers
    let finalAnswer = fullAnswer || `Here's a quick overview of "${query}".`;
    if (userGoal === "compare") {
      const originalText = finalAnswer;
      finalAnswer = filterCompareAnswer(finalAnswer);
      if (originalText !== finalAnswer) {
        console.log(`🔀 COMPARE GOAL: Filtered decision-style language from streaming answer`);
      }
    }

    // Send end event with complete answer
    sse.send("end", {
      intent: "answer",
      summary: finalAnswer,
      answer: finalAnswer,
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
