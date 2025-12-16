// src/memory/refineQuery.ts
import { getSession } from "./sessionMemory";

/**
 * 🧠 C9.3 — Memory-Aware Query Refinement
 * Enhances follow-up queries with context from session memory
 */
export async function refineQueryWithMemory(query: string, sessionId: string): Promise<string> {
  const s = await getSession(sessionId);
  if (!s) return query;

  let refined = query.trim();

  // ✅ Only add price filter if user EXPLICITLY mentions price in current query
  // Don't add price from session memory unless user explicitly asks for it
  const hasExplicitPrice = /(under|below|less than|max|maximum|up to)\s*\$?\d+/i.test(query);
  if (hasExplicitPrice) {
    // Extract price from current query if mentioned
    const priceMatch = query.match(/(under|below|less than|max|maximum|up to)\s*\$?(\d+)/i);
    if (priceMatch && priceMatch[2]) {
      const extractedPrice = priceMatch[2];
      if (!refined.toLowerCase().includes("under") && !refined.toLowerCase().includes("$")) {
        refined += ` under $${extractedPrice}`;
      }
    }
  }
  // ❌ REMOVED: Don't add price from session memory automatically

  // Keep category
  if (s.category && !query.toLowerCase().includes(s.category.toLowerCase())) {
    refined = `${s.category} ${refined}`;
  }

  // Keep brand
  if (s.brand && !query.toLowerCase().includes(s.brand.toLowerCase())) {
    refined = `${s.brand} ${refined}`;
  }

  // Keep gender
  if (s.gender && !query.toLowerCase().includes(s.gender.toLowerCase()) && 
      !query.toLowerCase().includes("men") && !query.toLowerCase().includes("women")) {
    refined += ` ${s.gender}`;
  }

  // ✅ PRODUCTION FIX: Only add city if:
  // 1. Domain is hotel/restaurants/places
  // 2. Query doesn't already have a city/location
  // 3. Query doesn't explicitly mention a DIFFERENT location
  if (s.city && (s.domain === "hotel" || s.domain === "restaurants" || s.domain === "places")) {
    const queryLower = query.toLowerCase();
    const sessionCityLower = s.city.toLowerCase();
    
    // Check if query already has a location (explicit or implicit)
    const hasLocation = /\b(in|at|near|from|to)\s+[a-zA-Z][a-zA-Z\s]{2,}/i.test(query);
    
    // Check if query mentions a different city/location
    const hasDifferentLocation = hasLocation && !queryLower.includes(sessionCityLower);
    
    // Only add city if:
    // - Query doesn't have any location, OR
    // - Query doesn't have a different location
    if (!hasLocation || !hasDifferentLocation) {
      if (!queryLower.includes(sessionCityLower)) {
        refined += ` in ${s.city}`;
      }
    }
  }

  // Keep intent-specific attributes
  if (s.intentSpecific) {
    if (s.intentSpecific.running && !query.toLowerCase().includes("running")) {
      refined += " running";
    }
    if (s.intentSpecific.wideFit && !query.toLowerCase().includes("wide")) {
      refined += " wide fit";
    }
    if (s.intentSpecific.longDistance && !query.toLowerCase().includes("long distance")) {
      refined += " long distance";
    }
  }

  const finalRefined = refined.trim();
  
  if (finalRefined !== query) {
    console.log(`🔧 Memory-refined query: "${query}" → "${finalRefined}"`);
  }

  return finalRefined;
}

