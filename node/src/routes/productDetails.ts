// src/routes/productDetails.ts
import express from "express";
import { Request, Response } from "express";
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

const router = express.Router();

/**
 * Generate product-specific details:
 * - What people say (customer reviews summary)
 * - Buy this if (use case recommendations)
 * - Key Features (product features list)
 */
router.post("/", async (req: Request, res: Response) => {
  try {
    const { title, description, price, rating, source, category } = req.body;

    if (!title) {
      return res.status(400).json({ error: "Product title is required" });
    }

    // Build product context
    const productInfo = `
Product Title: ${title}
${description ? `Description: ${description}` : ''}
${price ? `Price: $${price}` : ''}
${rating ? `Rating: ${rating}/5` : ''}
${source ? `Source: ${source}` : ''}
${category ? `Category: ${category}` : ''}
`.trim();

    const systemPrompt = `You are a product information expert. Generate accurate, helpful product details based on the product information provided.

Generate THREE sections in JSON format:
1. "whatPeopleSay" - A 2-3 sentence summary of what customers typically say about this product (based on common reviews for similar products). Be realistic and specific.
2. "buyThisIf" - A 2-3 sentence recommendation about who should buy this product and when it's most suitable. Be practical and helpful.
3. "keyFeatures" - An array of 4-6 specific key features or benefits of this product. Each feature should be a short phrase (3-6 words).

Rules:
- Be specific to the product type and category
- Use natural, conversational language
- Don't make up specific numbers or statistics
- Focus on practical benefits
- Return ONLY valid JSON, no markdown, no extra text

Example format:
{
  "whatPeopleSay": "Customers appreciate the...",
  "buyThisIf": "You should buy this if...",
  "keyFeatures": ["Feature 1", "Feature 2", "Feature 3"]
}`;

    try {
      const client = getOpenAIClient();
      const response = await client.chat.completions.create({
        model: "gpt-4o-mini",
        temperature: 0.5,
        messages: [
          { role: "system", content: systemPrompt },
          {
            role: "user",
            content: `Generate product details for:\n\n${productInfo}\n\nReturn ONLY the JSON object with whatPeopleSay, buyThisIf, and keyFeatures fields.`,
          },
        ],
      });

      const content = response.choices[0]?.message?.content || "";
      
      // Try to parse JSON from response
      let productDetails: any = {};
      try {
        // Extract JSON from markdown code blocks if present
        const jsonMatch = content.match(/\{[\s\S]*\}/);
        if (jsonMatch) {
          productDetails = JSON.parse(jsonMatch[0]);
        } else {
          productDetails = JSON.parse(content);
        }
      } catch (e) {
        console.error("❌ Failed to parse LLM response as JSON:", e);
        // Fallback to default values
        productDetails = getDefaultProductDetails(title, category);
      }

      // Ensure all required fields exist
      if (!productDetails.whatPeopleSay) {
        productDetails.whatPeopleSay = getDefaultWhatPeopleSay(title);
      }
      if (!productDetails.buyThisIf) {
        productDetails.buyThisIf = getDefaultBuyThisIf(title);
      }
      if (!productDetails.keyFeatures || !Array.isArray(productDetails.keyFeatures)) {
        productDetails.keyFeatures = getDefaultKeyFeatures(title, category);
      }

      return res.json(productDetails);
    } catch (err: any) {
      console.error("❌ LLM product details generation error:", err.message || err);
      // Return default values on error
      return res.json(getDefaultProductDetails(title, category));
    }
  } catch (err: any) {
    console.error("❌ Error generating product details:", err);
    return res.status(500).json({ 
      error: "Failed to generate product details",
      whatPeopleSay: "Customers appreciate the quality and value of this product.",
      buyThisIf: "This product is ideal for those seeking quality and reliability.",
      keyFeatures: ["Quality materials", "Reliable performance", "Good value"]
    });
  }
});

// Default fallback functions
function getDefaultProductDetails(title: string, category?: string): any {
  return {
    whatPeopleSay: getDefaultWhatPeopleSay(title),
    buyThisIf: getDefaultBuyThisIf(title),
    keyFeatures: getDefaultKeyFeatures(title, category),
  };
}

function getDefaultWhatPeopleSay(title: string): string {
  const lowerTitle = title.toLowerCase();
  if (lowerTitle.includes("watch")) {
    return "Customers love the elegant design and reliable timekeeping. Many reviewers mention the comfortable fit and durable construction.";
  } else if (lowerTitle.includes("shoe") || lowerTitle.includes("sneaker")) {
    return "Customers appreciate the comfort and style of these shoes. Many reviewers mention the excellent fit and durability.";
  } else if (lowerTitle.includes("phone") || lowerTitle.includes("smartphone")) {
    return "Users praise the performance and camera quality. Many mention the long battery life and smooth user experience.";
  } else if (lowerTitle.includes("laptop")) {
    return "Customers value the performance and build quality. Reviewers often highlight the fast processing speed and reliable battery life.";
  } else {
    return "Customers appreciate the quality and value of this product. Many reviewers mention the good build quality and reliable performance.";
  }
}

function getDefaultBuyThisIf(title: string): string {
  const lowerTitle = title.toLowerCase();
  if (lowerTitle.includes("watch")) {
    return "You want a stylish timepiece that combines elegance with functionality. Perfect for both formal occasions and everyday wear.";
  } else if (lowerTitle.includes("shoe") || lowerTitle.includes("sneaker")) {
    return "You want a versatile sneaker that works for both casual wear and light athletic activities. Perfect for everyday comfort.";
  } else if (lowerTitle.includes("phone") || lowerTitle.includes("smartphone")) {
    return "You need a reliable smartphone with good performance and camera capabilities. Ideal for daily use and staying connected.";
  } else if (lowerTitle.includes("laptop")) {
    return "You need a reliable laptop for work or study. Perfect for productivity tasks and everyday computing needs.";
  } else {
    return "You want a quality product that offers good value. Ideal for those seeking reliability and performance.";
  }
}

function getDefaultKeyFeatures(title: string, category?: string): string[] {
  const lowerTitle = title.toLowerCase();
  if (lowerTitle.includes("watch")) {
    return ["Elegant design", "Reliable timekeeping", "Comfortable fit", "Durable construction", "Water resistant"];
  } else if (lowerTitle.includes("shoe") || lowerTitle.includes("sneaker")) {
    return ["Comfortable fit", "Durable materials", "Versatile styling", "Breathable design", "Good support"];
  } else if (lowerTitle.includes("phone") || lowerTitle.includes("smartphone")) {
    return ["High performance", "Quality camera", "Long battery life", "Fast charging", "Smooth interface"];
  } else if (lowerTitle.includes("laptop")) {
    return ["Fast processing", "Reliable battery", "Quality display", "Lightweight design", "Good connectivity"];
  } else {
    return ["Quality materials", "Reliable performance", "Good value", "Durable construction", "User-friendly design"];
  }
}

export default router;

