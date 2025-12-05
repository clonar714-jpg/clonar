// src/reranker/cardReranker.ts
import { getEmbedding, cosine } from "../embeddings/embeddingClient";

// ---------- Extract price if exists ----------
function extractPrice(text: string): number | null {
  if (!text) return null;
  const match = text.replace(/,/g, "").match(/\$?(\d{2,5})(\.\d+)?/);
  if (!match) return null;
  return parseFloat(match[1]);
}

// ---------- Weight configuration ----------
const WEIGHTS = {
  semantic: 0.55,
  brand: 0.20,
  category: 0.15,
  price: 0.10,
};

// ---------- Helpers ----------
function extractBrand(q: string): string | null {
  const brands = [
    "nike", "puma", "adidas", "reebok", "new balance",
    "balmain", "rayban", "ray-ban", "gucci", "oakley",
    "apple", "samsung", "sony", "hp", "macbook",
    "fossil", "michael kors", "mk"
  ];
  const lower = q.toLowerCase();
  return brands.find((b) => lower.includes(b)) || null;
}

function extractPriceLimit(q: string): number | null {
  const m = q.match(/under\s*\$?(\d+)/i) || q.match(/\$?(\d+)\s*under/i);
  return m ? parseInt(m[1]) : null;
}

function extractCategory(q: string): string | null {
  const categories = [
    "shoes", "sneakers", "boots", "heels",
    "shirt", "tshirt", "t-shirt", "dress", "hoodie",
    "glasses", "sunglasses", "watch", "watches",
    "bag", "purse", "backpack",
    "laptop", "phone", "headphones", "earbuds"
  ];
  const lower = q.toLowerCase();
  return categories.find((x) => lower.includes(x)) || null;
}

/**
 * 🔥 C7 PATCH #5 — Boost Matching Attributes
 * Detects query attributes and adds score boosts
 */
function getAttributeBoosts(query: string, item: any): number {
  let boost = 0;
  const lowerQuery = query.toLowerCase();
  const lowerTitle = (item.title || "").toLowerCase();
  const lowerDesc = (item.description || item.snippet || "").toLowerCase();
  const combined = `${lowerTitle} ${lowerDesc}`;

  // Price-related boosts
  if (lowerQuery.includes("under") || lowerQuery.includes("cheap") || lowerQuery.includes("budget")) {
    const priceLimit = extractPriceLimit(query);
    const itemPrice = extractPrice(item.price || "");
    if (priceLimit && itemPrice && itemPrice <= priceLimit) {
      boost += 0.2; // Strong boost for matching price constraint
    }
  }

  // Use-case boosts
  if (lowerQuery.includes("running") && combined.includes("running")) {
    boost += 0.15;
  }
  if (lowerQuery.includes("walking") && combined.includes("walking")) {
    boost += 0.15;
  }
  if (lowerQuery.includes("long distance") && combined.includes("long distance")) {
    boost += 0.15;
  }
  if (lowerQuery.includes("best for") && combined.includes("best")) {
    boost += 0.1;
  }

  // Fit-related boosts
  if (lowerQuery.includes("wide fit") && combined.includes("wide")) {
    boost += 0.15;
  }
  if (lowerQuery.includes("narrow fit") && combined.includes("narrow")) {
    boost += 0.15;
  }
  if (lowerQuery.includes("true to size") && combined.includes("true to size")) {
    boost += 0.1;
  }

  // Material/feature boosts
  if (lowerQuery.includes("polarized") && combined.includes("polarized")) {
    boost += 0.15;
  }
  if (lowerQuery.includes("waterproof") && combined.includes("waterproof")) {
    boost += 0.15;
  }
  if (lowerQuery.includes("stainless steel") && combined.includes("stainless steel")) {
    boost += 0.1;
  }

  return Math.min(boost, 0.3); // Cap boost at 0.3 to prevent over-weighting
}

/**
 * 🔥 C7 PATCH #4 — Penalize Wrong Categories
 */
function applyCategoryPenalty(intent: string, item: any, baseScore: number): number {
  let score = baseScore;

  if (intent === "shopping") {
    // Penalize articles or non-product content
    if (item.sourceType === "article" || item.type === "article") {
      score *= 0.3; // 70% penalty
    }
    // Penalize if it's clearly not a product (no price, no buy link)
    if (!item.price && !item.link) {
      score *= 0.5;
    }
  }

  if (intent === "hotels" || intent === "hotel") {
    // Penalize if missing hotel-specific fields
    if (!item.name && !item.hotelName && !item.property_name) {
      score *= 0.3;
    }
    // Penalize if it's not a hotel (e.g., restaurant, attraction)
    if (item.type === "restaurant" || item.type === "attraction") {
      score *= 0.4;
    }
  }

  if (intent === "flights") {
    // Penalize if missing flight-specific fields
    if (!item.departure && !item.arrival && !item.airline) {
      score *= 0.3;
    }
  }

  if (intent === "restaurants") {
    // Penalize if missing restaurant-specific fields
    if (!item.name && !item.cuisine) {
      score *= 0.3;
    }
    // Penalize if it's not a restaurant
    if (item.type === "hotel" || item.type === "attraction") {
      score *= 0.4;
    }
  }

  return score;
}

/**
 * 🚀 C7 PATCH #1 — Main Reranker Function
 */
export async function rerankCards(query: string, items: any[], intent: string): Promise<any[]> {
  if (!items || items.length === 0) return [];

  // Get query embedding once
  const queryEmb = await getEmbedding(query);

  // Extract query attributes
  const brand = extractBrand(query);
  const priceLimit = extractPriceLimit(query);
  const category = extractCategory(query);

  // Score items
  const scored = await Promise.all(
    items.map(async (item) => {
      // Build item text for embedding
      const itemText = `${item.title || item.name || ""} ${item.description || item.snippet || ""}`.trim();
      
      if (!itemText) {
        return { ...item, finalScore: 0 };
      }

      // Get item embedding
      const itemEmb = await getEmbedding(itemText);

      // Semantic similarity score
      const semanticScore = cosine(queryEmb, itemEmb);

      // Brand match score
      const brandScore = brand && itemText.toLowerCase().includes(brand.toLowerCase())
        ? 1
        : 0;

      // Category match score
      const categoryScore = category && itemText.toLowerCase().includes(category.toLowerCase())
        ? 1
        : 0;

      // Price constraint score
      const itemPrice = extractPrice(item.price || "");
      const priceScore =
        priceLimit && itemPrice && itemPrice <= priceLimit ? 1 : 0;

      // Calculate base score
      let finalScore =
        semanticScore * WEIGHTS.semantic +
        brandScore * WEIGHTS.brand +
        categoryScore * WEIGHTS.category +
        priceScore * WEIGHTS.price;

      // 🔥 C7 PATCH #5 — Add attribute boosts
      const attributeBoost = getAttributeBoosts(query, item);
      finalScore += attributeBoost;

      // 🔥 C7 PATCH #4 — Apply category penalties
      finalScore = applyCategoryPenalty(intent, item, finalScore);

      return { ...item, finalScore };
    })
  );

  // Sort by highest score
  const sorted = scored.sort((a, b) => b.finalScore - a.finalScore);

  // Log top 3 scores for debugging
  if (sorted.length > 0) {
    console.log(`🎯 Reranked ${sorted.length} items. Top 3 scores:`, 
      sorted.slice(0, 3).map((s: any) => s.finalScore.toFixed(3))
    );
  }

  return sorted;
}

