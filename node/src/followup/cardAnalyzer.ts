// src/followup/cardAnalyzer.ts

export type CardType =
  | "shopping"
  | "hotel"
  | "restaurants"
  | "flights"
  | "places"
  | "location"
  | "movies"
  | "none";

export interface CardAnalysisResult {
  cardType: CardType;
  shouldReturnCards: boolean;
  brand: string | null;
  category: string | null;
  price: string | null;
  city: string | null;
}

const BRAND_LIST = [
  "nike", "puma", "adidas", "reebok", "gucci", "ray-ban", "rayban",
  "oakley", "balmain", "gap", "prada", "versace", "apple", "samsung",
  "michael kors", "mk", "sony", "canon", "dyson", "dior", "chanel",
  "louis vuitton", "lv", "hermes", "burberry", "tiffany", "cartier",
  "rolex", "omega", "tag heuer", "fossil", "seiko", "citizen"
];

const SHOPPING_KEYWORDS = [
  "buy",
  "shop",
  "purchase",
  "shoes",
  "sneakers",
  "watch",
  "watches",
  "glasses",
  "bag",
  "bags",
  "phone",
  "laptop",
  "hoodie",
  "tshirt",
  "shirt",
  "dress",
];

const HOTEL_KEYWORDS = [
  "hotel",
  "stay",
  "accommodation",
  "resort",
  "hostel",
  "airbnb",
];

const RESTAURANT_KEYWORDS = [
  "restaurant",
  "food",
  "eat",
  "dining",
  "cuisine",
  // ✅ Add local business terms (salons, bars, etc.) - these should use restaurants layout
  "salon", "salons", "hair salon", "hair saloon", "barber", "barbershop",
  "beauty salon", "beauty parlor", "spa", "nail salon", "massage",
  "pub", "bar", "nightclub", "club", "gym", "fitness", "yoga studio"
];

const FLIGHT_KEYWORDS = [
  "flight",
  "flights",
  "airline",
  "fare",
  "airport",
  "departure",
  "arrival",
  // Note: "ticket" and "tickets" removed to avoid conflicts with movie tickets
];

const PLACES_KEYWORDS = [
  "places to visit", "places to vsiit", "places to see", "places to go",
  "things to do", "attractions", "tourist spot", "tourist attraction", 
  "landmark", "temple", "park", "beach", "island", "mountain",
  "waterfall", "heritage site", "must visit", "places in", "visit in", "see in",
  "city to visit",
  "sightseeing",
  "temples",
  "parks",
  "beaches",
  "islands",
  "mountains",
  "cultural sites",
];

const LOCATION_KEYWORDS = [
  "where is",
  "location of",
  "best time to visit",
];

const MOVIE_KEYWORDS = [
  "movie", "movies", "film", "films", "cinema", "theater", "theatre",
  "showtime", "showtimes", "movie tickets", "cinema tickets", "theater tickets",
  "watch movie", "watch film", "watch movies", "watch films", // Only as phrases
  "streaming", "netflix", "hulu", "disney", "imdb", "rotten tomatoes",
  "box office", "premiere", "release", "trailer", "cast", "director"
];

/**
 * Extract the brand (any known brand).
 */
function extractBrand(text: string): string | null {
  const lower = text.toLowerCase();
  for (const b of BRAND_LIST) {
    if (lower.includes(b)) return b;
  }
  return null;
}

/**
 * Extract category such as shoes, hoodies, watches, bags, backpacks, etc.
 */
function extractCategory(text: string): string | null {
  const lower = text.toLowerCase();
  const categories = [
    "shoes",
    "sneakers",
    "hoodies",
    "hoodie",
    "tshirt",
    "shirt",
    "shirts",
    "watches",
    "watch",
    "bags",
    "bag",
    "glasses",
    "sunglasses",
    "phone",
    "laptop",
  ];

  for (const c of categories) {
    if (lower.includes(c)) return c;
  }

  return null;
}

function extractPrice(text: string): string | null {
  const m = text.match(/(under|below)\s*\$?(\d+)/i);
  if (m) return `under $${m[2]}`;
  return null;
}

/**
 * Strong city extractor for follow-ups.
 */
function extractCity(text: string): string | null {
  const regex = /\b(in|at|near|from)\s+([A-Z][a-zA-Z\s]+)/;
  const m = text.match(regex);
  if (m) return m[2].trim();
  return null;
}

/**
 * Check if query has brand name
 */
function hasBrandInQuery(text: string): boolean {
  const lower = text.toLowerCase();
  return BRAND_LIST.some(brand => lower.includes(brand.toLowerCase()));
}

/**
 * Check if "watch" is product context
 */
function isWatchProduct(text: string): boolean {
  const lower = text.toLowerCase();
  if (!lower.includes("watch") && !lower.includes("watches")) return false;
  
  // If has brand, it's definitely a product
  if (hasBrandInQuery(lower)) return true;
  
  // If "watches" (plural), it's likely a product
  if (lower.includes("watches")) return true;
  
  // If "watch" with shopping terms, it's a product
  const shoppingTerms = ["price", "buy", "purchase", "best", "top", "cheap", "under", "review"];
  if (shoppingTerms.some(term => lower.includes(term))) return true;
  
  return false;
}

/**
 * Check if "watch" is movie context
 */
function isWatchMovie(text: string): boolean {
  const lower = text.toLowerCase();
  if (!lower.includes("watch")) return false;
  return lower.includes("watch movie") || 
         lower.includes("watch film") || 
         lower.includes("watch movies") || 
         lower.includes("watch films");
}

/**
 * Type classifier (context-aware).
 */
function detectCardType(text: string): CardType {
  const lower = text.toLowerCase();

  // ✅ STEP 1: Check for brand names (strong shopping signal)
  if (hasBrandInQuery(lower)) {
    // Exception: if it's "watch movie" with brand, still movies
    if (isWatchMovie(lower)) return "movies";
    return "shopping";
  }
  
  // ✅ STEP 2: Check watch/watches with context
  if (lower.includes("watch") || lower.includes("watches")) {
    if (isWatchMovie(lower)) return "movies";
    if (isWatchProduct(lower)) return "shopping";
  }
  
  // ✅ STEP 3: Check movies (with context)
  if (isWatchMovie(lower)) return "movies";
  if (lower.includes("movie ticket") || lower.includes("cinema ticket") || lower.includes("theater ticket")) return "movies";
  if (MOVIE_KEYWORDS.some((k) => lower.includes(k))) return "movies";
  
  // ✅ STEP 4: Check shopping
  if (SHOPPING_KEYWORDS.some((k) => lower.includes(k))) return "shopping";
  
  // ✅ STEP 5: Check hotels
  if (HOTEL_KEYWORDS.some((k) => lower.includes(k))) return "hotel";
  
  // ✅ STEP 6: Check places (before restaurants)
  if (PLACES_KEYWORDS.some((k) => lower.includes(k))) return "places";
  
  // ✅ STEP 7: Check flights
  if (FLIGHT_KEYWORDS.some((k) => lower.includes(k))) return "flights";
  
  // ✅ STEP 8: Check restaurants
  if (RESTAURANT_KEYWORDS.some((k) => lower.includes(k))) return "restaurants";
  
  // ✅ STEP 9: Check location
  if (LOCATION_KEYWORDS.some((k) => lower.includes(k))) return "location";

  return "none";
}

function detectCardTrigger(text: string): boolean {
  const lower = text.toLowerCase();
  return lower.includes("best") ||
         lower.includes("compare") ||
         lower.includes("options") ||
         lower.includes("size") ||
         lower.includes("filter") ||
         lower.includes("under");
}

export function analyzeCardNeed(query: string): CardAnalysisResult {
  return {
    cardType: detectCardType(query),
    shouldReturnCards: detectCardTrigger(query),
    brand: extractBrand(query),
    category: extractCategory(query),
    price: extractPrice(query),
    city: extractCity(query),
  };
}
