# Conversation Memory, Follow-Up Queries, and Intent Switching Analysis

## 1. How Chat Sessions Are Stored

### **Frontend Session Storage:**

**File:** `lib/providers/session_history_provider.dart`  
**Provider:** `sessionHistoryProvider` (StateNotifierProvider)

**Storage Location:**
- **In-Memory:** Riverpod provider with `ref.keepAlive()` (line 47) - persists across widget rebuilds
- **Disk Persistence:** `ChatHistoryServiceCloud` saves to SharedPreferences (local cache) + cloud database

**Session Data Structure:**
- **Model:** `QuerySession` (defined in `lib/models/query_session_model.dart`)
- **Fields:**
  - `query` (String) - User's query text
  - `summary` (String?) - AI-generated summary/answer
  - `intent` (String?) - Detected intent (shopping, hotels, etc.)
  - `cardType` (String?) - Type of cards to display
  - `cards` (List<Map<String, dynamic>>) - Product/hotel/restaurant cards
  - `results` (List<dynamic>) - Raw search results
  - `destinationImages` (List<String>) - Location images
  - `locationCards` (List<Map<String, dynamic>>) - Location-specific cards
  - `allImages` (List<String>?) - Pre-aggregated images
  - `parsedSegments` (List<Map<String, dynamic>>?) - Cached parsed text segments
  - `isStreaming` (bool) - Whether response is streaming
  - `isParsing` (bool) - Whether response is being parsed
  - `timestamp` (DateTime) - When query was submitted

**Storage Mechanism:**
- **File:** `lib/services/ChatHistoryServiceCloud.dart`
- **Local Cache:** SharedPreferences (`chat_history_local_cache_v1` key, line 27)
- **Cloud Storage:** PostgreSQL database via API (`/chats` endpoint, line 81-119)
- **Sync Strategy:** Load from local cache first (instant), sync with cloud in background (3-second delay, line 39)

**When Session is Created:**
- **File:** `lib/providers/agent_provider.dart` line 32-172
- **Function:** `AgentController.submitQuery()`
- **Trigger:** User submits query in `ShopScreen` or `ShoppingResultsScreen`
- **Process:** Creates `QuerySession` with `isStreaming: true`, adds to `sessionHistoryProvider`

### **Backend Session Memory:**

**File:** `node/src/memory/sessionMemory.ts`

**Storage Location:**
- **In-Memory Only:** JavaScript object (line 26: `const memory: Record<string, SessionEntry> = {}`)
- **NOT Persistent:** Lost on server restart
- **TTL:** 30 minutes of inactivity (line 29)
- **Max Sessions:** 1000 (line 30)

**Session Data Structure:**
- **Interface:** `SessionState` (line 7-18)
- **Fields:**
  - `domain` ("shopping" | "hotel" | "restaurants" | "flights" | "location" | "general")
  - `brand` (string | null)
  - `category` (string | null)
  - `price` (number | null)
  - `city` (string | null)
  - `gender` ("men" | "women" | null)
  - `intentSpecific` (Record<string, any>) - Additional intent-specific data
  - `lastQuery` (string)
  - `lastAnswer` (string)
  - `lastImageUrl` (string | null) - Tracks image URL to detect changes

**When Session is Created/Updated:**
- **File:** `node/src/routes/agent.ts` line 1490-1526
- **Function:** `handleRequest()` calls `saveSession()` after processing query
- **Session ID:** Uses `conversationId ?? userId ?? sessionId ?? "global"` (line 379)

**Conclusion:**
- **Frontend:** Sessions stored in memory (Riverpod) + disk (SharedPreferences) + cloud (PostgreSQL)
- **Backend:** Session state stored in-memory only (30min TTL, not persistent)

---

## 2. When a Previous Chat is Opened

### **Chat Reconstruction Process:**

**File:** `lib/screens/ShopScreen.dart` line 1352-1396  
**Function:** `_loadChat(ChatHistoryItem chat)`

**Process:**
1. **Load from Storage:**
   - **File:** `lib/services/ChatHistoryServiceCloud.dart` line 32-54
   - **Function:** `loadChatHistory()` - Loads from local cache first, syncs with cloud in background
   - **Returns:** `List<ChatHistoryItem>` with `conversationHistory` field

2. **Navigate to Results Screen:**
   - **Line 1357-1365:** Navigates to `ShoppingResultsScreen` with:
     - `query`: Original query from chat
     - `imageUrl`: Image URL if present
     - `initialConversationHistory`: Full conversation history array

3. **Restore Sessions:**
   - **File:** `lib/screens/ShoppingResultsScreen.dart` line 1305-1324
   - **Function:** `build()` method checks if `sessions.isEmpty` and `initialConversationHistory` exists
   - **Process:** Creates `QuerySession` objects from `initialConversationHistory` data
   - **Timing:** Deferred to `addPostFrameCallback` to avoid blocking build (line 1307)

4. **Check for Duplicate Submission:**
   - **File:** `lib/screens/ShoppingResultsScreen.dart` line 230-243
   - **Function:** `initState()` checks if query already exists in `sessionHistoryProvider`
   - **Logic:** If session with same query + imageUrl exists and is completed, skips API call
   - **Result:** Uses cached data, does NOT call backend

### **Backend API Call Behavior:**

**Answer:** **NO** - Backend is NOT called if conversation history is restored from cache

**Evidence:**
- **File:** `lib/screens/ShoppingResultsScreen.dart` line 230-243
- **Check:** `queryAlreadySubmitted` prevents duplicate API calls
- **Condition:** Only submits if session doesn't exist OR is still `isStreaming`/`isParsing` OR `summary == null`

**Conclusion:**
- **Reconstruction:** Sessions restored from `initialConversationHistory` in memory
- **Backend Call:** Skipped if data already exists and is complete
- **Data Source:** Cached conversation history from SharedPreferences/cloud

---

## 3. When a New Query is Submitted Inside an Existing Conversation

### **Conversation History Sent to Backend:**

**Answer:** **YES** ✅

**File:** `lib/services/AgentService.dart` line 460-464  
**Function:** `askAgent()`

**Request Body:**
```dart
final body = <String, dynamic>{
  "query": query,
  "conversationHistory": conversationHistory ?? [],
};
```

**How Conversation History is Built:**

**File:** `lib/providers/follow_up_controller_provider.dart` line 37-53  
**Function:** `handleFollowUp()`

**Process:**
1. Reads all sessions from `sessionHistoryProvider`
2. Filters sessions with non-empty `query` and `summary`
3. Builds history array with:
   - `query`: Session query
   - `summary`: Session summary
   - `intent`: Session intent or resultType
   - `cardType`: Session cardType or resultType

**Note:** The follow-up controller builds history, but `AgentService.askAgent()` accepts `conversationHistory` parameter. Need to check if it's passed.

**File:** `lib/providers/agent_provider.dart` line 32-172  
**Function:** `submitQuery()`

**Observation:** `submitQuery()` does NOT explicitly build or pass `conversationHistory` to `AgentService.askAgent()`. However, `AgentService.askAgent()` accepts it as a parameter.

**Backend Consumption:**

**File:** `node/src/routes/agent.ts` line 105  
**Function:** `handleRequest()`

**Extraction:**
```typescript
const { query, conversationHistory, stream, sessionId, conversationId, userId, lastFollowUp, parentQuery, imageUrl } = req.body;
```

**Usage in LLM Answer Generation:**

**File:** `node/src/services/llmAnswer.ts` line 134-172  
**Function:** `getAnswerNonStream()` and `getAnswerStream()`

**Process:**
1. Builds messages array with system prompt
2. Iterates through `conversationHistory` (line 141-169)
3. Adds alternating user/assistant messages:
   - User message: `h.query`
   - Assistant message: `h.summary || h.answer` + context about cards shown
4. Adds current query as final user message (line 172)

**Conclusion:**
- **Frontend:** Conversation history is built from `sessionHistoryProvider` and sent to backend
- **Backend:** Consumes `conversationHistory` and uses it to build LLM context
- **LLM Context:** Full conversation history is included in LLM prompt for context-aware responses

---

## 4. Follow-Up Query Handling

### **How System Detects Refinements:**

**Approach:** **HYBRID** (LLM-based + Rule-based)

### **A. LLM-Based Context Extraction (Primary):**

**File:** `node/src/services/llmContextExtractor.ts`  
**Function:** `extractContextWithLLM()` (line 38-125)

**Process:**
1. **LLM Prompt:** Sends query + parent query + conversation history to GPT-4o-mini
2. **Extraction:** LLM extracts:
   - `brand`, `category`, `price`, `city`, `location`
   - `intent` - What user is looking for
   - `modifiers` - Array of modifiers (luxury, cheap, 5-star, etc.)
   - `isRefinement` - Boolean indicating if query is a refinement
   - `needsParentContext` - Boolean indicating if query needs context from parent

3. **Rules in Prompt:**
   - If query explicitly mentions location, set `needsParentContext: false`
   - If query is vague (e.g., "only 5 star", "cheaper ones") AND has NO location, set `needsParentContext: true`
   - NEVER infer location from parent if current query mentions DIFFERENT location

**File:** `node/src/services/llmContextExtractor.ts`  
**Function:** `mergeQueryContextWithLLM()` (line 132-215)

**Process:**
1. **Location Conflict Detection:** Checks if current query has explicit location different from parent (line 139-155)
2. **LLM Merging:** If `needsParentContext: true`, sends prompt to LLM to merge queries
3. **Examples in Prompt:**
   - "only 5 star hotels" + "hotels in bangkok" → "5 star hotels in Bangkok"
   - "cheaper ones" + "nike shoes" → "cheaper nike shoes"
   - "hotels in paris" + "hotels in bangkok" → "hotels in paris" (explicit location, never override)

### **B. Rule-Based Detection (Fallback):**

**File:** `node/src/routes/agent.ts` line 605-608  
**Function:** `handleRequest()` - Fallback logic when LLM fails

**Pattern Matching:**
```typescript
const isRefinementQuery = /^(only|just|show|find|get|give me|i want|i need)\s+.*/i.test(cleanQuery.trim()) ||
                         /\b(only|just|more|less|cheaper|expensive|costlier|luxury|budget|premium|star|stars)\b/i.test(cleanQuery) ||
                         /\b(\d+)\s*(star|stars)\b/i.test(cleanQuery);
```

**Rule-Based Merging (line 610-656):**
- Merges brand if parent has it and follow-up doesn't
- Merges category if parent has it and follow-up doesn't
- Merges city ONLY if:
  1. Current query doesn't have any location
  2. Current query doesn't explicitly mention a DIFFERENT location
  3. It's a travel intent (hotels, flights, restaurants, places)

### **C. Context Healing (Rule-Based):**

**File:** `node/src/context/healContext.ts`  
**Function:** `healFollowUp()` (line 27-128)

**Process:**
1. **Vague Query Detection:** Checks for patterns like "cheaper ones", "better ones", "more options"
2. **Query Expansion:**
   - "cheaper ones" → "cheaper [product/hotel] in [location]"
   - "better ones" → "better [product/hotel] in [location]"
   - "more options" → "[product/hotel] in [location]"
3. **Slot Filling:** Fills missing data from last session's slots (location, price, brand, category)

**Usage:**
- **File:** `node/src/routes/agent.ts` line 350-368
- **Trigger:** If `lastFollowUp` or `parentQuery` exists
- **Process:** Heals query, re-routes with healed query

### **D. Follow-Up Intent Detection:**

**File:** `node/src/utils/followUpIntent.ts`  
**Function:** `detectFollowUpIntent()` (line 125-240)

**Process:**
1. **Session Memory Check:** If session exists and domain is not "general", inherits domain for weak queries (line 133-144)
2. **Explicit Intent:** Checks explicit intent first (line 147-148)
3. **Context-Aware Classification:**
   - Uses embedding similarity to match against trigger lists
   - Shopping triggers: "best models", "top models", "compare products", etc.
   - Hotel triggers: "best areas", "price per night", "downtown hotels", etc.
   - Restaurant triggers: "good places to eat", "top restaurants", etc.
4. **Weak Query Detection:** If query is weak (e.g., "best ones", "more options"), inherits previous intent (line 96-119)

**Conclusion:**
- **Primary Method:** LLM-based context extraction and merging (handles edge cases, typos, variations)
- **Fallback:** Rule-based pattern matching and slot merging
- **Supporting:** Context healing for vague queries, follow-up intent detection for routing

---

## 5. Intent Switching

### **How System Detects New Query vs Refinement:**

**Approach:** **HYBRID** (LLM-based + Rule-based)

### **A. LLM-Based Detection (Primary):**

**File:** `node/src/services/llmContextExtractor.ts`  
**Function:** `extractContextWithLLM()` (line 38-125)

**LLM Rules in Prompt (line 84-94):**
1. **Explicit Location = New Query:**
   - "If query explicitly mentions a location/city, ALWAYS extract it and set needsParentContext: false"
   - "If query has explicit location (e.g., 'in singapore', 'in paris'), set isRefinement: false (it's a new query, not a refinement)"

2. **Different Location = New Query:**
   - "NEVER infer location from parent query if current query explicitly mentions a DIFFERENT location"

**File:** `node/src/services/llmContextExtractor.ts`  
**Function:** `mergeQueryContextWithLLM()` (line 132-215)

**Location Conflict Detection (line 139-155):**
```typescript
const hasExplicitLocation = /\b(in|at|near|from|to)\s+[a-zA-Z][a-zA-Z\s]{2,}/i.test(currentQuery);
const currentLocation = currentQuery.match(/\b(in|at|near|from|to)\s+([a-zA-Z][a-zA-Z\s]{2,})/i)?.[2];
const parentLocation = parentQuery.match(/\b(in|at|near|from|to)\s+([a-zA-Z][a-zA-Z\s]{2,})/i)?.[2];

if (hasExplicitLocation && currentLocation && parentLocation && currentLocation !== parentLocation) {
  console.log(`🔒 Location conflict detected: current="${currentLocation}", parent="${parentLocation}" - skipping merge`);
  return currentQuery; // Return as-is, don't merge
}
```

### **B. Rule-Based Detection (Fallback):**

**File:** `node/src/routes/agent.ts` line 620-645  
**Function:** `handleRequest()` - Fallback logic

**Location Conflict Check:**
```typescript
const hasLocationInQuery = /\b(in|at|near|from|to)\s+[a-zA-Z][a-zA-Z\s]{2,}/i.test(cleanQuery);
const hasDifferentLocation = hasLocationInQuery && 
  parentSlots.city && 
  !qLower.includes(parentSlots.city.toLowerCase());

if (hasDifferentLocation) {
  console.log(`📍 Fallback: Skipping location merge - current query has different location: "${cleanQuery}"`);
}
```

**Intent Override Detection:**

**File:** `node/src/routes/agent.ts` line 547-579  
**Function:** `handleRequest()` - LLM intent override

**Process:**
1. LLM extracts intent from current query
2. If extracted intent differs from detected intent, overrides it
3. Example: "near to downtown" might be misclassified as "places" but LLM correctly identifies as "hotels"

### **C. Session Memory Reset Signals:**

**File:** `node/src/routes/agent.ts` line 381-409  
**Function:** `handleRequest()` - Image search detection

**Signal:** **Image URL Change**
- If `imageUrl` is provided and different from `session.lastImageUrl`, completely clears session
- Creates fresh session with `domain: "general"`

**File:** `node/src/routes/agent.ts` line 262-274  
**Function:** `handleRequest()` - Image search conversation history clearing

**Signal:** **Image Search**
- If `imageUrl` is provided, completely clears `conversationHistory`
- Prevents old image search context from interfering

### **D. Domain/Intent Change Detection:**

**File:** `node/src/utils/followUpIntent.ts` line 125-240  
**Function:** `detectFollowUpIntent()`

**Process:**
1. Checks explicit intent first (line 147-148)
2. If explicit intent differs from previous intent, returns explicit intent (new query)
3. If query is strong (not weak), uses explicit intent even if different from previous

**Conclusion:**
- **Primary Signal:** Explicit location mention (especially different location) = new query
- **LLM Detection:** LLM analyzes query and determines if it's a refinement or new query
- **Session Reset:** Image URL change triggers complete session reset
- **Intent Override:** LLM can override detected intent if it extracts different intent

---

## 6. Conflict Resolution

### **How System Handles Conflicting Context:**

**Approach:** **LLM-based with Rule-based Fallback**

### **A. Location Conflicts:**

**File:** `node/src/services/llmContextExtractor.ts` line 139-155  
**Function:** `mergeQueryContextWithLLM()`

**Resolution:**
- **Rule:** Current query's explicit location ALWAYS wins
- **Process:** If current query has location different from parent, returns current query as-is (no merging)
- **Example:** "hotels in paris" + "hotels in bangkok" → "hotels in paris" (current wins)

**File:** `node/src/routes/agent.ts` line 620-645  
**Function:** `handleRequest()` - Fallback

**Resolution:**
- Checks if current query has location
- Checks if current location differs from parent location
- If different, skips location merge

### **B. Domain/Intent Conflicts:**

**File:** `node/src/routes/agent.ts` line 547-579  
**Function:** `handleRequest()` - LLM intent override

**Resolution:**
- LLM extracts intent from current query
- If extracted intent differs from detected intent, overrides detected intent
- Updates `finalIntent` and `finalCardType` accordingly

### **C. Brand/Category Conflicts:**

**File:** `node/src/routes/agent.ts` line 610-618  
**Function:** `handleRequest()` - Fallback merging

**Resolution:**
- **Rule:** Current query's explicit mentions ALWAYS win
- **Process:** Only merges brand/category from parent if current query doesn't have it
- **Logic:** `if (parentSlots.brand && !qLower.includes(parentSlots.brand.toLowerCase()))`

### **D. Image Search Conflicts:**

**File:** `node/src/routes/agent.ts` line 381-409  
**Function:** `handleRequest()` - Image search handling

**Resolution:**
- **Rule:** New image URL = complete context reset
- **Process:**
  1. Completely deletes existing session
  2. Clears conversation history (line 262-274)
  3. Creates fresh session with `domain: "general"`

### **E. Price/Modifier Conflicts:**

**File:** `node/src/services/llmContextExtractor.ts` line 132-215  
**Function:** `mergeQueryContextWithLLM()`

**Resolution:**
- LLM prompt includes rule: "Preserve explicit mentions in current query (don't override) - this is the HIGHEST priority"
- LLM merges only missing context, never overrides explicit mentions

**Conclusion:**
- **Priority:** Current query's explicit mentions > Parent context
- **Location:** Current location always wins, no merging if different
- **Intent:** LLM can override detected intent based on query analysis
- **Image Search:** Complete reset (no conflict resolution needed)
- **Brand/Category:** Only merged if missing in current query

---

## 7. User Preference Memory

### **Does App Persist Long-Term Preferences?**

**Answer:** **YES** ✅ (Partially Implemented)

### **A. Preference Storage:**

**File:** `node/src/services/personalization/preferenceStorage.ts`  
**Function:** `storePreferenceSignal()` (line 38-65)

**Storage:**
- **Database:** PostgreSQL (`preference_signals` table)
- **Fields Stored:**
  - `user_id`
  - `conversation_id`
  - `query`
  - `intent`
  - `style_keywords` (array)
  - `price_mentions` (array)
  - `brand_mentions` (array)
  - `rating_mentions` (array)
  - `cards_shown` (JSON)
  - `user_interaction` (JSON)

**When Stored:**
- **File:** `node/src/routes/agent.ts` line 1493-1526
- **Function:** `handleRequest()` - After response is sent
- **Trigger:** If `safeCards.length > 0` and `userId` is valid
- **Process:** Extracts preference signals from query and cards, stores in background (non-blocking)

### **B. Preference Aggregation:**

**File:** `node/src/services/personalization/backgroundAggregator.ts`  
**Function:** `aggregateIfNeeded()` (line 69-105)

**Aggregation Triggers:**
1. **Conversation Count:** 5+ conversations since last aggregation
2. **Time-Based:** 24 hours since last aggregation
3. **Signal Count:** Minimum 3 signals required

**Process:**
- Aggregates signals into `user_preferences` table
- Computes confidence scores
- Extracts brand preferences, style keywords, price ranges, category preferences

**File:** `node/src/services/personalization/backgroundAggregator.ts` line 227-241  
**Function:** `startBackgroundJob()`

**Scheduler:**
- Runs immediately on startup (after 30 seconds)
- Then runs every hour

### **C. Preference Retrieval:**

**File:** `node/src/services/personalization/preferenceStorage.ts`  
**Function:** `getUserPreferences()` (line 70-91)

**Retrieval:**
- Queries `user_preferences` table by `user_id`
- Returns aggregated preferences with confidence scores

### **D. Preference Usage:**

**File:** `node/src/routes/agent.ts` line 423-496  
**Function:** `handleRequest()` - Personalization query detection

**Usage:**
1. **Detection:** Detects queries like "of my type", "of my taste", "in my style"
2. **Retrieval:** Gets user preferences if confidence >= 0.3
3. **Enhancement:** Enhances query with:
   - Brand preferences
   - Style keywords
   - Price ranges
   - Category-specific preferences

**File:** `node/src/routes/agent.ts` line 498-663  
**Function:** `handleRequest()` - General preference enhancement

**Usage:**
- For shopping/travel intents, enhances query with user preferences
- Uses `enhanceQueryWithPreferences()` function

### **E. Limitations:**

1. **No Frontend Persistence:** Preferences are NOT stored on frontend
2. **Database-Dependent:** Requires PostgreSQL connection
3. **Aggregation Delay:** Preferences aggregated in background (not real-time)
4. **Minimum Signals:** Requires 3+ signals before aggregation
5. **No Explicit User Control:** No UI for users to view/edit preferences

### **Where to Add Long-Term Preference Logic:**

**Frontend:**
- **File:** `lib/services/` - Create `UserPreferencesService.dart`
- **Storage:** SharedPreferences or local database
- **Sync:** Sync with backend preferences API

**Backend:**
- **File:** `node/src/routes/` - Create `preferences.ts` route
- **Endpoints:**
  - `GET /preferences` - Get user preferences
  - `PUT /preferences` - Update user preferences
  - `DELETE /preferences` - Clear user preferences

**UI:**
- **File:** `lib/screens/` - Create `PreferencesScreen.dart`
- **Features:**
  - View aggregated preferences
  - Edit preferences manually
  - Clear preferences
  - See preference confidence scores

**Conclusion:**
- **Backend:** Preferences stored in PostgreSQL, aggregated in background
- **Frontend:** No preference storage (would need to be added)
- **Usage:** Preferences used to enhance queries for personalization
- **Limitations:** Database-dependent, aggregation delay, no user control UI

---

## Summary: Current Capabilities and Limitations

### **Capabilities:**

1. **Session Storage:**
   - ✅ Frontend: In-memory (Riverpod) + disk (SharedPreferences) + cloud (PostgreSQL)
   - ✅ Backend: In-memory session state (30min TTL)
   - ✅ Chat history persists across app restarts

2. **Chat Reconstruction:**
   - ✅ Restores full conversation from cache
   - ✅ Skips backend API calls if data exists
   - ✅ Instant loading from local cache

3. **Conversation History:**
   - ✅ Sent to backend with each query
   - ✅ Used in LLM context for context-aware responses
   - ✅ Includes card context for better follow-up understanding

4. **Follow-Up Detection:**
   - ✅ LLM-based context extraction (handles edge cases)
   - ✅ Rule-based fallback (pattern matching)
   - ✅ Context healing for vague queries
   - ✅ Follow-up intent detection

5. **Intent Switching:**
   - ✅ LLM detects explicit location mentions (new query signal)
   - ✅ Location conflict detection (different location = new query)
   - ✅ Intent override based on LLM analysis
   - ✅ Image search triggers complete reset

6. **Conflict Resolution:**
   - ✅ Current query's explicit mentions always win
   - ✅ Location conflicts resolved (current location wins)
   - ✅ Intent conflicts resolved (LLM override)
   - ✅ Image search triggers complete reset

7. **User Preferences:**
   - ✅ Backend storage in PostgreSQL
   - ✅ Background aggregation (every 5 conversations or 24 hours)
   - ✅ Query enhancement with preferences
   - ✅ Personalization query detection ("of my type")

### **Limitations:**

1. **Backend Session Memory:**
   - ❌ Not persistent (lost on server restart)
   - ❌ 30-minute TTL (short-lived)
   - ❌ Max 1000 sessions (may evict active sessions)

2. **Conversation History:**
   - ⚠️ Frontend doesn't explicitly pass `conversationHistory` to `AgentService.askAgent()` (may be null)
   - ⚠️ History built from `sessionHistoryProvider` but may not be sent if provider is empty

3. **Follow-Up Detection:**
   - ⚠️ LLM-based (costs API calls, may fail)
   - ⚠️ Rule-based fallback is basic (may miss edge cases)
   - ⚠️ Context healing is rule-based (may not handle all vague queries)

4. **Intent Switching:**
   - ⚠️ Relies on LLM for complex cases (may be slow/expensive)
   - ⚠️ Rule-based detection may miss subtle intent changes
   - ⚠️ No explicit "new conversation" signal from user

5. **Conflict Resolution:**
   - ⚠️ LLM-based (may be inconsistent)
   - ⚠️ Rule-based fallback is basic
   - ⚠️ No explicit conflict resolution UI for users

6. **User Preferences:**
   - ❌ No frontend persistence
   - ❌ Database-dependent (fails if DB unavailable)
   - ❌ Aggregation delay (not real-time)
   - ❌ No user control UI
   - ❌ Requires 3+ signals before aggregation

### **Recommended Improvements:**

1. **Backend Session Persistence:**
   - Store session state in Redis or database
   - Extend TTL or make it configurable
   - Implement session cleanup job

2. **Conversation History:**
   - Explicitly build and pass `conversationHistory` in `AgentService.askAgent()`
   - Add logging to verify history is sent

3. **Follow-Up Detection:**
   - Cache LLM responses for common patterns
   - Improve rule-based fallback with more patterns
   - Add confidence scores for refinement detection

4. **Intent Switching:**
   - Add explicit "new conversation" button in UI
   - Cache LLM intent detection results
   - Improve rule-based intent change detection

5. **Conflict Resolution:**
   - Add explicit conflict resolution prompts to LLM
   - Log conflicts for analysis
   - Add user feedback mechanism

6. **User Preferences:**
   - Add frontend preference storage
   - Add user preference UI
   - Add real-time preference updates
   - Add preference export/import

