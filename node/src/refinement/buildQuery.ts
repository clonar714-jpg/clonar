// src/refinement/buildQuery.ts
import { getSession } from "../memory/sessionMemory";

/**
 * 🧠 C11.1 — MEMORY-AWARE QUERY BUILDER
 * Uses session state to build the strongest possible query
 */
export function buildRefinedQuery(query: string, sessionId: string): string {
  const s = getSession(sessionId);
  if (!s) return query;

  let q = query.toLowerCase().trim();
  let refined = q;

  // Bring in memory (brand, category, price, purpose)
  if (s.brand && !refined.includes(s.brand.toLowerCase())) {
    refined += ` ${s.brand.toLowerCase()}`;
  }

  if (s.category && !refined.includes(s.category.toLowerCase())) {
    refined += ` ${s.category.toLowerCase()}`;
  }

  if (s.gender && !refined.includes(s.gender.toLowerCase()) && 
      !refined.includes("men") && !refined.includes("women")) {
    refined += ` ${s.gender}`;
  }

  // ✅ Only add price filter if user EXPLICITLY mentions price in current query
  // Don't add price from session memory unless user explicitly asks for it
  const hasExplicitPrice = /(under|below|less than|max|maximum|up to)\s*\$?\d+/i.test(query);
  if (hasExplicitPrice) {
    // Extract price from current query if mentioned
    const priceMatch = query.match(/(under|below|less than|max|maximum|up to)\s*\$?(\d+)/i);
    if (priceMatch && priceMatch[2]) {
      const extractedPrice = priceMatch[2];
      if (!refined.includes("under") && !refined.includes("$")) {
        refined += ` under $${extractedPrice}`;
      }
    }
  }
  // ❌ REMOVED: Don't add price from session memory automatically

  if (s.city && !refined.includes(s.city.toLowerCase())) {
    refined += ` in ${s.city}`;
  }

  // Intent-specific attributes - SMART CONTEXT MANAGEMENT (for all fields)
  // Only add context if user is REFINING, not CHANGING intent
  if (s.intentSpecific) {
    const currentQuery = refined.toLowerCase();
    const previousQuery = s.lastQuery?.toLowerCase() || "";
    const queryWords = currentQuery.split(" ").filter(w => w.length > 0);
    
    // Check if user is REFINING (same intent) vs CHANGING (different intent)
    const isRefining = 
      // User explicitly mentions the same attribute
      (s.intentSpecific.running && currentQuery.includes("running")) ||
      (s.intentSpecific.wideFit && currentQuery.includes("wide")) ||
      (s.intentSpecific.longDistance && currentQuery.includes("long distance"));
    
    // Check if user explicitly wants something DIFFERENT
    const wantsDifferent = 
      // Shopping: explicit different purpose
      (currentQuery.includes("casual") || currentQuery.includes("dress") || currentQuery.includes("lifestyle") || currentQuery.includes("fashion")) ||
      // Hotels/Restaurants: different location specificity
      (previousQuery.includes("downtown") && !currentQuery.includes("downtown") && queryWords.length > 2) ||
      (previousQuery.includes("airport") && !currentQuery.includes("airport") && queryWords.length > 2) ||
      // General: previous was specific, current is general (might want different)
      (previousQuery.split(" ").length > 3 && queryWords.length <= 2 && !isRefining);
    
    // Only add context if refining, not changing
    if (!wantsDifferent) {
      if (s.intentSpecific.purpose && !refined.includes(s.intentSpecific.purpose) && isRefining) {
        refined += ` for ${s.intentSpecific.purpose}`;
      }
      // Only add "running" if query is very vague OR user is refining
      if (s.intentSpecific.running && !refined.includes("running")) {
        if (isRefining || (queryWords.length <= 2 && !currentQuery.includes("casual") && !currentQuery.includes("dress"))) {
          refined += " running";
        }
      }
      if (s.intentSpecific.wideFit && !refined.includes("wide") && isRefining) {
        refined += " wide fit";
      }
      if (s.intentSpecific.longDistance && !refined.includes("long distance") && isRefining) {
        refined += " long distance";
      }
    }
    // Otherwise, don't add - user might want something different
  }

  const finalRefined = refined.trim();
  
  if (finalRefined !== query) {
    console.log(`🔧 Memory-enhanced query: "${query}" → "${finalRefined}"`);
  }

  return finalRefined;
}

