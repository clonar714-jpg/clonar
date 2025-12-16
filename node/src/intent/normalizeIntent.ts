// ✅ PHASE 8: Intent Normalization Layer
// Fixes misclassified intents and normalizes intent strings

import { IntentType } from "../utils/semanticIntent";

/**
 * Normalize intent to fix common misclassifications
 * @param rawIntent - The raw intent from classifier
 * @param query - The original query for context
 * @returns Clean, normalized intent string
 */
export function normalizeIntent(rawIntent: string, query: string): IntentType {
  const lowerQuery = query.toLowerCase().trim();
  const lowerIntent = rawIntent.toLowerCase().trim();

  // ✅ Fix: "top places in" → places
  if (lowerQuery.includes("top places") || 
      lowerQuery.includes("places in") ||
      lowerQuery.includes("places to visit") ||
      lowerQuery.includes("places to see")) {
    return "places";
  }

  // ✅ Fix: "things to do" → places
  if (lowerQuery.includes("things to do") ||
      lowerQuery.includes("thing to do") ||
      lowerQuery.includes("what to do")) {
    return "places";
  }

  // ✅ Fix: "cheap hotels" → hotels
  if ((lowerQuery.includes("cheap") || 
       lowerQuery.includes("affordable") ||
       lowerQuery.includes("budget")) &&
      (lowerQuery.includes("hotel") || 
       lowerQuery.includes("resort") ||
       lowerQuery.includes("accommodation"))) {
    return "hotels";
  }

  // ✅ Fix: "flight from X to Y" → flights
  if (lowerQuery.includes("flight") &&
      (lowerQuery.includes("from") || lowerQuery.includes("to"))) {
    return "flights";
  }

  // ✅ Fix: "buy / price / deals" → shopping
  if (lowerQuery.includes("buy") ||
      lowerQuery.includes("purchase") ||
      lowerQuery.includes("price") ||
      lowerQuery.includes("prices") ||
      lowerQuery.includes("deal") ||
      lowerQuery.includes("deals") ||
      lowerQuery.includes("discount") ||
      lowerQuery.includes("sale")) {
    // But exclude if it's clearly about flights/hotels
    if (!lowerQuery.includes("flight") && 
        !lowerQuery.includes("hotel") &&
        !lowerQuery.includes("ticket")) {
      return "shopping";
    }
  }

  // ✅ Fix: "restaurant" or "food" → restaurants
  if (lowerQuery.includes("restaurant") ||
      lowerQuery.includes("food") ||
      lowerQuery.includes("cafe") ||
      lowerQuery.includes("dining")) {
    return "restaurants";
  }

  // ✅ Fix: "attractions" or "tourist" → places
  if (lowerQuery.includes("attraction") ||
      lowerQuery.includes("tourist") ||
      lowerQuery.includes("landmark") ||
      lowerQuery.includes("sightseeing")) {
    return "places";
  }

  // ✅ Fix: "movie" or "film" → movies
  if (lowerQuery.includes("movie") ||
      lowerQuery.includes("film") ||
      lowerQuery.includes("cinema") ||
      lowerQuery.includes("theater")) {
    return "movies";
  }

  // ✅ Validate and return normalized intent
  const validIntents: IntentType[] = [
    "shopping", "hotels", "flights", "restaurants", 
    "places", "movies", "location", "general", 
    "images", "local", "answer"
  ];

  if (validIntents.includes(lowerIntent as IntentType)) {
    return lowerIntent as IntentType;
  }

  // Default fallback
  return "general";
}

/**
 * Check if query has multiple intents
 * @param query - The user query
 * @returns Array of detected intents
 */
export function detectMultipleIntents(query: string): IntentType[] {
  const lowerQuery = query.toLowerCase().trim();
  const intents: IntentType[] = [];

  // Check for shopping
  if (lowerQuery.includes("buy") || 
      lowerQuery.includes("price") ||
      lowerQuery.includes("shop") ||
      lowerQuery.match(/\b(shoes|watch|bag|phone|laptop)\b/)) {
    intents.push("shopping");
  }

  // Check for hotels
  if (lowerQuery.includes("hotel") || 
      lowerQuery.includes("resort") ||
      lowerQuery.includes("accommodation")) {
    intents.push("hotels");
  }

  // Check for flights
  if (lowerQuery.includes("flight") || 
      lowerQuery.includes("airline")) {
    intents.push("flights");
  }

  // Check for restaurants
  if (lowerQuery.includes("restaurant") || 
      lowerQuery.includes("food") ||
      lowerQuery.includes("cafe")) {
    intents.push("restaurants");
  }

  // Check for places
  if (lowerQuery.includes("places") || 
      lowerQuery.includes("attraction") ||
      lowerQuery.includes("things to do")) {
    intents.push("places");
  }

  // Check for movies
  if (lowerQuery.includes("movie") || 
      lowerQuery.includes("film")) {
    intents.push("movies");
  }

  // Remove duplicates
  return [...new Set(intents)];
}

