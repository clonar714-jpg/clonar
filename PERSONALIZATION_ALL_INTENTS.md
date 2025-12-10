# 🎯 Personalization for All Intents - Complete Guide

## ✅ What's Now Implemented

**Personalization now works for ALL intents:**
- ✅ **Shopping** (products, glasses, shoes, etc.)
- ✅ **Hotels** (accommodations, resorts, etc.)
- ✅ **Restaurants** (dining, cafes, etc.)
- ✅ **Flights** (airline tickets, routes, etc.)
- ✅ **Places** (attractions, landmarks, etc.)
- ✅ **Movies** (films, showtimes, etc.)

---

## 🔄 How It Works for Each Intent

### 1. Shopping (Products)

**Phase 2 - Query Enhancement:**
```
User: "glasses"
Preferences: { brand: "Prada", style: "luxury", price_max: 500 }
Enhanced: "Prada luxury glasses under $500"
```

**Phase 3 - Preference Matching:**
- Matches products by brand, style, price
- Reranks by preference similarity
- "Of my taste" queries: Pure preference matching

**Example:**
- Query: "glasses of my taste"
- System finds: Prada luxury glasses under $500 (ranked highest)

---

### 2. Hotels

**Phase 2 - Query Enhancement:**
```
User: "hotels in miami"
Preferences: { style: "luxury", rating_min: 4 }
Enhanced: "hotels in miami luxury 4 star"
```

**Phase 3 - Preference Matching:**
- Matches hotels by style (luxury, budget), rating, amenities
- Reranks by preference similarity
- Category-specific: "hotels" preferences applied

**Example:**
- Query: "hotels of my kind"
- System finds: Luxury 4+ star hotels (ranked highest)

---

### 3. Restaurants

**Phase 2 - Query Enhancement:**
```
User: "restaurants"
Preferences: { style: "luxury", rating_min: 4 }
Enhanced: "restaurants luxury 4 star"
```

**Phase 3 - Preference Matching:**
- Matches restaurants by cuisine, rating, price
- Reranks by preference similarity
- Category-specific: "restaurants" preferences applied

**Example:**
- Query: "restaurants of my taste"
- System finds: Luxury 4+ star restaurants (ranked highest)

---

### 4. Flights

**Phase 2 - Query Enhancement:**
```
User: "flights to paris"
Preferences: { price_max: 800 }
Enhanced: "flights to paris under $800"
```

**Phase 3 - Preference Matching:**
- Matches flights by price, airline, route preferences
- Reranks by preference similarity
- Works for "of my taste" queries

**Example:**
- Query: "flights of my kind"
- System finds: Flights matching price preferences (ranked highest)

---

### 5. Places

**Phase 2 - Query Enhancement:**
```
User: "places to visit"
Preferences: { style: "luxury" }
Enhanced: "places to visit luxury"
```

**Phase 3 - Preference Matching:**
- Matches places by category, rating, style
- Reranks by preference similarity
- Works for "of my taste" queries

**Example:**
- Query: "places of my kind"
- System finds: Places matching style preferences (ranked highest)

---

### 6. Movies ⭐ NEW

**Phase 2 - Query Enhancement:**
```
User: "movies"
Preferences: { category_preferences: { movies: { genres: ["action", "thriller"], rating_min: 7 } } }
Enhanced: "movies action thriller 7 rating"
```

**Phase 3 - Preference Matching:**
- Matches movies by genres, rating, release date
- Reranks by preference similarity
- **"Movies of my kind" works!**

**Example:**
- Query: "movies of my kind"
- System:
  1. Loads movie preferences from past searches/bookings
  2. Finds: User prefers action/thriller movies with 7+ rating
  3. Searches movies
  4. Matches each movie to preferences using embeddings
  5. Reranks: Action/thriller movies with 7+ rating ranked highest
  6. Returns personalized movie recommendations

---

## 🎬 Movies "Of My Kind" - Detailed Flow

### How It Learns Movie Preferences

**From Past Searches:**
```
User searches:
1. "action movies" → Signal: genres: ["action"]
2. "thriller movies 2023" → Signal: genres: ["thriller"]
3. "best movies 2024" → Signal: rating mentions: ["high rating"]
4. "movies with 8 rating" → Signal: rating_min: 8
5. "sci-fi movies" → Signal: genres: ["sci-fi"]
    ↓
Phase 4 aggregates:
  - category_preferences: {
      "movies": {
        genres: ["action", "thriller", "sci-fi"],
        rating_min: 8
      }
    }
```

### How "Movies of My Kind" Works

```
User Query: "movies of my kind"
    ↓
1. Phase 2: Load preferences
   - Found: { movies: { genres: ["action", "thriller"], rating_min: 7 } }
    ↓
2. Build preference profile:
   "prefers action thriller movies with 7+ rating"
    ↓
3. Search movies (normal search)
    ↓
4. Phase 3: Match to preferences
   For each movie:
     - Get movie embedding (title + overview + genres)
     - Calculate similarity to preference profile
     - Add boosts:
       * Genre match: +0.2
       * Rating match: +0.15
     - Score = similarity + boosts
    ↓
5. Rerank by preference score
    ↓
6. Return: Action/thriller movies with 7+ rating ranked highest
```

### What Gets Matched

**Movie Attributes Used:**
- **Title**: Movie name
- **Overview**: Description/synopsis
- **Genres**: Action, thriller, comedy, etc.
- **Rating**: Vote average (TMDB rating)
- **Release Date**: Year/date

**Preference Profile Includes:**
- Preferred genres (from past searches)
- Minimum rating (from past searches)
- Style preferences (if applicable)

---

## 🆚 Comparison with Perplexity

### Similarities ✅

1. **Learning from Behavior**
   - ✅ Both learn from user search history
   - ✅ Both extract preferences automatically
   - ✅ Both improve over time

2. **Query Enhancement**
   - ✅ Both enhance queries with preferences
   - ✅ Both work for multiple intents (shopping, hotels, etc.)
   - ✅ Both respect explicit user choices

3. **"Of My Taste" Queries**
   - ✅ Both support "of my taste" / "of my kind" queries
   - ✅ Both use semantic matching (embeddings)
   - ✅ Both rerank results by preference similarity

4. **Background Learning**
   - ✅ Both aggregate preferences periodically
   - ✅ Both learn from signals (not just explicit preferences)
   - ✅ Both build category-specific preferences

### Differences ⚠️

1. **Scope**
   - **Perplexity**: General search engine (web, news, etc.)
   - **Our System**: Focused on structured data (products, hotels, movies, etc.)

2. **Preference Storage**
   - **Perplexity**: Likely uses more sophisticated ML models
   - **Our System**: Uses rule-based aggregation with confidence scores

3. **Real-time vs Batch**
   - **Perplexity**: May use real-time ML inference
   - **Our System**: Uses batch aggregation (every 5 conversations or 24 hours)

4. **Cross-Domain Learning**
   - **Perplexity**: Learns across all search types
   - **Our System**: Learns per intent (shopping, hotels, movies, etc.)

---

## 📊 Complete Feature Matrix

| Feature | Shopping | Hotels | Restaurants | Flights | Places | Movies |
|---------|----------|--------|-------------|---------|--------|--------|
| **Phase 1: Signal Collection** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Phase 2: Query Enhancement** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Phase 3: Preference Matching** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **"Of My Taste" Queries** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Hybrid Reranking** | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| **Category-Specific Prefs** | ✅ | ✅ | ✅ | ❌ | ❌ | ✅ |
| **Brand Preferences** | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| **Style Preferences** | ✅ | ✅ | ✅ | ❌ | ✅ | ❌ |
| **Price Preferences** | ✅ | ✅ | ✅ | ✅ | ❌ | ❌ |
| **Rating Preferences** | ❌ | ✅ | ✅ | ❌ | ✅ | ✅ |
| **Genre Preferences** | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |

---

## 🎯 Examples for Each Intent

### Shopping
```
Query: "glasses of my taste"
Preferences: { brand: "Prada", style: "luxury", price_max: 500 }
Result: Prada luxury glasses under $500 (ranked highest)
```

### Hotels
```
Query: "hotels of my kind"
Preferences: { style: "luxury", rating_min: 4 }
Result: Luxury 4+ star hotels (ranked highest)
```

### Restaurants
```
Query: "restaurants of my taste"
Preferences: { style: "luxury", rating_min: 4 }
Result: Luxury 4+ star restaurants (ranked highest)
```

### Flights
```
Query: "flights of my kind"
Preferences: { price_max: 800 }
Result: Flights under $800 (ranked highest)
```

### Places
```
Query: "places of my kind"
Preferences: { style: "luxury" }
Result: Luxury/upscale places (ranked highest)
```

### Movies ⭐
```
Query: "movies of my kind"
Preferences: { 
  category_preferences: { 
    movies: { 
      genres: ["action", "thriller"], 
      rating_min: 7 
    } 
  } 
}
Result: Action/thriller movies with 7+ rating (ranked highest)
```

---

## 🔍 How Movie Preferences Are Learned

### From Search History

**Example Learning Journey:**
```
Day 1:
  User: "action movies" → Signal: genres: ["action"]
  
Day 2:
  User: "best thriller movies 2024" → Signal: genres: ["thriller"], rating: ["high"]
  
Day 3:
  User: "movies with 8 rating" → Signal: rating_min: 8
  
Day 4:
  User: "sci-fi action movies" → Signal: genres: ["sci-fi", "action"]
  
Day 5:
  User: "top rated movies" → Signal: rating: ["high"]
    ↓
Phase 4 Aggregates (after 5 conversations):
  category_preferences: {
    "movies": {
      genres: ["action", "thriller", "sci-fi"],  // Appears in 60%+ of signals
      rating_min: 7  // User consistently wants high-rated movies
    }
  }
    ↓
Now when user says "movies of my kind":
  System matches movies to these preferences
  Returns: Action/thriller/sci-fi movies with 7+ rating
```

### From Past Bookings (Future Enhancement)

**Currently**: System learns from search queries  
**Future**: Could learn from actual bookings/purchases
- If user books action movies → Stronger preference signal
- If user watches thriller movies → Learn from viewing history
- If user rates movies → Learn from ratings

---

## ✅ Summary

### Is It Similar to Perplexity?

**Yes!** The system works similarly to Perplexity:
- ✅ Learns from user behavior
- ✅ Enhances queries with preferences
- ✅ Supports "of my taste" queries
- ✅ Uses semantic matching (embeddings)
- ✅ Works across multiple intents

### Does It Work for All Intents?

**Yes!** Personalization now works for:
- ✅ Shopping
- ✅ Hotels
- ✅ Restaurants
- ✅ Flights
- ✅ Places
- ✅ **Movies** (newly added!)

### Does "Movies of My Kind" Work?

**Yes!** When you say "movies of my kind":
1. ✅ System loads your movie preferences (genres, ratings from past searches)
2. ✅ Searches movies normally
3. ✅ Matches each movie to your preferences using embeddings
4. ✅ Reranks: Movies matching your taste ranked highest
5. ✅ Returns personalized movie recommendations

**Note**: Currently learns from search queries. Future enhancement could learn from actual bookings/viewing history for even better personalization!

---

## 🚀 Next Steps (Future Enhancements)

1. **Booking History Integration**
   - Learn from actual bookings (not just searches)
   - Stronger preference signals from purchases

2. **Viewing History**
   - For movies: Learn from what user actually watches
   - For hotels: Learn from bookings

3. **Explicit Feedback**
   - Allow users to rate results
   - Use ratings to refine preferences

4. **Cross-Intent Learning**
   - Learn that "luxury" preference applies to hotels AND restaurants
   - Share preferences across related intents

