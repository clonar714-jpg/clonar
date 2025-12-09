// src/services/productDescriptionGenerator.ts
import OpenAI from "openai";

// Lazy-load OpenAI client
let clientInstance: OpenAI | null = null;

function getOpenAIClient(): OpenAI {
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

/**
 * 🎯 Perplexity-Style Product Description Generator
 * 
 * Generates concise 1 sentence product descriptions exactly like Perplexity:
 * - AI-written, not copied from retailer descriptions
 * - Highlights key features, materials, design, and intended use
 * - Concise (1 sentence, 20-40 words)
 * - Natural, human-written style
 * - Focuses on what makes the product unique or valuable
 */
export async function generateProductDescription(params: {
  title: string;
  price?: string;
  rating?: number;
  category?: string;
  provider?: string;
  images?: string[];
  rawDescription?: string; // For context only, not to copy
  features?: string[];
  materials?: string[];
}): Promise<string> {
  try {
    const client = getOpenAIClient();

    // Build context from available data
    const contextParts: string[] = [];
    
    if (params.category) {
      contextParts.push(`Category: ${params.category}`);
    }
    
    if (params.features && params.features.length > 0) {
      contextParts.push(`Features: ${params.features.join(', ')}`);
    }
    
    if (params.materials && params.materials.length > 0) {
      contextParts.push(`Materials: ${params.materials.join(', ')}`);
    }
    
    if (params.price) {
      contextParts.push(`Price: ${params.price}`);
    }
    
    if (params.rating && params.rating > 0) {
      contextParts.push(`Rating: ${params.rating}/5`);
    }

    const context = contextParts.length > 0 ? contextParts.join('\n') : 'No additional context available.';

    const systemPrompt = `You are a product description writer for a search engine (like Perplexity). Your task is to write concise, informative product descriptions.

RULES:
1. Write 1 sentence (20-40 words total) - Concise and to the point
2. DO NOT copy or paraphrase the retailer's description
3. Highlight key features, materials, design, and intended use
4. Write in a natural, human-written style
5. Focus on what makes this product unique or valuable
6. Be factual and avoid exaggeration
7. If you don't have enough information, write a brief, general description based on the product title

EXAMPLE GOOD DESCRIPTIONS:
- "These running shoes feature a lightweight mesh upper with responsive cushioning, ideal for daily training and long-distance runs."
- "A versatile backpack with multiple compartments and padded laptop sleeve, suitable for work and travel."
- "Premium wireless headphones with active noise cancellation and 30-hour battery life, featuring comfortable over-ear design."`;

    const userPrompt = `Write a Perplexity-style product description for:

Product: ${params.title}

Context:
${context}

${params.rawDescription ? `Note: The retailer's description mentions: "${params.rawDescription.substring(0, 200)}..." - Use this only for context, DO NOT copy it.` : ''}

Write a concise 1 sentence description (20-40 words) that highlights key features, materials, design, and intended use. Make it sound natural and human-written, not like a marketing copy.`;

    const response = await client.chat.completions.create({
      model: "gpt-4o-mini",
      messages: [
        { role: "system", content: systemPrompt },
        { role: "user", content: userPrompt },
      ],
      max_tokens: 100, // ✅ Reduced to enforce 1 sentence (20-40 words)
      temperature: 0.7,
    });

    const description = response.choices[0]?.message?.content?.trim() || "";

    if (!description || description.length < 20) {
      // Fallback: Generate a simple description from title
      return `A ${params.category || 'product'} designed for ${params.features && params.features.length > 0 ? params.features[0].toLowerCase() : 'everyday use'}. ${params.materials && params.materials.length > 0 ? `Made with ${params.materials[0]} materials.` : 'Offers quality and functionality.'}`;
    }

    return description;
  } catch (error: any) {
    console.error("❌ Error generating product description:", error.message);
    // Fallback description
    return `A quality ${params.category || 'product'} offering ${params.features && params.features.length > 0 ? params.features[0].toLowerCase() : 'reliable performance'}. ${params.materials && params.materials.length > 0 ? `Constructed with ${params.materials[0]} for durability.` : 'Designed for everyday use.'}`;
  }
}

