# Movie Query Processing Flow - Current Architecture Analysis

## Current Flow (Step-by-Step)

### 1. **Query Reception** (`node/src/routes/agent.ts:103`)
   - Query received: `"action movies 2025"`
   - Cleaned and logged

### 2. **Intent Detection** (`node/src/utils/semanticIntent.ts:408`)
   - **Step 2.1: Fast Keyword Detection** (`fastKeywordIntent`)
     - Checks for keywords: "movie", "movies", "film", "cinema", "theater", etc.
     - ✅ Detects: `"action movies 2025"` → **intent: "movies"**
   
   - **Step 2.2: LLM Classifier** (if fast keywords fail)
   - **Step 2.3: Embedding Similarity** (fallback)

### 3. **Routing Decision** (`node/src/followup/router.ts:30`)
   - Takes intent from Step 2
   - Maps to `finalIntent: "movies"` and `finalCardType: "movies"`
   - Returns routing result

### 4. **Card Type Analysis** (`node/src/followup/cardAnalyzer.ts:273`)
   - Analyzes query for card needs
   - Returns `cardType: "movies"`

### 5. **Movie Query Processing** (`node/src/routes/agent.ts:930`)
   - **Step 5.1: Query Repair** (LLM-based typo fixing)
   - **Step 5.2: Query Preprocessing** (Lines 938-971)
     ```
     "action movies 2025"
     → Remove "showtimes", "tickets"
     → Extract year: 2025
     → Remove year: "action movies"
     → Extract title before "movie": "action"  ❌ PROBLEM HERE!
     → Final query: "action"
     ```
   
   - **Step 5.3: Genre Detection** (Lines 975-1012) - **TOO LATE!**
     - Checks if "action" is a genre
     - ✅ Detects genre: "action" (ID: 28)
     - But query is already reduced to "action"
   
   - **Step 5.4: TMDB API Call**
     - If genre detected → `discoverMovies(genreId: 28, year: 2025)` ✅
     - If not → `searchMovies("action")` → Returns movie titled "Action" ❌

## 🔴 **ROOT PROBLEMS**

### Problem 1: **Query Preprocessing Destroys Intent**
- Line 961-968: Extracts title BEFORE checking if it's a genre
- `"action movies 2025"` → `"action"` (removes "movies")
- Then checks if "action" is genre (too late, query already damaged)

### Problem 2: **No Query Type Classification**
- System doesn't differentiate between:
  - **Genre queries**: "action movies", "comedy films"
  - **New releases**: "new movies", "recent releases", "latest movies"
  - **Specific titles**: "akhanda 2 movie", "inception film"
  - **Discovery queries**: "best movies 2024", "top rated movies"
  - **Year-based**: "movies 2025", "films from 2024"
  - **Rating-based**: "highly rated movies", "top rated films"

### Problem 3: **Genre Detection Happens Too Late**
- Genre check happens AFTER preprocessing
- Should happen BEFORE preprocessing to preserve query structure

### Problem 4: **No Pattern Recognition for Query Types**
- Missing patterns:
  - `"[genre] movies [year]"` → Genre + Year query
  - `"new/recent/latest movies"` → New releases query
  - `"best/top movies"` → Discovery query
  - `"[title] movie"` → Specific title query

## ✅ **REQUIRED FIXES**

### Fix 1: **Query Type Classifier (BEFORE Preprocessing)**
Create a function that classifies query type FIRST:
```typescript
type MovieQueryType = 
  | "genre"           // "action movies 2025"
  | "new_releases"    // "new movies", "recent releases"
  | "specific_title"  // "akhanda 2 movie"
  | "discovery"       // "best movies 2024"
  | "year_only"       // "movies 2025"
  | "rating_based"    // "top rated movies"
```

### Fix 2: **Reordered Processing Flow**
1. **Query Type Detection** (FIRST)
2. **Genre Detection** (if genre query)
3. **Query Preprocessing** (only for title queries)
4. **TMDB API Selection** (based on query type)

### Fix 3: **Enhanced Pattern Recognition**
- Detect genre patterns: `"[genre] movies"`, `"[genre] films"`
- Detect new release patterns: `"new movies"`, `"recent releases"`, `"latest films"`
- Detect discovery patterns: `"best movies"`, `"top rated films"`
- Detect specific title patterns: `"[title] movie"`, `"[title] film"`

## 📋 **CURRENT FLOW SUMMARY**

```
Query: "action movies 2025"
  ↓
1. Intent Detection → "movies" ✅
  ↓
2. Routing → finalIntent: "movies" ✅
  ↓
3. Movie Processing:
   - Query Repair → "action movies 2025"
   - Preprocessing → "action" ❌ (removes "movies")
   - Genre Check → Detects "action" as genre ✅
   - API Call → discoverMovies(genre: 28, year: 2025) ✅
   
   BUT: If genre check fails, it searches for "action" as title ❌
```

## 🎯 **DESIRED FLOW**

```
Query: "action movies 2025"
  ↓
1. Intent Detection → "movies" ✅
  ↓
2. Query Type Classification → "genre" ✅
  ↓
3. Genre Detection → "action" (ID: 28) ✅
  ↓
4. Year Extraction → 2025 ✅
  ↓
5. API Call → discoverMovies(genre: 28, year: 2025) ✅
```

## 🔧 **NEXT STEPS**

1. Create `classifyMovieQueryType()` function
2. Move genre detection BEFORE preprocessing
3. Add pattern recognition for all query types
4. Update preprocessing to preserve query structure for genre queries
5. Add support for "new releases", "recent movies" queries

