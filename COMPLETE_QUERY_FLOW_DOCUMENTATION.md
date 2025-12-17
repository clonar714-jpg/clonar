# Complete End-to-End Query Flow Documentation

## Overview
This document traces the complete flow from query submission to results display for ALL intent types (shopping, hotels, movies, places, flights, restaurants, general/answer).

---

## 🎯 **PHASE 1: Query Reception & Preprocessing**

### Entry Point: `node/src/routes/agent.ts:103` - `handleRequest()`

**Input:**
```typescript
{
  query: string,
  conversationHistory: Array,
  stream: boolean,
  sessionId: string,
  conversationId: string,
  userId: string,
  lastFollowUp: string,
  parentQuery: string,
  imageUrl: string (optional)
}
```

**Steps:**
1. **Query Cleaning** (Line 106)
   - Trim whitespace
   - Validate non-empty

2. **Image Analysis** (Lines 118-255) - *If imageUrl provided*
   - Analyze image content
   - Detect image type (product, place, document)
   - Enhance query with image description/keywords
   - Clear conversation history for new image searches

3. **Conversation History Filtering** (Lines 262-274)
   - Filter or clear history based on context
   - Image searches → Clear history completely

---

## 🎯 **PHASE 2: Intent Detection & Routing**

### Step 2.1: Semantic Intent Detection
**File:** `node/src/utils/semanticIntent.ts:408` - `detectSemanticIntent()`

**Process:**
1. **Fast Keyword Detection** (`fastKeywordIntent`) - Lines 233-295
   - Checks keywords in priority order:
     - Shopping: brands, product categories, shopping terms
     - Movies: movie/film/cinema terms (with context)
     - Places: "places to visit", "things to do", attractions
     - Hotels: hotel/resort/accommodation terms
     - Restaurants: restaurant/food/dining terms
     - Flights: flight/airline/airport terms
     - Location: "where is", location queries
   
2. **LLM Classifier** (`llmIntentClassifier`) - Lines 301-383
   - If fast keywords fail, uses GPT-4o-mini
   - Context-aware classification
   - Handles ambiguous queries

3. **Embedding Fallback** (`embeddingIntent`) - Lines 389-402
   - Semantic similarity matching
   - Compares query to example queries for each intent

**Output:** `IntentType` (shopping, hotels, flights, restaurants, places, location, movies, general, answer, images, local)

### Step 2.2: Routing Decision
**File:** `node/src/followup/router.ts:30` - `routeQuery()`

**Process:**
1. Get base intent from semantic detection
2. Check follow-up context (if lastTurn exists)
3. Analyze card needs (`analyzeCardNeed`)
4. Map intent to card type
5. Extract slots (brand, category, price, city)

**Output:** `RoutingResult`
```typescript
{
  finalIntent: UnifiedIntent,
  finalCardType: "shopping" | "hotel" | "restaurants" | "flights" | "places" | "location" | "movies" | null,
  shouldReturnCards: boolean,
  brand: string | null,
  category: string | null,
  price: string | null,
  city: string | null
}
```

### Step 2.3: Intent Normalization & Healing
**File:** `node/src/routes/agent.ts:331-368`

**Process:**
1. **Intent Normalization** (Line 332)
   - Fixes misclassified intents
   - Maps similar intents (e.g., "hotel" → "hotels")

2. **Multi-Intent Detection** (Line 344)
   - Detects multiple intents in single query
   - Uses primary intent, notes secondary

3. **Context Healing** (Lines 350-368)
   - Heals vague follow-ups using conversation history
   - Re-routes if query is healed

---

## 🎯 **PHASE 3: Query Enhancement & Memory**

### Step 3.1: Session Memory Management
**File:** `node/src/routes/agent.ts:377-730`

**Process:**
1. **Session ID Resolution** (Line 379)
   - Priority: conversationId → userId → sessionId → "global"

2. **Memory Enhancement Decision** (Lines 411-418)
   - **Enhanced:** shopping, hotels, flights, restaurants, places, movies
   - **NOT Enhanced:** answer, general (informational queries)

3. **Query Refinement** (Lines 420-736)
   - **For Enhanced Intents:**
     - Personalization enhancement (if "of my taste" query)
     - Preference enhancement (if user has preferences)
     - Context merging (if follow-up query)
     - Memory refinement (adds brand/category/price/city from session)
   - **For Non-Enhanced Intents:**
     - Uses original query (no memory enhancement)

---

## 🎯 **PHASE 4: Card Fetching (Intent-Specific Processing)**

### 4.1 SHOPPING Intent
**File:** `node/src/routes/agent.ts:748-786`

**Flow:**
1. **Product Search** → `searchProducts(refinedQuery)`
2. **Zero Results Fallback** → Try extra refined query
3. **Lexical Filters** → `applyLexicalFilters()` (price, brand, etc.)
4. **Attribute Filters** → `applyAttributeFilters()` (soft filters)
5. **Reranking:**
   - If "of my taste" → `matchItemsToPreferences()` (preference matching)
   - If user has preferences → `hybridRerank()` (query + preferences)
   - Otherwise → `rerankCards()` (embedding-based)
6. **LLM Correction** → `correctCards()` (removes mismatches)
7. **Description Enrichment** → `enrichProductsWithDescriptions()` (generates AI descriptions)

**Data Source:** SerpAPI (Google Shopping)

---

### 4.2 HOTELS Intent
**File:** `node/src/routes/agent.ts:787-821`

**Flow:**
1. **Hotel Search** → `searchHotels(refinedQuery)`
2. **Zero Results Fallback** → Try extra refined query
3. **Lexical Filters** → `applyLexicalFilters()` (price, etc.)
4. **Location Filters** → `filterHotelsByLocation()` (downtown, airport, etc.)
5. **Attribute Filters** → `applyAttributeFilters()`
6. **Reranking:**
   - If "of my taste" → `matchItemsToPreferences()`
   - If user has preferences → `hybridRerank()`
   - Otherwise → `rerankCards()`
7. **LLM Correction** → `correctCards()`
8. **Description Enrichment** → `enrichHotelsWithThemesAndDescriptions()` (generates sections: whatPeopleSay, reviewSummary, etc.)

**Data Source:** SerpAPI (Google Hotels)

---

### 4.3 RESTAURANTS Intent
**File:** `node/src/routes/agent.ts:822-852`

**Flow:**
1. **Restaurant Search** → `searchRestaurants(refinedQuery)`
2. **Zero Results Fallback** → Try extra refined query
3. **Lexical Filters** → `applyLexicalFilters()`
4. **Location Filters** → `filterRestaurantsByLocation()` (downtown, airport, etc.)
5. **Attribute Filters** → `applyAttributeFilters()`
6. **Reranking:**
   - If "of my taste" → `matchItemsToPreferences()`
   - If user has preferences → `hybridRerank()`
   - Otherwise → `rerankCards()`
7. **LLM Correction** → `correctCards()`

**Data Source:** SerpAPI (Google Restaurants)

---

### 4.4 FLIGHTS Intent
**File:** `node/src/routes/agent.ts:853-881`

**Flow:**
1. **Flight Search** → `searchFlights(refinedQuery)`
2. **Zero Results Fallback** → Try extra refined query
3. **Lexical Filters** → `applyLexicalFilters()` (price, route, etc.)
4. **Attribute Filters** → `applyAttributeFilters()`
5. **Reranking:**
   - If "of my taste" → `matchItemsToPreferences()`
   - If user has preferences → `hybridRerank()`
   - Otherwise → `rerankCards()`
6. **LLM Correction** → `correctCards()`

**Data Source:** SerpAPI (Google Flights)

---

### 4.5 PLACES Intent
**File:** `node/src/routes/agent.ts:882-913`

**Flow:**
1. **Places Search** → `searchPlaces(placesQuery)`
   - Uses context-aware query if available
   - LLM-powered search engine
2. **Location Filters** → `filterPlacesByLocation()` (downtown, airport, etc.)
3. **Reranking:**
   - If "of my taste" → `matchItemsToPreferences()`
   - If user has preferences → `hybridRerank()`
   - Otherwise → No reranking (results already ranked by searchPlaces)
4. **No LLM Correction** (places are location-based, all relevant)

**Data Source:** BrightData Places API + LLM enhancement

---

### 4.6 LOCATION Intent
**File:** `node/src/routes/agent.ts:914-929`

**Flow:**
1. **Location Search** → `searchPlaces(locationQuery)`
   - Uses context-aware query if available
2. **No Filtering** (location queries return specific places)
3. **No Reranking** (location queries are specific)

**Data Source:** BrightData Places API

---

### 4.7 MOVIES Intent
**File:** `node/src/routes/agent.ts:930-1120`

**Flow:**
1. **Query Repair** → `repairQuery()` (LLM-based typo fixing)
2. **Query Type Classification** → `classifyMovieQueryType()`
   - Types: "genre", "new_releases", "specific_title", "discovery", "year_only", "rating_based"
3. **Year Extraction** → Extract year from query
4. **Query Processing (Based on Type):**
   
   **A. Genre Queries** (e.g., "action movies 2025"):
   - Detect genre from query (BEFORE preprocessing)
   - Use `discoverMovies(genreId, year)`
   
   **B. New Releases** (e.g., "new movies", "recent releases"):
   - Use `discoverMovies(year, sortBy: 'release_date.desc')`
   
   **C. Discovery** (e.g., "best movies 2024"):
   - Use `discoverMovies(year, sortBy: 'popularity.desc')`
   
   **D. Rating-Based** (e.g., "highly rated movies"):
   - Use `discoverMovies(sortBy: 'vote_average.desc')`
   
   **E. Year-Only** (e.g., "movies 2025"):
   - Use `discoverMovies(year)`
   
   **F. Specific Title** (e.g., "akhanda 2 movie"):
   - Preprocess query (remove "movie", extract title)
   - Use `searchMovies(title)` with fallbacks:
     - Try without numbers
     - Try first word only
   - Detect if specific (1 result) vs general (multiple results)

5. **Year Filtering** (only for title searches)
6. **In-Theaters Detection** (check TMDB "now playing" + date-based)
7. **Result Transformation** → Format as cards with images, rating, etc.

**Data Source:** TMDB API (The Movie Database)

---

### 4.8 GENERAL/ANSWER Intent
**File:** `node/src/routes/agent.ts:1400-1416`

**Flow:**
1. **No Card Fetching** (informational query)
2. **LLM Answer Only** → Generated summary/explanation
3. **Web Search** → If needed for answer generation

**Data Source:** OpenAI + SerpAPI (web search)

---

## 🎯 **PHASE 5: Card Post-Processing**

### Step 5.1: Card Filtering
**File:** `node/src/cards/filterCards.ts`

**Process:**
1. **Irrelevant Card Removal** → `filterOutIrrelevantCards()`
   - Intent-specific filtering
   - Removes cards not matching intent

2. **Duplicate Removal** → `removeDuplicateCards()`
   - Removes exact duplicates

3. **Card Validation** → `isValidCard()`
   - Ensures required fields present

### Step 5.2: Card Fusion
**File:** `node/src/cards/fuseCards.ts`

**Process:**
1. **Optimal Ordering** → `fuseCardsInOrder()`
   - Intent-specific card ordering
   - Prioritizes most relevant cards

### Step 5.3: Memory Filtering
**File:** `node/src/routes/agent.ts:1155-1165`

**Process:**
1. **Session Memory Filtering** (for shopping/hotels)
   - Filters by brand/category/price from session
   - Only if session has strong signals

2. **Skip for Movies/Places** (no brand/category/price)

---

## 🎯 **PHASE 6: Answer Generation**

### Step 6.1: LLM Answer
**File:** `node/src/services/llmAnswer.ts`

**Process:**
1. **Non-Streaming** → `getAnswerNonStream()`
   - Generates summary/overview
   - Includes web search if needed
   - Formats conversation history

2. **Streaming** → `getAnswerStream()`
   - Streams answer incrementally
   - Sends chunks as they're generated

**Output:**
```typescript
{
  summary: string,
  sources: Array,
  locations: Array,
  destination_images: Array
}
```

---

## 🎯 **PHASE 7: Response Assembly**

### Step 7.1: Section Generation
**File:** `node/src/format/sectionGenerator.ts`

**Process:**
1. **Generate Sections** (for hotels)
   - whatPeopleSay
   - reviewSummary
   - chooseThisIf
   - about
   - amenitiesClean
   - locationSummary
   - ratingInsights

### Step 7.2: Follow-Up Suggestions
**File:** `node/src/followup/index.ts`

**Process:**
1. **Generate Suggestions** → `getFollowUpSuggestions()`
   - Intent-aware suggestions
   - Behavior-weighted scoring
   - Novelty injection
   - Answer coverage detection

### Step 7.3: Confidence Scoring
**File:** `node/src/confidence/scorer.ts`

**Process:**
1. **Intent Confidence** → `computeIntentConfidence()`
2. **Slot Confidence** → `computeSlotConfidence()`
3. **Card Confidence** → `computeCardConfidence()`
4. **Overall Confidence** → `computeOverallConfidence()`

---

## 🎯 **PHASE 8: Session Memory Update**

### Step 8.1: Save Session State
**File:** `node/src/routes/agent.ts:1630-1680`

**Process:**
1. **Extract Preference Signals** → `extractPreferenceSignals()`
2. **Store Signals** → `storePreferenceSignal()`
3. **Save Session** → `saveSession()`
   - Domain (shopping, hotels, etc.)
   - Brand, category, price, city
   - Last query, last answer
   - Intent-specific slots

---

## 🎯 **PHASE 9: Response Return**

### Step 9.1: Response Formatting
**File:** `node/src/routes/agent.ts:1680-1950`

**Response Structure:**
```typescript
{
  summary: string,
  intent: string,
  cardType: string,
  cards: Array,
  results: Array,
  sections: Array (hotels only),
  mapPoints: Array (hotels only),
  sources: Array,
  followUpSuggestions: Array,
  confidence: {
    intent: number,
    slots: number,
    cards: number,
    overall: number
  }
}
```

---

## 📊 **INTENT DIFFERENTIATION SUMMARY**

| Intent | Detection Signals | Data Source | Processing Steps | Special Features |
|--------|------------------|-------------|------------------|------------------|
| **Shopping** | Brands, product categories, "buy", "price" | SerpAPI | Search → Filter → Rerank → Correct → Enrich | Preference matching, description generation |
| **Hotels** | "hotel", "resort", "stay", "accommodation" | SerpAPI | Search → Filter → Location Filter → Rerank → Correct → Enrich | Section generation, map points |
| **Restaurants** | "restaurant", "food", "eat", "dining" | SerpAPI | Search → Filter → Location Filter → Rerank → Correct | Location-aware |
| **Flights** | "flight", "airline", "airport" | SerpAPI | Search → Filter → Rerank → Correct | Route-based |
| **Places** | "places to visit", "things to do", "attractions" | BrightData + LLM | LLM Search → Location Filter → Rerank | LLM-powered search |
| **Location** | "where is", "location of" | BrightData | LLM Search | Specific location queries |
| **Movies** | "movie", "film", "cinema", "showtime" | TMDB | Type Classification → Genre/Discover/Search → Transform | Genre detection, new releases, discovery |
| **General/Answer** | No specific signals | OpenAI + Web | LLM Answer Only | No cards, informational |

---

## 🔄 **COMPLETE FLOW DIAGRAM**

```
Query Submission
    ↓
[Image Analysis] (if imageUrl)
    ↓
Intent Detection (Fast Keywords → LLM → Embeddings)
    ↓
Routing Decision (Intent → Card Type → Slots)
    ↓
Intent Normalization & Healing
    ↓
Query Enhancement (Memory, Preferences, Context)
    ↓
┌─────────────────────────────────────────┐
│  INTENT-SPECIFIC PROCESSING             │
├─────────────────────────────────────────┤
│  Shopping: Search → Filter → Rerank →   │
│            Correct → Enrich             │
│  Hotels: Search → Filter → Location →   │
│          Rerank → Correct → Enrich      │
│  Restaurants: Search → Filter → Location│
│              → Rerank → Correct         │
│  Flights: Search → Filter → Rerank →    │
│          Correct                         │
│  Places: LLM Search → Location Filter → │
│         Rerank                           │
│  Location: LLM Search                    │
│  Movies: Type Classify → Genre/Discover │
│         /Search → Transform              │
│  General: LLM Answer Only                │
└─────────────────────────────────────────┘
    ↓
Card Post-Processing (Filter → Fuse → Memory Filter)
    ↓
Answer Generation (LLM + Web Search)
    ↓
Section Generation (Hotels only)
    ↓
Follow-Up Suggestions
    ↓
Confidence Scoring
    ↓
Session Memory Update
    ↓
Response Assembly
    ↓
Return to Frontend
```

---

## 🎯 **KEY DIFFERENCES BY INTENT**

### **Shopping vs Hotels vs Restaurants vs Flights**
- **Common:** All use SerpAPI, filtering, reranking, correction
- **Different:** 
  - Shopping: Description enrichment, preference matching
  - Hotels: Section generation, map points, location filtering
  - Restaurants: Location filtering
  - Flights: Route-based filtering

### **Places vs Location**
- **Places:** Multiple results, LLM-powered search, reranking
- **Location:** Single/specific results, no reranking

### **Movies vs Others**
- **Movies:** Query type classification, genre detection, TMDB API
- **Others:** Direct search, no type classification

### **General/Answer vs Others**
- **General:** No cards, LLM answer only
- **Others:** Cards + LLM answer

---

## 📝 **NOTES**

1. **Memory Enhancement:** Only applied to shopping, hotels, flights, restaurants, places, movies
2. **Query Refinement:** Only for shopping/travel intents, NOT movies/general
3. **Preference Matching:** Only if user has preferences stored
4. **LLM Correction:** Applied to all card-based intents except places
5. **Description Enrichment:** Only for shopping and hotels
6. **Section Generation:** Only for hotels

