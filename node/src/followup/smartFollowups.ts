// src/followup/smartFollowups.ts
import { getEmbedding, cosine } from "../embeddings/embeddingClient";

export interface FollowUpContext {
  query: string;
  answer: string;
  intent: string;
  brand: string | null;
  category: string | null;
  price: string | null;
  city: string | null;
  lastFollowUp: string | null;
  parentQuery: string | null;
  cards: any[];
}

/**
 * remove duplicate or similar follow-ups
 */
async function removeSemanticDuplicates(list: string[], last: string | null): Promise<string[]> {
  if (!last) return list;

  const lastEmb = await getEmbedding(last);
  const result: string[] = [];

  for (const item of list) {
    const emb = await getEmbedding(item);
    const score = cosine(lastEmb, emb);

    // Remove anything semantically similar
    if (score < 0.80) result.push(item);
  }

  return result;
}

/**
 * SHOPPING FOLLOW-UPS
 */
function shoppingFollowUps(ctx: FollowUpContext): string[] {
  const brand = ctx.brand ? ctx.brand.toUpperCase() : "";
  const cat = ctx.category || "products";

  const suggestions: string[] = [];
  
  if (brand) {
    suggestions.push(
      `Compare other ${cat} from ${brand}`,
      `Is ${brand} good for long-term durability?`,
      `Show alternatives to ${brand} ${cat}`
    );
  }
  
  suggestions.push(
    `Best ${cat} under higher price range`,
    `Which ${cat} offer the best comfort?`,
    `Compare materials & build quality`,
    `Which ${cat} are good for everyday use?`,
    `Show lightweight ${cat} options`
  );
  
  return suggestions;
}

/**
 * HOTEL FOLLOW-UPS
 */
function hotelFollowUps(ctx: FollowUpContext): string[] {
  const city = ctx.city || "this area";

  return [
    `Best areas to stay in ${city}`,
    `Compare budget vs luxury hotels in ${city}`,
    `Hotels near major attractions in ${city}`,
    `Hotel amenities comparison in ${city}`,
    `Best family-friendly hotels in ${city}`,
  ];
}

/**
 * RESTAURANTS FOLLOW-UPS
 */
function restaurantFollowUps(ctx: FollowUpContext): string[] {
  const city = ctx.city || "this area";

  return [
    `Cheap restaurants in ${city}`,
    `Top-rated restaurants for dinner`,
    `Best breakfast spots in ${city}`,
    `Best cuisines to try in ${city}`,
  ];
}

/**
 * FLIGHT FOLLOW-UPS
 */
function flightFollowUps(ctx: FollowUpContext): string[] {
  return [
    `Compare airlines on this route`,
    `Cheapest time to fly`,
    `Baggage rules comparison`,
    `Best seats for long flights`,
  ];
}

/**
 * LOCATION FOLLOW-UPS
 */
function locationFollowUps(ctx: FollowUpContext): string[] {
  const city = ctx.city || "this area";

  return [
    `Must-see attractions in ${city}`,
    `Best time to visit ${city}`,
    `Hidden gems in ${city}`,
    `Local food recommendations in ${city}`,
    `Top neighborhoods to explore in ${city}`,
  ];
}

/**
 * GENERAL FOLLOW-UPS
 */
function generalFollowUps(ctx: FollowUpContext): string[] {
  return [
    `Explain in simpler terms`,
    `Give real-world examples`,
    `Show pros & cons`,
    `Provide a short summary`,
  ];
}

/**
 * MASTER FOLLOW-UP GENERATOR
 * (Perplexity-level)
 */
export async function generateSmartFollowUps(ctx: FollowUpContext): Promise<string[]> {
  let base: string[] = [];

  switch (ctx.intent) {
    case "shopping":
      base = shoppingFollowUps(ctx);
      break;
    case "hotels":
    case "hotel":
      base = hotelFollowUps(ctx);
      break;
    case "restaurants":
      base = restaurantFollowUps(ctx);
      break;
    case "flights":
      base = flightFollowUps(ctx);
      break;
    case "location":
      base = locationFollowUps(ctx);
      break;
    default:
      base = generalFollowUps(ctx);
  }

  // Filter out any empty suggestions
  base = base.filter(Boolean);

  // Remove identical to last follow-up
  if (ctx.lastFollowUp) {
    base = base.filter(
      (s) => s.toLowerCase() !== ctx.lastFollowUp?.toLowerCase()
    );
  }

  // Remove semantically similar ones
  base = await removeSemanticDuplicates(base, ctx.lastFollowUp);

  // Limit to 5
  return base.slice(0, 5);
}

