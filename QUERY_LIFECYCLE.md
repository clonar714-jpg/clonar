# Complete Query Lifecycle: From User Input to UI Display

## 📋 Table of Contents
1. [Overview](#overview)
2. [Architecture Diagram](#architecture-diagram)
3. [Phase-by-Phase Breakdown](#phase-by-phase-breakdown)
4. [File Reference Guide](#file-reference-guide)
5. [Data Flow](#data-flow)
6. [Key Components](#key-components)

---

## 🎯 Overview

This document explains the complete journey of a user's query from when they type it in the Flutter app until the answer appears on their screen. The system uses a **Perplexity-style agent architecture** with:

- **LLM-based classification** to determine search types and widgets
- **Parallel execution** of widgets and research actions
- **Iterative tool-based research** using an action registry
- **Server-Sent Events (SSE)** for real-time streaming
- **Block-based UI updates** for incremental rendering

---

## 🏗️ Architecture Diagram

```
┌─────────────────────────────────────────────────────────────────┐
│                    FLUTTER FRONTEND                            │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐        │
│  │ ShopScreen   │→ │ AgentProvider│→ │ StreamService│        │
│  │ (UI Input)   │  │ (State Mgmt) │  │ (SSE Client) │        │
│  └──────────────┘  └──────────────┘  └──────────────┘        │
└─────────────────────────────────────────────────────────────────┘
                            │ HTTP POST + SSE
                            ▼
┌─────────────────────────────────────────────────────────────────┐
│                    NODE.JS BACKEND                             │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐        │
│  │ /api/chat    │→ │ APISearchAgent│→ │ SessionManager│        │
│  │ (Route)      │  │ (Orchestrator)│  │ (SSE Events)  │        │
│  └──────────────┘  └──────────────┘  └──────────────┘        │
│                            │                                    │
│        ┌───────────────────┴───────────────────┐              │
│        │                                       │              │
│        ▼                                       ▼              │
│  ┌──────────────┐                      ┌──────────────┐      │
│  │  Classifier  │                      │   Widgets    │      │
│  │  (LLM)       │                      │  (Parallel)   │      │
│  └──────────────┘                      └──────────────┘      │
│        │                                       │              │
│        └───────────┬───────────────────────────┘              │
│                    ▼                                           │
│            ┌──────────────┐                                   │
│            │  Researcher  │                                   │
│            │  (Iterative) │                                   │
│            └──────────────┘                                   │
│                    │                                           │
│        ┌───────────┴───────────┐                             │
│        ▼                       ▼                             │
│  ┌──────────────┐      ┌──────────────┐                     │
│  │ ActionRegistry│      │  Writer LLM  │                     │
│  │ (web_search,  │      │  (Answer Gen)│                     │
│  │  etc.)        │      │              │                     │
│  └──────────────┘      └──────────────┘                     │
└─────────────────────────────────────────────────────────────────┘
```

---

## 📱 Phase-by-Phase Breakdown

### **PHASE 1: User Input in Flutter App**

#### Step 1.1: User Types Query
- **Location**: `lib/screens/ShopScreen.dart` or similar UI component
- **Action**: User types a query (e.g., "hotels in Knoxville") and presses submit
- **Trigger**: UI calls `ref.read(agentControllerProvider.notifier).submitQuery(query)`

#### Step 1.2: Agent Provider Receives Query
- **Location**: `lib/providers/agent_provider.dart`
- **Method**: `submitQuery(String query)`
- **What happens**:
  1. Creates a unique `sessionId` (UUID) for this query
  2. Creates an initial `QuerySession` object to track state
  3. Adds session to `sessionHistoryProvider` (for UI display)
  4. Builds conversation history from previous completed queries
  5. Calls `_handleStreamingResponse()` to start backend request

**Key Files**:
- `lib/providers/agent_provider.dart` - Main state management
- `lib/models/query_session.dart` - Session data model

---

### **PHASE 2: Flutter Sends Request to Backend**

#### Step 2.1: Create HTTP Request
- **Location**: `lib/services/agent_stream_service.dart`
- **Method**: `postStream(String endpoint, Map<String, dynamic> body)`
- **What happens**:
  1. Creates HTTP POST request to `http://127.0.0.1:4000/api/chat?stream=true`
  2. Sets headers:
     - `Content-Type: application/json`
     - `Accept: text/event-stream` (tells backend we want SSE streaming)
  3. Builds request body with:
     - Query text
     - Conversation history (formatted as `[['human', '...'], ['assistant', '...']]`)
     - Chat ID, Message ID
     - Model configuration (chatModel, embeddingModel)
     - Sources (web, academic, discussion, personal)
     - Optimization mode (speed, balanced, quality)
     - System instructions

#### Step 2.2: Establish SSE Connection
- **Location**: `lib/services/agent_stream_service.dart`
- **What happens**:
  - Opens HTTP connection to backend
  - Sends POST request
  - Waits for Server-Sent Events (SSE) stream to start
  - Returns `Stream<String>` for consuming SSE events

**Key Files**:
- `lib/services/agent_stream_service.dart` - SSE client service (singleton)
- `lib/services/ApiClient.dart` - Base HTTP client utilities

---

### **PHASE 3: Backend Receives Request**

#### Step 3.1: Route Handler Receives Request
- **Location**: `node/src/routes/chat.ts`
- **Endpoint**: `POST /api/chat`
- **What happens**:
  1. Validates request body using Zod schema (`chatRequestSchema`)
  2. Extracts query from `body.content` or `body.message.content`
  3. Converts history format from `[['human', '...'], ['assistant', '...']]` to `ChatTurnMessage[]`
  4. Creates a new `SessionManager` session
  5. Creates `AbortController` for cancellation support
  6. Sets up SSE headers immediately:
     - `Content-Type: text/event-stream`
     - `Connection: keep-alive`
     - `Cache-Control: no-cache`
  7. Flushes headers to establish connection
  8. Sends initial heartbeat and start event
  9. Calls `APISearchAgent.searchAsync()` with session and input

**Key Files**:
- `node/src/routes/chat.ts` - Main chat endpoint route handler
- `node/src/agent/APISearchAgent.ts` - Main agent orchestrator

#### Step 3.2: Session Manager Setup
- **Location**: `node/src/agent/APISearchAgent.ts` (SessionManager class)
- **What happens**:
  - Creates session with unique ID
  - Sets up event emitter for SSE events
  - Stores session in `sessionStore` for reconnection support
  - Subscribes to session events and streams them to client in SSE format

**Key Files**:
- `node/src/agent/APISearchAgent.ts` - SessionManager class (lines 53-195)
- `node/src/agent/sessionStore.ts` - Session storage for reconnection

---

### **PHASE 4: Query Classification**

#### Step 4.1: LLM-Based Classification
- **Location**: `node/src/agent/classifier.ts`
- **Method**: `classify(ClassifierInput)`
- **What happens**:
  1. Uses LLM's `generateObject()` with structured Zod schema
  2. Sends system prompt from `node/src/agent/prompts/classifier.ts`
  3. Includes conversation history and user query
  4. LLM returns structured classification:
     - `skipSearch`: boolean - Can query be answered without search?
     - `personalSearch`: boolean - Need user uploaded documents?
     - `academicSearch`: boolean - Need academic databases?
     - `discussionSearch`: boolean - Need forums/discussions?
     - `showWeatherWidget`: boolean - Show weather widget?
     - `showStockWidget`: boolean - Show stock widget?
     - `showCalculationWidget`: boolean - Show calculator widget?
     - `showProductWidget`: boolean - Show product/shopping widget?
     - `showHotelWidget`: boolean - Show hotel widget?
     - `showPlaceWidget`: boolean - Show place/restaurant widget?
     - `showMovieWidget`: boolean - Show movie widget?
  5. Also returns `standaloneFollowUp`: string - Self-contained reformulation of query

**Key Files**:
- `node/src/agent/classifier.ts` - Classification logic
- `node/src/agent/prompts/classifier.ts` - Classification prompt
- `node/src/agent/types.ts` - TypeScript types (ClassifierInput, ClassifierOutput)

**Example Classification Output**:
```typescript
{
  classification: {
    skipSearch: false,
    personalSearch: false,
    academicSearch: false,
    discussionSearch: false,
    showWeatherWidget: false,
    showStockWidget: false,
    showCalculationWidget: false,
    showProductWidget: false,
    showHotelWidget: true,  // ✅ Hotel query detected
    showPlaceWidget: false,
    showMovieWidget: false,
  },
  standaloneFollowUp: "hotels in Knoxville"
}
```

---

### **PHASE 5: Parallel Widget Execution**

#### Step 5.1: Widget Executor Determines Active Widgets
- **Location**: `node/src/services/widgets/executor.ts`
- **Method**: `WidgetExecutor.executeAll()`
- **What happens**:
  1. Iterates through all registered widgets
  2. For each widget, calls `widget.shouldExecute(classification)`
  3. Widgets check classification flags (e.g., `classification.showHotelWidget`)
  4. Only widgets that return `true` from `shouldExecute()` are executed

**Registered Widgets** (from `node/src/services/widgets/index.ts`):
- `weatherWidget` - Weather data
- `stockWidget` - Stock prices
- `calculatorWidget` - Math calculations
- `productWidget` - Product/shopping search
- `hotelWidget` - Hotel search and booking
- `placeWidget` - Places/restaurants search
- `movieWidget` - Movie/TV show information

#### Step 5.2: Widget Execution (Agent-Style)
- **Location**: Individual widget files (e.g., `node/src/services/widgets/hotelWidget.ts`)
- **What happens** (using hotel widget as example):
  1. **Intent Extraction**: Uses LLM's `generateObject()` with Zod schema to extract:
     - Location (city/address)
     - Check-in/check-out dates
     - Number of guests
     - Price range
     - Hotel type (luxury, budget, etc.)
     - Desired amenities
  2. **Multi-Source Data Fetching** (in parallel):
     - **Google Maps API**: Geocoding + Places Text Search + Place Details (for photos)
     - **SerpAPI**: `google_hotels` engine for structured hotel listings
     - **Booking.com**: Placeholder (future integration)
  3. **Data Merging**: Combines results from all sources, deduplicates by name/address
  4. **Formatting**: Transforms into hotel cards with:
     - Evidence section (facts: name, address, rating, reviews)
     - Commerce section (booking: price, link, photos)
  5. **Returns**: `WidgetResult[]` with hotel cards

**Key Files**:
- `node/src/services/widgets/executor.ts` - Widget registry and execution
- `node/src/services/widgets/index.ts` - Widget registration
- `node/src/services/widgets/hotelWidget.ts` - Hotel widget implementation
- `node/src/services/widgets/productWidget.ts` - Product widget
- `node/src/services/widgets/placeWidget.ts` - Place widget
- `node/src/services/widgets/movieWidget.ts` - Movie widget
- `node/src/services/widgets/weatherWidget.ts` - Weather widget
- `node/src/services/widgets/stockWidget.ts` - Stock widget
- `node/src/services/widgets/calculatorWidget.ts` - Calculator widget

**Widget Output Format**:
```typescript
{
  type: 'hotel',
  success: true,
  data: [
    {
      name: "Hotel Name",
      address: "123 Main St",
      rating: 4.5,
      reviewCount: 1200,
      photos: ["url1", "url2"],
      thumbnail: "url1",
      price: "$150/night",
      link: "https://booking.com/...",
      description: "...",
      source: "serpapi",
      // ... more fields
    }
  ],
  llmContext: "Formatted context for LLM answer generation"
}
```

#### Step 5.3: Widget Events Emitted
- **Location**: `node/src/agent/APISearchAgent.ts` (widgetPromise)
- **What happens**:
  - For each widget output, emits a `block` event via `session.emitBlock()`
  - Block type: `'widget'`
  - Block data: `{ widgetType: 'hotel', params: [...] }`
  - These events are streamed to frontend via SSE

---

### **PHASE 6: Research Execution (If Not Skipped)**

#### Step 6.1: Researcher Initialization
- **Location**: `node/src/agent/APISearchAgent.ts` (Researcher class)
- **Method**: `researcher.research(session, input)`
- **What happens**:
  1. Checks if `classification.skipSearch === true` (if so, skips research)
  2. Creates `Researcher` instance
  3. Determines max iterations based on mode:
     - `speed`: 2 iterations
     - `balanced`: 6 iterations
     - `quality`: 25 iterations
  4. Gets available actions from `ActionRegistry` based on classification
  5. Builds researcher prompt from `node/src/agent/prompts/researcher.ts`
  6. Initializes `agentMessageHistory` with system prompt and user query

**Key Files**:
- `node/src/agent/APISearchAgent.ts` - Researcher class (lines 208-497)
- `node/src/agent/prompts/researcher.ts` - Research prompts (speed/balanced/quality modes)
- `node/src/agent/actions/registry.ts` - Action registry

#### Step 6.2: Iterative Research Loop
- **Location**: `node/src/agent/APISearchAgent.ts` (Researcher.research)
- **What happens** (for each iteration, up to maxIteration):
  1. **LLM Tool Call Generation**:
     - Sends `agentMessageHistory` to LLM with available tools
     - LLM returns tool calls (e.g., `web_search`, `academic_search`, `done`)
  2. **Tool Call Validation**:
     - Filters out invalid `web_search` calls (missing `queries` array)
     - If no valid tool calls remain, skips iteration
  3. **Add Assistant Message to History**:
     - Only adds assistant `tool_calls` message if valid tool calls exist
     - Prevents invalid tool calls from being logged
  4. **Execute Actions**:
     - Calls `ActionRegistry.executeAll(safeToolCalls, config)`
     - Actions execute in parallel
     - Each action returns `ActionOutput`
  5. **Add Tool Results to History**:
     - Adds tool results as `tool` role messages to `agentMessageHistory`
  6. **Emit Research Progress**:
     - Emits `researchProgress` event with current step and action names
  7. **Check for Done**:
     - If `done` action is called, breaks loop
  8. **Repeat** until max iterations or `done` is called

**Available Actions** (from `node/src/agent/actions/`):
- `webSearchAction.ts` - General web search (SerpAPI)
- `academicSearchAction.ts` - Academic search (Google Scholar via SerpAPI)
- `discussionSearchAction.ts` - Discussion search (Reddit, forums via SerpAPI)
- `personalSearchAction.ts` - Personal document search (vector search)
- `doneAction.ts` - Signal research completion
- `reasoningAction.ts` - Reasoning preamble (for quality mode)

**Key Files**:
- `node/src/agent/actions/registry.ts` - Action registry and execution
- `node/src/agent/actions/webSearchAction.ts` - Web search implementation
- `node/src/agent/actions/academicSearchAction.ts` - Academic search
- `node/src/agent/actions/discussionSearchAction.ts` - Discussion search
- `node/src/agent/actions/personalSearchAction.ts` - Personal document search
- `node/src/agent/actions/doneAction.ts` - Done action
- `node/src/services/searchService.ts` - Unified search service (used by actions)

#### Step 6.3: Search Service Execution
- **Location**: `node/src/services/searchService.ts`
- **Method**: `search(query, searchType, options)`
- **What happens** (for `web_search` action):
  1. Calls SerpAPI with appropriate engine:
     - `web`: General web search
     - `google_scholar`: Academic search
     - `reddit`: Discussion search
  2. Extracts results:
     - `organic_results`: Web pages
     - `images`: Image results
     - `videos`: Video results
  3. Transforms to `Document[]` format:
     - Title, URL, content snippet
     - Thumbnail images
     - Metadata (author, date, etc.)
  4. Returns `{ documents, rawResponse, images, videos }`

**Key Files**:
- `node/src/services/searchService.ts` - Unified search service
- `node/src/services/types.ts` - Document interface (if exists)

#### Step 6.4: Research Results Aggregation
- **Location**: `node/src/agent/APISearchAgent.ts` (Researcher.research)
- **What happens**:
  1. Collects all `ActionOutput[]` from all iterations
  2. Extracts `Chunk[]` from search actions
  3. Returns `ResearcherOutput`:
     ```typescript
     {
       chunks: Chunk[],  // Search findings
       images: string[],  // Aggregated images
       videos: string[],  // Aggregated videos
     }
     ```

---

### **PHASE 7: Answer Generation**

#### Step 7.1: Context Preparation
- **Location**: `node/src/agent/APISearchAgent.ts` (APISearchAgent.searchAsync)
- **What happens**:
  1. Waits for both `widgetPromise` and `searchPromise` to complete
  2. Aggregates context:
     - **Search Findings**: Formats `chunks` from research as `<result>` XML tags
     - **Widget Context**: Formats widget outputs as `<widgets_result>` XML tags
  3. Combines into `finalContextWithWidgets`:
     ```xml
     <search_results>
       <result index=1 title="...">...</result>
       <result index=2 title="...">...</result>
       ...
     </search_results>
     <widgets_result>
       <result>Hotel widget context...</result>
       ...
     </widgets_result>
     ```
  4. Builds writer prompt using `getWriterPrompt()` from `node/src/agent/prompts/writer.ts`

**Key Files**:
- `node/src/agent/prompts/writer.ts` - Writer system prompt
- `node/src/agent/APISearchAgent.ts` - Context aggregation (lines 690-712)

#### Step 7.2: LLM Answer Streaming
- **Location**: `node/src/agent/APISearchAgent.ts` (APISearchAgent.searchAsync)
- **What happens**:
  1. Calls LLM's `streamText()` with:
     - System prompt (writer prompt with context)
     - Chat history
     - User query
  2. Streams answer chunks in real-time:
     - For each chunk, creates or updates a `TextBlock`
     - Emits `block` event (new block) or `updateBlock` event (update existing)
     - Uses RFC 6902 JSON Patch format for updates
  3. Accumulates full answer text

**Key Files**:
- `node/src/agent/APISearchAgent.ts` - Answer streaming (lines 714-845)
- `node/src/models/llms/openai.ts` - LLM adapter (streamText implementation)

#### Step 7.3: Follow-Up Suggestions Generation
- **Location**: `node/src/agent/APISearchAgent.ts` (APISearchAgent.searchAsync)
- **What happens**:
  1. Uses Perplexity-style follow-up system
  2. Generates suggestions based on:
     - Query context
     - Search results
     - Widget outputs
  3. Returns array of follow-up question strings

**Key Files**:
- `node/src/agent/APISearchAgent.ts` - Follow-up generation (lines 847-890)

#### Step 7.4: Final Aggregation
- **Location**: `node/src/agent/APISearchAgent.ts` (APISearchAgent.searchAsync)
- **What happens**:
  1. Aggregates images from:
     - Search findings (`chunks[].metadata.thumbnail`, `chunks[].metadata.images`)
     - Widget outputs (`cards[].photos`, `cards[].thumbnail`)
  2. Aggregates sources from:
     - Search findings (`chunks[].metadata`)
     - Widget outputs (`cards[].link`)
  3. Emits final `end` event with:
     - Complete answer
     - Follow-up suggestions
     - Sources
     - Images
     - Widget data

**Key Files**:
- `node/src/agent/APISearchAgent.ts` - Final aggregation (lines 891-1042)

---

### **PHASE 8: SSE Streaming to Frontend**

#### Step 8.1: Event Formatting
- **Location**: `node/src/routes/chat.ts` (session subscription)
- **What happens**:
  1. Session events are formatted as SSE:
     - Format: `data: {json}\n\n`
     - Each event includes `eventId` and `sessionId` for idempotency
  2. Event types:
     - `block`: New block created (text, widget, etc.)
     - `updateBlock`: Block updated (RFC 6902 patch)
     - `researchProgress`: Research iteration progress
     - `end`: Final event with complete answer
     - `error`: Error event
  3. Heartbeat sent every 15 seconds to keep connection alive

**Key Files**:
- `node/src/routes/chat.ts` - SSE event formatting (lines 182-239)

#### Step 8.2: Connection Management
- **Location**: `node/src/routes/chat.ts`
- **What happens**:
  1. Monitors client disconnect:
     - Listens for `req.on('close')` and `res.on('close')`
     - Aborts all operations via `AbortController` on disconnect
  2. Handles abort signals:
     - Terminates SSE stream gracefully
     - Emits final event before closing
  3. Cleans up on completion:
     - Clears heartbeat interval
     - Closes response stream

**Key Files**:
- `node/src/routes/chat.ts` - Connection management (lines 100-176)

---

### **PHASE 9: Frontend Receives SSE Events**

#### Step 9.1: Stream Consumption
- **Location**: `lib/providers/agent_provider.dart`
- **Method**: `_handleStreamingResponse()`
- **What happens**:
  1. Consumes `Stream<String>` from `AgentStreamService.postStream()`
  2. Parses SSE format:
     - Splits by `\n\n` to get individual events
     - Extracts JSON from `data: {...}` lines
  3. Implements idempotency:
     - Tracks `_processedEventIds` per session
     - Ignores duplicate events (by `eventId` or `sessionId + blockId + eventId`)

#### Step 9.2: Event Processing
- **Location**: `lib/providers/agent_provider.dart`
- **What happens** (for each event type):

  **`block` event**:
  - Creates new block in session
  - Types: `text`, `widget`, `research`
  - Updates `QuerySession` state

  **`updateBlock` event**:
  - Applies RFC 6902 JSON Patch to existing block
  - Updates accumulated text in real-time
  - Updates `QuerySession.answer` and `QuerySession.summary`

  **`researchProgress` event**:
  - Updates research progress indicator
  - Shows current step and action names

  **`end` event**:
  - Finalizes session:
    - Sets `isFinalized: true`
    - Sets `isStreaming: false`
    - Extracts final answer, sources, follow-ups, images, cards
  - Updates `QuerySession` with complete data
  - Changes agent state to `AgentState.completed`

  **`error` event**:
  - Handles errors gracefully
  - Updates session with error state

**Key Files**:
- `lib/providers/agent_provider.dart` - Event processing (lines 722-1322)
- `lib/models/query_session.dart` - QuerySession model

---

### **PHASE 10: UI Rendering**

#### Step 10.1: Navigation to Results Screen
- **Location**: `lib/screens/ShopScreen.dart`
- **What happens**:
  1. User submits query in `ShopScreen`
  2. `ShopScreen` navigates to `ShoppingResultsScreen` via `Navigator.push()`
  3. Passes query, imageUrl, and conversationId to results screen
  4. Results screen handles the actual query submission and result display

**Key Files**:
- `lib/screens/ShopScreen.dart` - Main search input screen
- `lib/screens/ShoppingResultsScreen.dart` - Main results display screen

#### Step 10.2: Results Screen Initialization
- **Location**: `lib/screens/ShoppingResultsScreen.dart`
- **What happens**:
  1. Receives query from `ShopScreen`
  2. Checks if query already submitted (prevents duplicates)
  3. If not in replay mode, calls `agentControllerProvider.submitQuery()`
  4. Watches `sessionHistoryProvider` for session updates
  5. Uses `SessionRenderer` widget to display results

**Key Files**:
- `lib/screens/ShoppingResultsScreen.dart` - Results screen implementation
- `lib/widgets/SessionRenderer.dart` - Renders query sessions

#### Step 10.3: Widget Rebuild
- **Location**: `lib/widgets/SessionRenderer.dart` → `lib/widgets/PerplexityAnswerWidget.dart`
- **What happens**:
  1. `SessionRenderer` watches `sessionHistoryProvider`
  2. For each `QuerySession`, renders `PerplexityAnswerWidget`
  3. `QuerySession` changes trigger widget rebuilds
  4. Renders based on session state:
     - `isStreaming: true` → Shows loading indicator
     - `isFinalized: false` → Shows streaming answer
     - `isFinalized: true` → Shows complete answer

#### Step 10.4: Answer Display
- **Location**: `lib/widgets/PerplexityAnswerWidget.dart`
- **What happens**:
  1. Displays answer text (from `session.answer` or `session.summary`)
  2. Renders cards (hotels, products, places, movies) if present
  3. Shows sources section (if sources exist)
  4. Shows media section (if images exist)
  5. Displays follow-up suggestions
  6. Handles navigation to detail screens:
     - `HotelResultsScreen` - For hotel-specific queries
     - `ProductDetailScreen` - For product details
     - `PlaceDetailScreen` - For place details
     - `MovieDetailScreen` - For movie details

**Key Files**:
- `lib/widgets/PerplexityAnswerWidget.dart` - Main answer widget
- `lib/widgets/SessionRenderer.dart` - Session renderer wrapper
- `lib/screens/HotelResultsScreen.dart` - Hotel-specific results screen
- `lib/screens/ProductDetailScreen.dart` - Product detail screen
- `lib/screens/PlaceDetailScreen.dart` - Place detail screen
- `lib/screens/MovieDetailScreen.dart` - Movie detail screen

#### Step 10.3: Chat History Persistence
- **Location**: `lib/services/ChatHistoryServiceCloud.dart`
- **What happens** (when user navigates away or app closes):
  1. Saves session to backend via `POST /chats/{chatId}/messages`
  2. Sends:
     - Query
     - Answer
     - Sources
     - Follow-up suggestions
     - Images (`destinationImages` array)
     - Cards data
  3. Backend stores in `conversation_messages` table:
     - `query`: User query
     - `answer`: Complete answer text
     - `results`: JSONB with `destination_images` array
     - `sources`: JSONB array
     - `follow_up_suggestions`: JSONB array

**Key Files**:
- `lib/services/ChatHistoryServiceCloud.dart` - Chat history service
- `node/src/routes/chats.ts` - Chat history API endpoint
- `lib/services/conversation_hydration.dart` - Loads past chats from backend

---

## 📁 File Reference Guide

### **Frontend Files**

#### Core State Management
- `lib/providers/agent_provider.dart` - Main agent state provider, handles SSE events
- `lib/providers/session_history_provider.dart` - Session history state management
- `lib/models/query_session.dart` - QuerySession data model

#### Services
- `lib/services/agent_stream_service.dart` - SSE client service (singleton)
- `lib/services/ChatHistoryServiceCloud.dart` - Chat history persistence
- `lib/services/conversation_hydration.dart` - Loads past chats from database
- `lib/services/ApiClient.dart` - Base HTTP client utilities

#### UI Components
- `lib/screens/ShopScreen.dart` - Main search input screen (where users type queries)
- `lib/screens/ShoppingResultsScreen.dart` - Main results display screen (navigated to from ShopScreen)
- `lib/screens/HotelResultsScreen.dart` - Hotel-specific results screen
- `lib/screens/ProductDetailScreen.dart` - Product detail screen
- `lib/screens/PlaceDetailScreen.dart` - Place detail screen
- `lib/screens/MovieDetailScreen.dart` - Movie detail screen
- `lib/widgets/PerplexityAnswerWidget.dart` - Main answer display widget (used inside ShoppingResultsScreen)
- `lib/widgets/SessionRenderer.dart` - Renders query sessions (wrapper around PerplexityAnswerWidget)

### **Backend Files**

#### Routes
- `node/src/routes/chat.ts` - Main chat endpoint (`POST /api/chat`)

#### Agent Core
- `node/src/agent/APISearchAgent.ts` - Main agent orchestrator
  - `SessionManager` class - SSE event management
  - `Researcher` class - Iterative research execution
  - `APISearchAgent` class - Main search agent
- `node/src/agent/classifier.ts` - LLM-based query classification
- `node/src/agent/types.ts` - TypeScript type definitions
- `node/src/agent/sessionStore.ts` - Session storage for reconnection

#### Prompts
- `node/src/agent/prompts/classifier.ts` - Classification prompt
- `node/src/agent/prompts/researcher.ts` - Research prompts (speed/balanced/quality)
- `node/src/agent/prompts/writer.ts` - Writer/answer generation prompt

#### Actions (Research Tools)
- `node/src/agent/actions/registry.ts` - Action registry and execution
- `node/src/agent/actions/webSearchAction.ts` - Web search action
- `node/src/agent/actions/academicSearchAction.ts` - Academic search action
- `node/src/agent/actions/discussionSearchAction.ts` - Discussion search action
- `node/src/agent/actions/personalSearchAction.ts` - Personal document search action
- `node/src/agent/actions/doneAction.ts` - Done action
- `node/src/agent/actions/reasoningAction.ts` - Reasoning preamble action

#### Widgets
- `node/src/services/widgets/executor.ts` - Widget registry and execution
- `node/src/services/widgets/index.ts` - Widget registration
- `node/src/services/widgets/hotelWidget.ts` - Hotel widget (agent-style)
- `node/src/services/widgets/productWidget.ts` - Product widget (agent-style)
- `node/src/services/widgets/placeWidget.ts` - Place widget (agent-style)
- `node/src/services/widgets/movieWidget.ts` - Movie widget (agent-style)
- `node/src/services/widgets/weatherWidget.ts` - Weather widget
- `node/src/services/widgets/stockWidget.ts` - Stock widget
- `node/src/services/widgets/calculatorWidget.ts` - Calculator widget

#### Services
- `node/src/services/searchService.ts` - Unified search service (SerpAPI)
- `node/src/services/fileSearchService.ts` - File/document search service

#### Models
- `node/src/models/llms/openai.ts` - OpenAI LLM adapter
- `node/src/models/llms/registry.ts` - LLM registry
- `node/src/models/types.ts` - Model type definitions

#### Utilities
- `node/src/utils/formatHistory.ts` - Chat history formatting utilities
- `node/src/utils/agentConfigHelper.ts` - Agent configuration helper

---

## 🔄 Data Flow

### **Request Flow**
```
User Input (ShopScreen)
  ↓
Navigate to ShoppingResultsScreen
  ↓
AgentProvider.submitQuery()
  ↓
AgentStreamService.postStream()
  ↓
HTTP POST /api/chat
  ↓
chat.ts route handler
  ↓
APISearchAgent.searchAsync()
  ↓
┌─────────────────┬─────────────────┐
│  Classifier     │  WidgetExecutor │
│  (LLM)          │  (Parallel)     │
└─────────────────┴─────────────────┘
  ↓
Researcher.research()
  ↓
ActionRegistry.executeAll()
  ↓
searchService.search()
  ↓
Writer LLM (streamText)
  ↓
SSE Events
  ↓
Frontend Event Processing (ShoppingResultsScreen)
  ↓
SessionRenderer → PerplexityAnswerWidget
  ↓
UI Update
```

### **Response Flow (SSE Events)**
```
SessionManager.emitBlock()
  ↓
session.subscribe() handler
  ↓
SSE format: data: {json}\n\n
  ↓
HTTP Response Stream
  ↓
AgentStreamService Stream<String>
  ↓
AgentProvider._handleStreamingResponse()
  ↓
QuerySession update
  ↓
Widget rebuild
  ↓
UI rendering
```

---

## 🔑 Key Components

### **1. SessionManager**
- **Purpose**: Manages SSE event streaming and session state
- **Key Methods**:
  - `emitBlock(block)` - Emit a new block
  - `updateBlock(id, patch)` - Update existing block (RFC 6902)
  - `subscribe(callback)` - Subscribe to session events
- **Location**: `node/src/agent/APISearchAgent.ts` (lines 53-195)

### **2. Classifier**
- **Purpose**: Determines search types and widgets to activate
- **Input**: User query + conversation history
- **Output**: Structured classification object
- **Location**: `node/src/agent/classifier.ts`

### **3. WidgetExecutor**
- **Purpose**: Registry pattern for widget execution
- **Key Methods**:
  - `register(widget)` - Register a widget
  - `executeAll(input)` - Execute all applicable widgets in parallel
- **Location**: `node/src/services/widgets/executor.ts`

### **4. Researcher**
- **Purpose**: Iterative tool-based research execution
- **Key Features**:
  - LLM-driven tool calling
  - Multiple iterations (based on mode)
  - Action registry pattern
- **Location**: `node/src/agent/APISearchAgent.ts` (lines 208-497)

### **5. ActionRegistry**
- **Purpose**: Registry pattern for research actions
- **Key Methods**:
  - `register(action)` - Register an action
  - `getAvailableActions(config)` - Get enabled actions
  - `executeAll(toolCalls, config)` - Execute actions in parallel
- **Location**: `node/src/agent/actions/registry.ts`

### **6. AgentStreamService**
- **Purpose**: Singleton SSE client service
- **Key Features**:
  - Single HttpClient instance (reused)
  - Single active StreamSubscription
  - Connection management
- **Location**: `lib/services/agent_stream_service.dart`

### **7. AgentProvider**
- **Purpose**: Main Flutter state management for agent
- **Key Features**:
  - SSE event processing
  - Session state management
  - Idempotency handling
- **Location**: `lib/providers/agent_provider.dart`

---

## 🎯 Summary

The system follows a **Perplexity-style architecture** with:

1. **LLM-based classification** to determine what to do
2. **Parallel execution** of widgets and research
3. **Iterative tool-based research** using an action registry
4. **Real-time streaming** via Server-Sent Events (SSE)
5. **Block-based UI updates** for incremental rendering
6. **Graceful error handling** and cancellation support

The entire flow from user input to UI display typically takes **2-10 seconds** depending on:
- Query complexity
- Number of widgets activated
- Research iterations needed
- Optimization mode (speed/balanced/quality)

---

**Last Updated**: 2024
**Version**: 1.0

