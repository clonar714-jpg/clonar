// ✅ PHASE 9: Card Fusion Engine
// Orders cards intelligently based on intent and sections

/**
 * Fuse cards in optimal order based on intent and sections
 * @param intent - Primary intent
 * @param cards - Array of cards
 * @param sections - Array of sections (optional)
 * @returns Fused array with cards in optimal order
 */
export function fuseCardsInOrder(intent: string, cards: any[], sections?: any[]): any[] {
  if (!Array.isArray(cards) || cards.length === 0) {
    return cards;
  }

  const lowerIntent = intent.toLowerCase();
  const fused: any[] = [];

  // ✅ Rule: places → first
  if (lowerIntent === "places") {
    // Places cards should be ordered by relevance/rating
    const sorted = [...cards].sort((a, b) => {
      const ratingA = parseFloat(a.rating || a.overall_rating || "0") || 0;
      const ratingB = parseFloat(b.rating || b.overall_rating || "0") || 0;
      return ratingB - ratingA; // Higher rating first
    });
    return sorted;
  }

  // ✅ Rule: overview before details
  // If sections exist, place overview sections first
  if (sections && sections.length > 0) {
    const overviewSections = sections.filter(s => 
      s.type === "overview" || 
      s.title?.toLowerCase().includes("overview") ||
      s.title?.toLowerCase().includes("summary")
    );
    const detailSections = sections.filter(s => 
      s.type !== "overview" && 
      !s.title?.toLowerCase().includes("overview") &&
      !s.title?.toLowerCase().includes("summary")
    );
    
    // Reorder sections: overview first, then details
    const reorderedSections = [...overviewSections, ...detailSections];
    
    // Extract cards from sections in order
    for (const section of reorderedSections) {
      if (section.items && Array.isArray(section.items)) {
        fused.push(...section.items);
      }
    }
    
    // Add remaining cards not in sections
    const sectionCardIds = new Set();
    reorderedSections.forEach(s => {
      if (s.items) {
        s.items.forEach((c: any) => {
          const id = c.id || c.title || c.name;
          if (id) sectionCardIds.add(id);
        });
      }
    });
    
    const remainingCards = cards.filter(c => {
      const id = c.id || c.title || c.name;
      return !id || !sectionCardIds.has(id);
    });
    
    fused.push(...remainingCards);
    
    return fused.length > 0 ? fused : cards;
  }

  // ✅ Rule: hotels after places (if mixed intent)
  if (lowerIntent === "hotels" || lowerIntent.includes("hotel")) {
    // Hotels should be ordered by rating or price
    const sorted = [...cards].sort((a, b) => {
      // First by rating (higher first)
      const ratingA = parseFloat(a.rating || a.overall_rating || "0") || 0;
      const ratingB = parseFloat(b.rating || b.overall_rating || "0") || 0;
      if (ratingB !== ratingA) {
        return ratingB - ratingA;
      }
      
      // Then by price (lower first, if available)
      const priceA = parseFloat(a.price?.toString().replace(/[^\d.]/g, "") || "0") || 0;
      const priceB = parseFloat(b.price?.toString().replace(/[^\d.]/g, "") || "0") || 0;
      if (priceA > 0 && priceB > 0) {
        return priceA - priceB;
      }
      
      return 0;
    });
    return sorted;
  }

  // ✅ Rule: flights last (if mixed intent)
  if (lowerIntent === "flights") {
    // Flights should be ordered by price (lower first) or departure time
    const sorted = [...cards].sort((a, b) => {
      // First by price (lower first)
      const priceA = parseFloat(a.price?.toString().replace(/[^\d.]/g, "") || "0") || 0;
      const priceB = parseFloat(b.price?.toString().replace(/[^\d.]/g, "") || "0") || 0;
      if (priceA > 0 && priceB > 0) {
        return priceA - priceB;
      }
      
      // Then by departure time (earlier first, if available)
      if (a.departure && b.departure) {
        return a.departure.localeCompare(b.departure);
      }
      
      return 0;
    });
    return sorted;
  }

  // ✅ Default: shopping/restaurants - order by rating or relevance
  if (lowerIntent === "shopping" || lowerIntent === "restaurants") {
    const sorted = [...cards].sort((a, b) => {
      // First by rating (higher first)
      const ratingA = parseFloat(a.rating || a.overall_rating || "0") || 0;
      const ratingB = parseFloat(b.rating || b.overall_rating || "0") || 0;
      if (ratingB !== ratingA) {
        return ratingB - ratingA;
      }
      
      // Then by price (lower first for shopping)
      if (lowerIntent === "shopping") {
        const priceA = parseFloat(a.price?.toString().replace(/[^\d.]/g, "") || "0") || 0;
        const priceB = parseFloat(b.price?.toString().replace(/[^\d.]/g, "") || "0") || 0;
        if (priceA > 0 && priceB > 0) {
          return priceA - priceB;
        }
      }
      
      return 0;
    });
    return sorted;
  }

  // Default: return cards as-is
  return cards;
}

/**
 * Merge cards from multiple sources intelligently
 * @param primaryCards - Primary source cards
 * @param secondaryCards - Secondary source cards
 * @param intent - Intent for ordering
 * @returns Merged and ordered cards
 */
export function mergeCardsIntelligently(
  primaryCards: any[],
  secondaryCards: any[],
  intent: string
): any[] {
  const merged = [...(primaryCards || []), ...(secondaryCards || [])];
  return fuseCardsInOrder(intent, merged);
}

