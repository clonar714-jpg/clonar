// ======================================================================
//  PERPLEXITY-GRADE INTENT ENGINE (C2 / STEP 1)
//  Multi-layer classifier: keywords → LLM → embeddings → correction layer
// ======================================================================
import OpenAI from "openai";
import { getEmbedding, cosine } from "../embeddings/embeddingClient";
// Lazy client loader
let clientInstance = null;
function getClient() {
    if (!clientInstance) {
        const apiKey = process.env.OPENAI_API_KEY;
        if (!apiKey)
            throw new Error("Missing OPENAI_API_KEY");
        clientInstance = new OpenAI({ apiKey });
    }
    return clientInstance;
}
// Brand names - if query contains brand + product, it's definitely shopping
const BRAND_NAMES = [
    "michael kors", "mk", "gucci", "puma", "nike", "adidas", "reebok",
    "balmain", "rayban", "ray-ban", "oakley", "gap", "prada", "versace",
    "apple", "samsung", "sony", "canon", "dyson", "dior", "chanel",
    "louis vuitton", "lv", "hermes", "burberry", "tiffany", "cartier",
    "rolex", "omega", "tag heuer", "fossil", "seiko", "citizen"
];
// Product categories - these indicate shopping intent
const PRODUCT_CATEGORIES = [
    "shoes", "sneakers", "boots", "sandals", "heels",
    "watch", "watches", "timepiece", "timepieces",
    "bag", "bags", "purse", "handbag", "backpack", "luggage",
    "glasses", "sunglasses", "eyewear",
    "tshirt", "shirt", "shirts", "dress", "dresses", "hoodie", "hoodies",
    "jeans", "pants", "shorts", "jacket", "coat",
    "phone", "smartphone", "laptop", "tablet", "headphones", "earbuds",
    "camera", "tv", "television", "speaker", "watch band", "watch strap"
];
// Shopping action words
const SHOPPING_ACTION_TERMS = [
    "buy", "purchase", "shop", "shopping", "price", "prices", "cost",
    "best", "top", "cheap", "affordable", "discount", "sale", "deal",
    "compare", "review", "reviews", "rating", "ratings",
    "under", "below", "above", "over", "from", "starting at"
];
// Keywords for fast routing (comprehensive)
const SHOPPING_TERMS = [
    ...SHOPPING_ACTION_TERMS,
    ...PRODUCT_CATEGORIES,
    "market", "bazaar", "mall", "store", "shop", "retailer"
];
const HOTEL_TERMS = [
    "hotel", "stay", "resort", "lodging", "inn", "motel",
    "accommodation", "airbnb", "rooms", "book a hotel"
];
const FLIGHT_TERMS = [
    "flight", "flights", "airline", "fare",
    "plane", "route", "airport", "departure", "arrival"
    // Note: "ticket" and "tickets" removed to avoid conflicts with movie tickets
];
const RESTAURANT_TERMS = [
    "restaurant", "restaurants", "food", "eat", "cafe",
    "dining", "cuisine", "breakfast", "lunch", "dinner",
    // ✅ Add local business terms (salons, bars, etc.) - these should use restaurants/local layout
    "salon", "salons", "hair salon", "hair saloon", "barber", "barbershop",
    "beauty salon", "beauty parlor", "spa", "nail salon", "massage",
    "pub", "bar", "nightclub", "club", "gym", "fitness", "yoga studio"
];
const PLACES_TERMS = [
    "places to visit", "places to vsiit", "places to see", "places to go",
    "things to do", "attractions", "tourist spot", "tourist attraction",
    "landmark", "temple", "park", "beach", "island", "mountain",
    "waterfall", "heritage site", "must visit", "city to visit",
    "sightseeing", "temples", "parks", "beaches", "islands",
    "mountains", "cultural sites", "places in", "visit in", "see in"
];
const LOCATION_TERMS = [
    "where is", "city", "country", "location of",
    "best time to visit", "travel guide"
];
// Movie terms - REMOVED "watch" to avoid ambiguity with product watches
// "watch" alone is ambiguous - use context detection instead
const MOVIE_TERMS = [
    "movie", "movies", "film", "films", "cinema", "theater", "theatre",
    "showtime", "showtimes", "movie tickets", "cinema tickets", "theater tickets",
    "streaming", "netflix", "hulu", "disney", "imdb", "rotten tomatoes",
    "box office", "premiere", "release", "trailer", "cast", "director",
    "watch movie", "watch film", "watch movies", "watch films" // Only as phrases
];
const IMAGE_TERMS = ["photo", "images", "pictures", "wallpapers"];
const LOCAL_TERMS = ["near me", "nearby", "closest", "around me"];
// Embedding fallback examples (improved with context)
const embeddingExamples = {
    shopping: [
        "best shoes", "nike shoes", "michael kors watches", "gucci bag",
        "buy watch", "watches under 200", "best laptops", "apple phone",
        "puma sneakers", "rolex watch", "cheap headphones"
    ],
    hotels: ["hotels in new york", "resorts in bali", "best hotels paris"],
    flights: ["cheap flights", "flight deals", "airline tickets"],
    restaurants: ["best restaurants", "top cafes", "food near me"],
    places: [
        "places to visit in thailand", "things to do in paris",
        "attractions in japan", "tourist spots"
    ],
    location: ["where is paris", "location of tokyo"],
    movies: [
        "inception movie", "best movies 2024", "movie showtimes",
        "film reviews", "watch movie", "cinema tickets"
    ],
    images: ["cat photos", "car wallpapers"],
    local: ["food near me", "hospitals near me"],
    general: ["what is", "how to", "why does", "meaning of"],
    answer: ["what is", "explain", "how to", "describe"]
};
// ======================================================================
//  CONTEXT-AWARE HELPERS
// ======================================================================
/**
 * Check if query contains a brand name
 */
function hasBrand(query) {
    const lower = query.toLowerCase();
    return BRAND_NAMES.some(brand => lower.includes(brand.toLowerCase()));
}
/**
 * Check if query contains product category
 */
function hasProductCategory(query) {
    const lower = query.toLowerCase();
    return PRODUCT_CATEGORIES.some(cat => {
        // Use word boundary matching for better accuracy
        const regex = new RegExp(`\\b${cat.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\b`, 'i');
        return regex.test(lower);
    });
}
/**
 * Check if "watch" refers to movies (context: "watch movie/film")
 */
function isWatchMovieContext(query) {
    const lower = query.toLowerCase();
    // Only match if "watch" appears with movie-related terms
    if (!lower.includes("watch"))
        return false;
    return lower.includes("watch movie") ||
        lower.includes("watch film") ||
        lower.includes("watch movies") ||
        lower.includes("watch films") ||
        (lower.includes("watch") && (lower.includes("cinema") || lower.includes("theater") || lower.includes("streaming")));
}
/**
 * Check if "watch" refers to product (context: brand + watch, or watch + product terms)
 */
function isWatchProductContext(query) {
    const lower = query.toLowerCase();
    if (!lower.includes("watch") && !lower.includes("watches"))
        return false;
    // If has brand, it's definitely a product
    if (hasBrand(lower))
        return true;
    // If "watch" appears with shopping/product terms, it's a product
    const productIndicators = ["price", "buy", "purchase", "best", "top", "cheap", "under", "review", "rating"];
    if (productIndicators.some(term => lower.includes(term)))
        return true;
    // If "watches" (plural) appears, it's likely a product
    if (lower.includes("watches"))
        return true;
    return false;
}
/**
 * Check if "tickets" refers to movies (context: "movie tickets")
 */
function isMovieTicketContext(query) {
    const lower = query.toLowerCase();
    if (!lower.includes("ticket"))
        return false;
    return lower.includes("movie ticket") ||
        lower.includes("film ticket") ||
        lower.includes("cinema ticket") ||
        lower.includes("theater ticket") ||
        lower.includes("showtime");
}
/**
 * Check if "tickets" refers to flights (context: "flight tickets" or airline terms)
 */
function isFlightTicketContext(query) {
    const lower = query.toLowerCase();
    if (!lower.includes("ticket"))
        return false;
    return lower.includes("flight ticket") ||
        lower.includes("airline ticket") ||
        lower.includes("plane ticket") ||
        (lower.includes("ticket") && (lower.includes("flight") || lower.includes("airline") || lower.includes("airport")));
}
// ======================================================================
//  1. FAST KEYWORD ROUTER (most accurate layer - context-aware)
// ======================================================================
function fastKeywordIntent(q) {
    const lower = q.toLowerCase();
    // ✅ STEP 1: Check for strong shopping signals FIRST (brands + products)
    // If query has brand name, it's almost certainly shopping
    if (hasBrand(lower)) {
        // Double-check: if it's "watch movie" with a brand, it's still movies
        if (isWatchMovieContext(lower))
            return "movies";
        return "shopping";
    }
    // ✅ STEP 2: Check product categories with context
    // If query has product category + shopping terms, it's shopping
    if (hasProductCategory(lower)) {
        // Special handling for "watch/watches" - need context
        if (lower.includes("watch") || lower.includes("watches")) {
            if (isWatchMovieContext(lower))
                return "movies";
            if (isWatchProductContext(lower))
                return "shopping";
            // Default: if has shopping action terms, it's shopping
            if (SHOPPING_ACTION_TERMS.some(term => lower.includes(term)))
                return "shopping";
        }
        else {
            // Other product categories are definitely shopping
            return "shopping";
        }
    }
    // ✅ STEP 3: Check movies with context-aware detection
    // Special handling: "movie tickets" vs "flight tickets"
    // ✅ FIX 2: Require BOTH movie keywords AND absence of product model patterns
    // Hard exclusion: If query contains camera/laptop/vehicle model patterns → block movies intent
    const productModelPatterns = [
        // Camera models
        /\b(x-t\d+|a\d+|eos|d\d+|z\d+|alpha|nex-|a7|a9|r\d+|m\d+)\b/i,
        // Laptop models
        /\b(m\d+|macbook|thinkpad|xps|spectre|zenbook|vivobook|inspiron|pavilion)\b/i,
        // Vehicle models
        /\b(rav4|cr-v|corolla|civic|camry|accord|prius|f-150|silverado|model\s*[3syx]|x\d+|q\d+)\b/i,
        // Product model indicators
        /\b(\d+mp|\d+gb|\d+tb|inch|inches|mm|f\/|iso|shutter)\b/i,
    ];
    const hasProductModelPattern = productModelPatterns.some(pattern => pattern.test(lower));
    // Only return movies if:
    // 1. Has movie keywords
    // 2. AND does NOT have product model patterns
    if (hasProductModelPattern) {
        // Product model detected - block movies intent
        // Continue to next checks (shopping, etc.)
    }
    else if (isMovieTicketContext(lower)) {
        return "movies";
    }
    else if (isWatchMovieContext(lower)) {
        return "movies";
    }
    else if (MOVIE_TERMS.some(k => lower.includes(k))) {
        return "movies";
    }
    // ✅ STEP 4: Check places FIRST (before shopping) for location-based queries
    // This ensures "things to do in [city]" is correctly identified as places, not shopping
    // Use fuzzy matching to handle typos like "thinds" → "things"
    const placesMatch = PLACES_TERMS.some(k => {
        const normalizedK = k.toLowerCase();
        const normalizedQ = lower.replace(/thinds/g, 'things').replace(/vsiit/g, 'visit');
        return normalizedQ.includes(normalizedK);
    });
    if (placesMatch)
        return "places";
    // ✅ STEP 5: Check shopping (after places to avoid false positives)
    if (SHOPPING_TERMS.some(k => lower.includes(k)))
        return "shopping";
    // ✅ STEP 6: Check hotels
    if (q.includes("hotels"))
        return "hotels";
    if (HOTEL_TERMS.some(k => lower.includes(k)))
        return "hotels";
    // ✅ STEP 7: Check restaurants
    if (RESTAURANT_TERMS.some(k => lower.includes(k)))
        return "restaurants";
    // ✅ STEP 8: Check flights (with ticket context)
    if (isFlightTicketContext(lower))
        return "flights";
    if (FLIGHT_TERMS.some(k => lower.includes(k)))
        return "flights";
    // ✅ STEP 9: Other intents
    if (LOCATION_TERMS.some(k => lower.includes(k)))
        return "location";
    if (IMAGE_TERMS.some(k => lower.includes(k)))
        return "images";
    if (LOCAL_TERMS.some(k => lower.includes(k)))
        return "local";
    return null;
}
// ======================================================================
//  2. LLM ADJUDICATION (Perplexity-style yes/no classification)
// ======================================================================
async function llmIntentClassifier(query) {
    const system = `
You are an expert intent classifier. Classify the user query into ONE of these intents:

- shopping
- hotels
- flights
- restaurants
- places
- movies
- general
- answer

CRITICAL RULES (follow in order):

1. SHOPPING INTENT:
   - If query contains BRAND NAME (e.g., "michael kors", "nike", "gucci", "apple") + product → shopping
   - If query contains PRODUCT CATEGORY (shoes, watches, bags, phones, laptops, etc.) → shopping
   - If query contains "watch" or "watches" WITH brand name → shopping (e.g., "michael kors watches", "rolex watch")
   - If query contains "watch" or "watches" WITH shopping terms (price, buy, best, top, under) → shopping
   - If query contains shopping action words (buy, purchase, price, best, top, cheap, compare, review) → shopping
   - Examples: "michael kors watches", "nike shoes", "best laptops", "watches under $200", "buy gucci bag" → shopping

2. MOVIES INTENT:
   - If query contains "watch" ONLY with movie context → movies (e.g., "watch movie", "watch film", "watch movies")
   - If query contains "movie tickets", "cinema tickets", "theater tickets", "showtimes" → movies
   - If query contains movie terms (movie, film, cinema, theater, streaming, netflix, imdb) → movies
   - Examples: "watch movie", "best movies 2024", "movie showtimes", "inception film" → movies
   - CRITICAL: "watch" alone is ambiguous - if it appears with brand/product, it's shopping, not movies

3. FLIGHTS INTENT:
   - If query contains "flight tickets", "airline tickets", "plane tickets" → flights
   - If query contains flight terms (flight, airline, airport, departure, arrival) → flights
   - Examples: "cheap flights", "flight tickets to paris", "airline deals" → flights
   - CRITICAL: "tickets" alone is ambiguous - check context (movie tickets vs flight tickets)

4. PLACES INTENT:
   - If query contains "places to visit", "places to see", "things to do", "attractions" → places
   - If query contains "places" + location (city/country) → places
   - Examples: "places to visit in paris", "attractions in japan", "things to do in new york" → places

5. RESTAURANTS INTENT:
   - If query explicitly mentions "restaurant", "food", "eat", "dining", "cafe", "cuisine" → restaurants
   - Examples: "best restaurants", "food near me", "top cafes in paris" → restaurants

6. HOTELS INTENT:
   - If query contains hotel terms (hotel, stay, resort, accommodation, airbnb) → hotels
   - Examples: "hotels in new york", "best resorts", "cheap accommodation" → hotels

AMBIGUITY RESOLUTION:
- "watch" + brand/product → shopping (e.g., "michael kors watches" = shopping)
- "watch" + movie/film → movies (e.g., "watch movie" = movies)
- "tickets" + movie/film/cinema → movies
- "tickets" + flight/airline → flights
- "places" + location → places (NOT restaurants)

Respond with ONLY the intent word (lowercase). No explanation.
`;
    const user = `Query: "${query}"`;
    try {
        const res = await getClient().chat.completions.create({
            model: "gpt-4o-mini",
            temperature: 0,
            max_tokens: 10,
            messages: [
                { role: "system", content: system },
                { role: "user", content: user }
            ]
        });
        const intent = (res.choices[0]?.message?.content ?? "").trim().toLowerCase();
        const valid = [
            "shopping", "hotels", "flights", "restaurants", "places", "movies",
            "location", "general", "images", "local", "answer"
        ];
        if (!valid.includes(intent))
            return "general";
        return intent;
    }
    catch {
        return "general";
    }
}
// ======================================================================
//  3. Embedding Fall-back (semantic similarity)
// ======================================================================
async function embeddingIntent(query) {
    const qEmb = await getEmbedding(query);
    let best = { intent: "general", score: 0 };
    for (const intent of Object.keys(embeddingExamples)) {
        for (const example of embeddingExamples[intent]) {
            const emb = await getEmbedding(example);
            const score = cosine(qEmb, emb);
            if (score > best.score)
                best = { intent, score };
        }
    }
    return best.intent;
}
// ======================================================================
//  MASTER INTENT DETECTOR — combines all layers
// ======================================================================
export async function detectSemanticIntent(query) {
    const cleaned = query.toLowerCase().trim();
    // 1) Try fast keywords FIRST (most accurate, context-aware)
    const fast = fastKeywordIntent(cleaned);
    if (fast) {
        console.log(`🎯 Fast keyword detection: "${query}" → ${fast}`);
        return fast;
    }
    // 2) Try LLM classifier (handles complex cases)
    const llm = await llmIntentClassifier(query);
    if (llm !== "general" && llm !== "answer") {
        console.log(`🤖 LLM classification: "${query}" → ${llm}`);
        return llm;
    }
    // 3) Embeddings fallback (semantic similarity)
    const semantic = await embeddingIntent(query);
    if (semantic !== "general") {
        console.log(`🔍 Embedding similarity: "${query}" → ${semantic}`);
        return semantic;
    }
    console.log(`❓ Default classification: "${query}" → general`);
    return "general";
}
// ======================================================================
// Card fetch decision (rewritten)
// ======================================================================
export async function shouldFetchCards(query, answer) {
    const intent = await detectSemanticIntent(query);
    if (["shopping", "hotels", "flights", "restaurants", "places", "location"].includes(intent))
        return intent;
    // If LLM answer mentions products/hotels explicitly, fetch cards
    const lower = answer.toLowerCase();
    if (/\bprice|model|options|best|top|shoes|watch|bag|hotel|flight|restaurants|attractions\b/.test(lower)) {
        return "shopping";
    }
    return null;
}
// ======================================================================
// Compatibility wrappers
// ======================================================================
export async function classifyIntent(query) {
    const i = await detectSemanticIntent(query);
    return i === "general" ? "answer" : i;
}
export async function semanticIntent(q) {
    return classifyIntent(q);
}
