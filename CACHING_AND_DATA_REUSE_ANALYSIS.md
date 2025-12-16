# Caching and Data Reuse Behavior Analysis

## 1. Where Query Results Are Stored

### **Storage Location:**
**File:** `lib/providers/session_history_provider.dart`  
**Provider:** `sessionHistoryProvider` (StateNotifierProvider)

### **Data Structure:**
- **Type:** `List<QuerySession>`
- **Model:** `QuerySession` (defined in `lib/models/query_session_model.dart`)
- **Fields stored:**
  - `query` (String)
  - `summary` (String?)
  - `intent` (String?)
  - `cardType` (String?)
  - `cards` (List<Map<String, dynamic>>)
  - `results` (List<dynamic>)
  - `destinationImages` (List<String>)
  - `locationCards` (List<Map<String, dynamic>>)
  - `allImages` (List<String>?) - Pre-aggregated images
  - `parsedSegments` (List<Map<String, dynamic>>?) - Cached parsed text

### **Persistence Across Rebuilds:**
**YES** ✅

**Evidence:**
- Line 47 in `session_history_provider.dart`: `ref.keepAlive()` - Prevents provider disposal
- Provider uses `StateNotifierProvider` which maintains state across widget rebuilds
- State persists in memory as long as Riverpod container exists

### **Persistence Across Navigation:**
**YES** ✅

**Evidence:**
- `ref.keepAlive()` ensures provider survives navigation
- `ShoppingResultsScreen` uses `AutomaticKeepAliveClientMixin` (line 135) with `wantKeepAlive => true`
- When navigating back, `sessionHistoryProvider` still contains all sessions

### **Additional Storage:**
- **File:** `lib/providers/agent_provider.dart`  
- **Provider:** `agentResponseProvider` (StateProvider, line 21-24)
- **Purpose:** Stores raw API response (temporary, used during processing)
- **Persistence:** Uses `ref.keepAlive()` (line 23)

---

## 2. Scrolling Behavior - API Calls and Re-computation

### **Does Scrolling Trigger Backend API Calls?**
**NO** ❌

**Evidence:**
- **File:** `lib/screens/ShoppingResultsScreen.dart`
- **Line 213:** `_scrollController.addListener(_handleScroll)` - Only handles scroll-to-bottom button visibility
- **Line 70-76 in FeedScreen.dart:** `_onScroll()` triggers `_loadMoreCollages()` - **ONLY for FeedScreen collages**, not agent queries
- **No API calls found in scroll listeners for agent queries**

### **Does Scrolling Trigger AI Re-computation?**
**NO** ❌

**Evidence:**
- No AI logic in frontend (confirmed in previous analysis)
- Scroll listeners only update UI state (button visibility)
- No recomputation of results on scroll

### **Does Scrolling Trigger Image Re-downloads?**
**NO** ❌

**Evidence:**
- **File:** `lib/screens/ShoppingResultsScreen.dart` (multiple locations)
- **Widget used:** `CachedNetworkImage` (from `cached_network_image` package)
- **Comments in code:** "CachedNetworkImage caches to disk, persists across scrolls/navigation"
- Images are cached to disk by `CachedNetworkImage` widget
- No re-download on scroll or rebuild

### **ListView.builder Behavior:**
- **File:** `lib/screens/ShoppingResultsScreen.dart` (line 1388-1392)
- Uses `SliverList.builder` with `addAutomaticKeepAlives: true`
- Prevents widget disposal when scrolled out of view
- **No API calls in itemBuilder**

---

## 3. Navigation Behavior - Data Reuse vs Re-fetch

### **Navigating Back and Forth:**
**REUSES CACHED DATA** ✅

**Evidence:**

**File:** `lib/screens/ShoppingResultsScreen.dart`
- **Line 230-243:** Checks `sessionHistoryProvider` before submitting query
- **Logic:** If session with same query + imageUrl exists and is completed, skips API call
- **Line 232-236:** `queryAlreadySubmitted` check prevents duplicate submissions

**File:** `lib/screens/ShopScreen.dart`
- **Line 753-779:** When navigating back from `ShoppingResultsScreen`, receives conversation history
- **Line 1430-1454 in ShoppingResultsScreen.dart:** Returns conversation history when navigating back
- History is passed via `Navigator.pop(context, historyToReturn)`

**File:** `lib/screens/ShopScreen.dart` (line 1352-1396)
- **Function:** `_loadChat(ChatHistoryItem chat)`
- **Line 1363:** Passes `initialConversationHistory` to `ShoppingResultsScreen`
- **Line 1305-1324 in ShoppingResultsScreen.dart:** Restores sessions from `initialConversationHistory` if provider is empty

### **When Navigation Triggers Re-fetch:**
**ONLY if:**
1. Query doesn't exist in `sessionHistoryProvider`
2. Session exists but is still `isStreaming` or `isParsing` (line 235)
3. Session exists but `summary == null` (line 235)

**Conclusion:** Navigation reuses cached data when available, only fetches if missing or incomplete.

---

## 4. All Code Paths That Trigger Backend API Calls

### **Agent Query API Calls:**

1. **File:** `lib/providers/agent_provider.dart`
   - **Function:** `AgentController.submitQuery()` (line 32)
   - **Called from:**
     - `lib/screens/ShopScreen.dart` line 704: `ref.read(agentControllerProvider.notifier).submitQuery(query)`
     - `lib/screens/ShoppingResultsScreen.dart` line 240: `ref.read(agentControllerProvider.notifier).submitQuery(widget.query, imageUrl: widget.imageUrl)`
   - **API:** `POST /api/agent` via `ApiClient.post("/agent", {...})`
   - **When:** User submits query, or screen init if query not in session history

2. **File:** `lib/providers/agent_provider.dart`
   - **Function:** `_handleStreamingResponse()` (line 177)
   - **API:** `POST /api/agent?stream=true` via `ApiClient.postStream()`
   - **When:** If `useStreaming: true` is passed

### **Product/Hotel Detail API Calls:**

3. **File:** `lib/screens/ProductDetailScreen.dart`
   - **Function:** `_loadProductDetails()` (line 44)
   - **Called from:** `initState()` (line 41)
   - **API:** `POST ${AgentService.baseUrl}/api/product-details`
   - **When:** Screen initializes (but checks cache first - line 58)

4. **File:** `lib/screens/HotelDetailScreen.dart`
   - **Function:** `_loadHotelDetails()` (line 134)
   - **Called from:** `initState()` (line 77)
   - **API:** `POST ${AgentService.baseUrl}/api/hotel-details`
   - **When:** Screen initializes (but checks cache first - line 149)

### **Hotel Results API Calls:**

5. **File:** `lib/screens/HotelResultsScreen.dart`
   - **Function:** `_fetchHotels()` (line 80)
   - **Called from:** `initState()` (line 63)
   - **API:** `AgentService.askAgent(widget.query)` → `POST /api/agent`
   - **When:** Screen initializes

### **Feed/Collage API Calls:**

6. **File:** `lib/screens/FeedScreen.dart`
   - **Function:** `_loadCollages()` (line 78)
   - **Called from:** `initState()` (line 57)
   - **API:** `CollageService.getPublishedCollagesForFeed()`
   - **When:** Screen initializes

7. **File:** `lib/screens/FeedScreen.dart`
   - **Function:** `_loadMoreCollages()` (called from `_onScroll()` line 73)
   - **API:** `CollageService.getPublishedCollagesForFeed(page: _currentPage + 1)`
   - **When:** User scrolls near bottom (line 71-75)
   - **Note:** This is the ONLY scroll-triggered API call, and it's for collages, not agent queries

### **Autocomplete API Calls:**

8. **File:** `lib/services/AgentService.dart`
   - **Function:** `getAutocompleteSuggestions()` (line 49)
   - **API:** `POST $baseUrl/api/autocomplete`
   - **When:** Called from autocomplete provider (currently disabled in ShopScreen per line 136)

### **Location Autocomplete API Calls:**

9. **File:** `lib/services/AgentService.dart`
   - **Function:** `getLocationAutocomplete()` (line 95)
   - **API:** `POST $baseUrl/api/autocomplete/location`
   - **When:** Called from TravelScreen (line 150)

### **API Calls in build() Methods:**
**NO** ❌

**Evidence:**
- Searched all `build()` methods in `lib/screens/`
- No direct API calls found in `build()` methods
- All API calls are in `initState()`, button handlers, or async functions

### **API Calls in Scroll Listeners:**
**YES** ⚠️ (but only for FeedScreen collages)

**Evidence:**
- **File:** `lib/screens/FeedScreen.dart` line 70-76
- **Function:** `_onScroll()` calls `_loadMoreCollages()` when near bottom
- **Note:** This is for collage feed pagination, NOT agent queries

### **API Calls in Lifecycle Methods:**
**YES** ✅ (but only in initState)

**Evidence:**
- `ShoppingResultsScreen.initState()` (line 225): Calls `submitQuery()` via postFrameCallback
- `ProductDetailScreen.initState()` (line 41): Calls `_loadProductDetails()`
- `HotelDetailScreen.initState()` (line 77): Calls `_loadHotelDetails()`
- `HotelResultsScreen.initState()` (line 63): Calls `_fetchHotels()`
- `FeedScreen.initState()` (line 57): Calls `_loadCollages()`

**No API calls in:**
- `didChangeAppLifecycleState()` - Only unfocuses keyboard (line 254-259 in ShoppingResultsScreen)
- `dispose()` - Only cleanup
- `didUpdateWidget()` - Not found

---

## 5. Image Loading Analysis

### **Widget Used for Images:**
**CachedNetworkImage** ✅

**Evidence:**
- **Package:** `cached_network_image` (imported in multiple files)
- **Primary usage:** `lib/screens/ShoppingResultsScreen.dart` (80+ instances)
- **Also used in:** `FeedScreen.dart`, `CollageViewPage.dart`, `SessionRenderer.dart`, `HotelCardPerplexity.dart`, etc.

### **Memory/Disk Caching:**
**YES** ✅

**Evidence:**
- **Comments in code:** "CachedNetworkImage caches to disk, persists across scrolls/navigation"
- **Package behavior:** `cached_network_image` automatically caches to disk
- **No re-download on rebuild:** CachedNetworkImage checks cache before downloading

### **Image Re-download on Rebuild:**
**NO** ❌

**Evidence:**
- `CachedNetworkImage` uses disk cache
- Cache persists across app restarts
- No manual cache clearing found in code
- Images are only downloaded once per URL

### **Alternative Image Widgets:**
- **File:** `lib/screens/ProductDetailScreen.dart` line 310, 933: Uses `Image.network()` (no caching)
- **File:** `lib/screens/MovieDetailScreen.dart` line 279, 797: Uses `Image.network()` (no caching)
- **File:** `lib/screens/HotelDetailScreen.dart` line 856, 1466: Uses `Image.network()` (no caching)
- **Note:** These are detail screens that load once, so caching less critical

---

## 6. Backend and Frontend Response Caching

### **Frontend Response Caching:**

#### **YES** ✅ - CacheService (Disk Persistence)

**File:** `lib/services/CacheService.dart`

**Features:**
- **Storage:** SharedPreferences (disk persistence)
- **Max entries:** 50 responses (line 16)
- **Max size:** 10MB (line 17)
- **Default expiry:** 7 days (line 18)
- **Eviction:** LRU (Least Recently Used) - line 315-350
- **Smart expiry:** Based on query type (line 23-124)
  - Price queries: 15 minutes
  - Shopping queries: 30 minutes
  - Best/top queries: 1 hour
  - Brand queries: 2 hours
  - Hotels/places: 7 days

**Usage:**
- **File:** `lib/services/AgentService.dart` line 399-440
- **Function:** `askAgent()` checks cache before API call
- **Cache key:** Generated from query + conversation history + context hash (line 411-415)
- **Storage:** `CacheService.set()` stores response (line 556 in agent_provider.dart)

**Product/Hotel Details Caching:**
- **File:** `lib/screens/ProductDetailScreen.dart` line 53-68
- **Cache key:** `product-details-{title}-{source}`
- **Expiry:** 3 days (implied from code)
- **File:** `lib/screens/HotelDetailScreen.dart` line 144-172
- **Cache key:** `hotel-details-{name}-{location}`
- **Expiry:** 7 days (line 229)

### **Backend Response Caching:**

#### **NO** ❌ (No Redis/DB cache for responses)

**Evidence:**
- **File:** `node/src/routes/agent.ts`
- **No response caching found** - Each request processes fresh
- **File:** `node/src/memory/sessionMemory.ts`
- **Purpose:** Stores session state (domain, brand, category, etc.) - NOT query results
- **Storage:** In-memory only (line 26: `const memory: Record<string, SessionEntry> = {}`)
- **TTL:** 30 minutes (line 29)
- **Max sessions:** 1000 (line 30)
- **Note:** This is for context/memory, not response caching

**Redis Reference:**
- **File:** `node/dist/services/redisCache.js` exists but appears unused
- **No imports found** in `agent.ts` or main routes
- **Status:** Redis infrastructure exists but not integrated for response caching

### **Backend Session Memory:**
**YES** ✅ (In-memory, not persistent)

**File:** `node/src/memory/sessionMemory.ts`
- **Storage:** In-memory object (line 26)
- **Purpose:** Stores user context (brand, category, price, city, etc.)
- **Persistence:** NO - Lost on server restart
- **TTL:** 30 minutes of inactivity
- **Cleanup:** Automatic every 5 minutes (line 68-70)

---

## Summary

### **Data Storage:**
- ✅ Query results stored in `sessionHistoryProvider` (Riverpod)
- ✅ Persists across rebuilds (keepAlive)
- ✅ Persists across navigation (keepAlive + AutomaticKeepAliveClientMixin)

### **Scrolling:**
- ❌ Scrolling does NOT trigger agent API calls
- ❌ Scrolling does NOT trigger AI re-computation
- ❌ Images are NOT re-downloaded on scroll (CachedNetworkImage caches to disk)
- ⚠️ FeedScreen scroll triggers collage pagination (separate feature)

### **Navigation:**
- ✅ Navigation reuses cached data from `sessionHistoryProvider`
- ✅ Only re-fetches if query not in cache or incomplete
- ✅ Conversation history passed between screens

### **API Call Locations:**
- ✅ All API calls in `initState()` or user actions (button taps)
- ❌ NO API calls in `build()` methods
- ⚠️ ONE scroll-triggered API call (FeedScreen collages only)

### **Image Caching:**
- ✅ Uses `CachedNetworkImage` (disk caching)
- ✅ Images cached to disk, persist across scrolls/navigation
- ❌ No re-download on rebuild

### **Response Caching:**
- ✅ Frontend: `CacheService` with disk persistence (SharedPreferences)
- ✅ Smart expiry based on query type
- ✅ LRU eviction
- ❌ Backend: No response caching (each request processes fresh)
- ✅ Backend: In-memory session state (context only, not responses)

