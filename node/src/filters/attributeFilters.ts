// src/filters/attributeFilters.ts
import { getEmbedding, cosine } from "../embeddings/embeddingClient";

/**
 * 🟦 C8.2 — ATTRIBUTE FILTERING (SOFT FILTERS)
 * For follow-ups like "wide fit", "for long-distance", "for hiking"
 * We apply attribute-based semantic matching
 */

const attributes: Record<string, string[]> = {
  longDistance: ["long distance running", "marathon", "endurance", "distance running", "ultra running"],
  wideFit: ["wide fit", "wide toe box", "wide running shoe", "wide width", "extra wide"],
  hiking: ["trail", "hiking", "outdoor", "mountain", "trail running"],
  flatFeet: ["flat feet", "arch support", "stability", "motion control"],
  running: ["running", "jogging", "sprint", "athletic"],
  waterproof: ["waterproof", "water resistant", "rain", "weatherproof"],
  polarized: ["polarized", "uv protection", "sunglasses"],
  lightweight: ["lightweight", "light", "featherweight"],
};

/**
 * Apply attribute-based semantic filtering
 */
export async function applyAttributeFilters(query: string, items: any[]): Promise<any[]> {
  if (!items || items.length === 0) return [];

  // Skip filtering for hotels - attribute filters are for products only
  if (items.length > 0 && (items[0].source === "Google Hotels" || items[0].name && !items[0].title)) {
    return items;
  }

  const q = query.toLowerCase();
  let targetKey: string | null = null;

  // Detect target attribute
  if (q.includes("long") && (q.includes("distance") || q.includes("run"))) {
    targetKey = "longDistance";
  } else if (q.includes("wide") && (q.includes("fit") || q.includes("size"))) {
    targetKey = "wideFit";
  } else if (q.includes("hiking") || q.includes("trail")) {
    targetKey = "hiking";
  } else if (q.includes("flat feet") || q.includes("flat foot")) {
    targetKey = "flatFeet";
  } else if (q.includes("running") || q.includes("run")) {
    targetKey = "running";
  } else if (q.includes("waterproof") || q.includes("water resistant")) {
    targetKey = "waterproof";
  } else if (q.includes("polarized")) {
    targetKey = "polarized";
  } else if (q.includes("lightweight") || q.includes("light weight")) {
    targetKey = "lightweight";
  }

  // If no target attribute detected, return items as-is
  if (!targetKey || !attributes[targetKey]) {
    return items;
  }

  console.log(`🎯 Applying attribute filter: ${targetKey}`);

  try {
    // Get query embedding
    const qEmb = await getEmbedding(query);

    // Get attribute embeddings
    const attrEmbeds = await Promise.all(
      attributes[targetKey].map((a) => getEmbedding(a))
    );

    // Score each item by semantic closeness to the target attribute
    const scored = await Promise.all(
      items.map(async (item) => {
        const text = `${item.title || item.name || ""} ${item.description || item.snippet || ""}`.trim();
        
        if (!text) return { item, score: 0 };

        const itemEmb = await getEmbedding(text);

        // Find max similarity across all attribute examples
        const maxSimilarity = Math.max(
          ...attrEmbeds.map((emb) => cosine(qEmb, emb)),
          ...attrEmbeds.map((emb) => cosine(itemEmb, emb))
        );

        return { item, score: maxSimilarity };
      })
    );

    // Sort by score and return
    const sorted = scored
      .sort((a, b) => b.score - a.score)
      .map((x) => x.item);

    console.log(`✅ Attribute filter applied: ${sorted.length} items (top score: ${scored[0]?.score.toFixed(3)})`);

    return sorted;
  } catch (err: any) {
    console.error("❌ Attribute filter error:", err.message);
    return items; // Fallback to original items
  }
}

