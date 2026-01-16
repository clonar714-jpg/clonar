// src/routes/generateSuggestions.ts
import express from "express";
import { Request, Response } from "express";
import generateSuggestions from "../agent/suggestionGenerator";
import ModelRegistry from "../models/registry";
import { ChatTurnMessage } from "../agent/types";

const router = express.Router();

/* =====================================================
   PERPLEXITY-STYLE FOLLOW-UP GENERATOR (FINAL VERSION)
   
   ✅ PERPLEXICA PATTERN SUPPORT:
   - Accepts chatModel from client: { providerId: string, key: string }
   - Supports tuple format: [["human", "query"], ["assistant", "answer"]]
   - Endpoint: /api/chat/generate-suggestions (POST)
   ===================================================== */

router.post("/", async (req: Request, res: Response) => {
  try {
    // ✅ FIX: Extract chatModel from request body (Perplexica pattern)
    // Request body format:
    // {
    //   conversationHistory: [["human", "query"], ["assistant", "answer"]] | ChatTurnMessage[],
    //   chatModel?: { providerId: string, key: string }
    // }
    const { conversationHistory, chatModel } = req.body;

    // Convert conversation history to ChatTurnMessage format
    let chatHistory: ChatTurnMessage[] = [];
    
    if (Array.isArray(conversationHistory)) {
      // ✅ PERPLEXICA PATTERN: Check if conversationHistory is already in tuple format [string, string][]
      // e.g., [["human", "query"], ["assistant", "answer"]]
      if (conversationHistory.length > 0 && Array.isArray(conversationHistory[0]) && conversationHistory[0].length === 2) {
        // Direct tuple format - convert each tuple to ChatTurnMessage
        chatHistory = conversationHistory.map((tuple: [string, string]) => ({
          role: tuple[0] === 'human' ? 'user' : tuple[0] === 'assistant' ? 'assistant' : tuple[0],
          content: tuple[1],
        })) as ChatTurnMessage[];
      } else {
        // Handle different conversation history formats (object-based)
        chatHistory = conversationHistory.map((turn: any) => {
          // Handle different conversation history formats
          if (turn.role && turn.content) {
            // Already in ChatTurnMessage format
            return {
              role: turn.role === 'human' ? 'user' : turn.role === 'assistant' ? 'assistant' : turn.role,
              content: turn.content,
            };
          } else if (turn.query && turn.answer) {
            // Old format: { query: string, answer: string }
            return [
              { role: 'user' as const, content: turn.query },
              { role: 'assistant' as const, content: turn.answer },
            ];
          } else if (Array.isArray(turn) && turn.length === 2) {
            // Tuple format within object array: [role, content]
            return {
              role: turn[0] === 'human' ? 'user' : turn[0] === 'assistant' ? 'assistant' : turn[0],
              content: turn[1],
            };
          }
          return null;
        }).filter(Boolean).flat() as ChatTurnMessage[];
      }
    }

    // If no conversation history, return empty suggestions
    if (chatHistory.length === 0) {
      return res.json({ suggestions: [] });
    }

    // ✅ IMPROVEMENT: Use ModelRegistry to load LLM (supports multiple providers)
    const modelRegistry = new ModelRegistry();
    
    let llm;
    try {
      // ✅ FIX: Use provided chatModel from request body (Perplexica pattern)
      // chatModel format: { providerId: string, key: string }
      if (chatModel?.providerId && chatModel?.key) {
        llm = await modelRegistry.loadChatModel(chatModel.providerId, chatModel.key);
      } else {
        // Fallback: Get first available OpenAI provider and use default model
        const providers = await modelRegistry.getActiveProviders();
        const openAIProvider = providers.find(p => p.id.includes('openai') || p.name.toLowerCase().includes('openai'));
        if (openAIProvider && openAIProvider.chatModels.length > 0) {
          // Find the provider ID from activeProviders
          const activeProvider = modelRegistry.activeProviders.find(
            p => p.id === openAIProvider.id || p.name.toLowerCase().includes('openai')
          );
          if (activeProvider) {
            llm = await modelRegistry.loadChatModel(activeProvider.id, openAIProvider.chatModels[0].key);
          } else {
            throw new Error('No OpenAI provider found');
          }
        } else {
          throw new Error('No model providers configured');
        }
      }
    } catch (error: any) {
      console.error('❌ Failed to load LLM from registry:', error);
      // Fallback to template suggestions
      const lastMessage = chatHistory[chatHistory.length - 1];
      const query = lastMessage?.content || '';
      return res.json({
        suggestions: generateTemplateSuggestions({
          query,
          answer: '',
          results: [],
          intent: 'answer',
        }),
      });
    }

    // Generate suggestions using the new structured generator
    let suggestions: string[] = [];
    
    try {
      suggestions = await generateSuggestions(
        { chatHistory },
        llm
      );
      
      // Ensure we have at least some suggestions (the prompt asks for 4-5)
      if (suggestions.length === 0) {
        throw new Error('No suggestions generated');
      }
    } catch (err: any) {
      console.error("❌ Structured suggestion generation error:", err.message || err);
      
      // Fallback to template suggestions if structured generation fails
      const lastMessage = chatHistory[chatHistory.length - 1];
      const query = lastMessage?.content || '';
      suggestions = generateTemplateSuggestions({
        query,
        answer: '',
        results: [],
        intent: 'answer',
      });
    }

    return res.json({ suggestions });
  } catch (err: any) {
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

function generateTemplateSuggestions({ query, results, intent }: {
  query: string;
  answer?: string;
  results: any[];
  intent: string;
}): string[] {
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

