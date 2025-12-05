// ===============================================
// FOLLOW-UP TEMPLATES (Perplexity-Style)
// 🟦 C10.1 — CATEGORY TEMPLATES (Perplexity-style)
// ===============================================

export interface FollowUpTemplate {
  text: string;
  category: string;
  weight: number;       // default priority
  slots?: string[];     // dynamic slot keywords (brand, price, etc.)
}

/**
 * 🟦 C10.1 — Domain-specific templates
 */
export const TEMPLATES: Record<string, string[]> = {
  shopping: [
    "Compare popular models?",
    "Any alternatives under {price}?",
    "Which one is best for {purpose}?",
    "What about different colors?",
    "Is there a better budget option?",
    "Any premium upgrade?",
    "Which has better durability?",
    "Best value for the price?",
    "What sizes are available?",
    "Any lightweight options?",
    "Compare {brand} models?",
    "Best {category} under {price}?",
  ],

  hotels: [
    "Which areas are best to stay in {city}?",
    "Best budget-friendly options?",
    "Compare luxury stays?",
    "Hotels near major attractions?",
    "Which ones are family friendly?",
    "Best rated for cleanliness?",
    "Any with free breakfast?",
    "Safest neighborhoods?",
  ],

  restaurants: [
    "Top dishes to try?",
    "Cheapest good-rated places?",
    "Where do locals prefer?",
    "Any vegetarian options?",
    "What's best for groups?",
    "Best {city} restaurants?",
    "Price range per person?",
    "Is reservation needed?",
  ],

  flights: [
    "Any cheaper dates?",
    "Compare airlines?",
    "Best time to book?",
    "Any non-stop options?",
    "Compare flight durations?",
    "Does this include baggage?",
    "What's the cancellation policy?",
  ],

  places: [
    "Best waterfalls?",
    "Top temples?",
    "Best islands?",
    "Hidden gems nearby?",
    "Nature & adventure spots?",
    "Cultural sites?",
    "Best beaches?",
    "What else to see?",
    "Other places to visit?",
    "Best {city} attractions?",
  ],

  location: [
    "Best things to do?",
    "Where to stay?",
    "Best time to visit?",
    "Top attractions?",
    "Local food recommendations?",
    "Transportation options?",
    "Safety tips?",
  ],

  general: [
    "Want more details?",
    "Need examples?",
    "Should I break this down further?",
  ],
};

// Utility: safe slot replacement
function slot(text: string, key: string, value: string | null): string {
  if (!value) return text;
  return text.replaceAll(`{{${key}}}`, value);
}

// ===============================================
// 🚀 MAIN TEMPLATE BANK
// ===============================================

export const TEMPLATE_BANK: FollowUpTemplate[] = [
  // ------------------------------------------------
  // 🛍️ SHOPPING — GENERAL
  // ------------------------------------------------
  {
    text: "Compare top {{category}} models under {{price}}",
    category: "shopping",
    weight: 0.98,
    slots: ["category", "price"],
  },
  {
    text: "Which {{brand}} {{category}} offer the best durability?",
    category: "shopping",
    weight: 0.96,
    slots: ["brand", "category"],
  },
  {
    text: "Any lightweight options for daily use?",
    category: "shopping",
    weight: 0.92,
  },
  {
    text: "Are there size and color variations available?",
    category: "shopping",
    weight: 0.90,
  },
  {
    text: "Which models have the best customer ratings?",
    category: "shopping",
    weight: 0.89,
  },

  // ------------------------------------------------
  // 🎽 SHOPPING — SHOES
  // ------------------------------------------------
  {
    text: "Which {{brand}} running shoes are best for long-distance?",
    category: "shoes",
    weight: 0.94,
    slots: ["brand"],
  },
  {
    text: "Compare cushioning: {{brand}} models for running",
    category: "shoes",
    weight: 0.93,
    slots: ["brand"],
  },
  {
    text: "Which {{brand}} shoes are best for walking?",
    category: "shoes",
    weight: 0.92,
    slots: ["brand"],
  },
  {
    text: "Are these models true-to-size?",
    category: "shoes",
    weight: 0.90,
  },
  {
    text: "Do these shoes come in wide/narrow sizes?",
    category: "shoes",
    weight: 0.87,
  },

  // ------------------------------------------------
  // ⌚ SHOPPING — WATCHES
  // ------------------------------------------------
  {
    text: "Which {{brand}} watches under {{price}} have stainless steel bands?",
    category: "watches",
    weight: 0.94,
    slots: ["brand", "price"],
  },
  {
    text: "Are these {{brand}} models water-resistant?",
    category: "watches",
    weight: 0.92,
    slots: ["brand"],
  },
  {
    text: "Compare features: analog vs digital in this price range",
    category: "watches",
    weight: 0.90,
  },
  {
    text: "Do these watches come with warranty?",
    category: "watches",
    weight: 0.88,
  },

  // ------------------------------------------------
  // 👓 SHOPPING — GLASSES
  // ------------------------------------------------
  {
    text: "Which {{brand}} glasses have polarized lenses?",
    category: "glasses",
    weight: 0.93,
    slots: ["brand"],
  },
  {
    text: "Any {{brand}} models suitable for driving?",
    category: "glasses",
    weight: 0.90,
    slots: ["brand"],
  },
  {
    text: "Are these models scratch-resistant?",
    category: "glasses",
    weight: 0.88,
  },

  // ------------------------------------------------
  // 🏨 HOTELS
  // ------------------------------------------------
  {
    text: "Hotels near downtown {{city}}?",
    category: "hotel",
    weight: 0.96,
    slots: ["city"],
  },
  {
    text: "Best budget-friendly stays in {{city}}?",
    category: "hotel",
    weight: 0.94,
    slots: ["city"],
  },
  {
    text: "Which hotels offer free breakfast?",
    category: "hotel",
    weight: 0.92,
  },
  {
    text: "Which areas in {{city}} are safest to stay?",
    category: "hotel",
    weight: 0.90,
    slots: ["city"],
  },

  // ------------------------------------------------
  // 🍽️ RESTAURANTS
  // ------------------------------------------------
  {
    text: "Popular dishes at this restaurant?",
    category: "restaurants",
    weight: 0.95,
  },
  {
    text: "Price range per person?",
    category: "restaurants",
    weight: 0.94,
  },
  {
    text: "Is reservation required?",
    category: "restaurants",
    weight: 0.92,
  },

  // ------------------------------------------------
  // ✈️ FLIGHTS
  // ------------------------------------------------
  {
    text: "What is the cheapest date to fly?",
    category: "flights",
    weight: 0.94,
  },
  {
    text: "Compare flight durations and layovers",
    category: "flights",
    weight: 0.92,
  },
  {
    text: "Does this fare include baggage?",
    category: "flights",
    weight: 0.90,
  },

  // ------------------------------------------------
  // 📍 LOCATIONS / TRAVEL
  // ------------------------------------------------
  {
    text: "Best time to visit {{city}}?",
    category: "location",
    weight: 0.96,
    slots: ["city"],
  },
  {
    text: "Top attractions in {{city}}?",
    category: "location",
    weight: 0.95,
    slots: ["city"],
  },
  {
    text: "Local transportation options?",
    category: "location",
    weight: 0.92,
  },

  // ------------------------------------------------
  // ℹ️ GENERAL KNOWLEDGE
  // ------------------------------------------------
  {
    text: "Want examples?",
    category: "general",
    weight: 0.80,
  },
  {
    text: "Should I break this down further?",
    category: "general",
    weight: 0.75,
  },
];

// ===============================================
// 🧠 APPLY SLOT VALUES TO A TEMPLATE
// ===============================================

export function fillSlots(
  template: FollowUpTemplate,
  values: Record<string, string | null>
): string {
  let result = template.text;

  if (template.slots) {
    for (const key of template.slots) {
      result = slot(result, key, values[key] ?? null);
    }
  }
  return result;
}

