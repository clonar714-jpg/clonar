# Files to Include for Open Source Release

## Frontend (Flutter/Dart)

### Core Screens (Required)
```
lib/screens/
├── ShopScreen.dart                    # Main search interface with query input
└── ClonarAnswerScreen.dart            # Answer display screen with follow-ups
```

### Core Widgets (Required)
```
lib/widgets/
├── ClonarAnswerWidget.dart            # Main answer rendering widget
├── SessionRenderer.dart                # Session rendering logic
└── ResearchActivityWidget.dart        # Research progress indicator
```

### Providers (Required - State Management)
```
lib/providers/
├── agent_provider.dart                # Core agent state and query submission
├── session_history_provider.dart      # Session history management
├── session_phase_provider.dart        # Query phase tracking (searching/answering/done)
├── session_stream_provider.dart       # Streaming state management
├── follow_up_controller_provider.dart # Follow-up suggestion handling
├── conversation_loader_provider.dart  # Loading chat history from backend
├── query_state_provider.dart          # Query text state
├── parsed_agent_output_provider.dart  # Parsed agent response
├── display_content_provider.dart      # Content display state
├── scroll_provider.dart               # Scroll position management
└── streaming_text_provider.dart       # Streaming text state
```

### Services (Required)
```
lib/services/
├── agent_stream_service.dart          # SSE streaming client
├── ChatHistoryServiceCloud.dart       # Chat history persistence
└── conversation_hydration.dart        # Converting backend messages to sessions
```

### Models (Required)
```
lib/models/
├── query_session_model.dart           # QuerySession data model
└── Product.dart                       # Product model (used in cards)
```

### Core Utilities (Required)
```
lib/core/
├── api_client.dart                    # HTTP client for API calls
└── provider_observer.dart             # Riverpod observer
```

### Utils (Required)
```
lib/utils/
└── card_converters.dart               # Converts backend cards to Product objects
```

### Theme (Required)
```
lib/theme/
├── AppColors.dart                     # Color definitions
└── Typography.dart                    # Text styles
```

### Main Entry Point (Required)
```
lib/main.dart                          # App entry point (simplified version)
```

---

## Backend (Node.js/TypeScript)

### Core Agent System (Required)
```
node/src/agent/
├── APISearchAgent.ts                  # Main agent orchestrator
├── classifier.ts                      # Query classification
├── detail.handler.ts                  # Detail page content generation
├── sessionStore.ts                    # Session storage
├── types.ts                           # TypeScript types
├── actions/
│   ├── index.ts                       # Action exports
│   ├── registry.ts                    # Action registry
│   ├── webSearchAction.ts             # Web search action
│   ├── academicSearchAction.ts        # Academic search action
│   ├── socialSearchAction.ts          # Discussion search action
│   ├── uploadsSearchAction.ts         # File search action
│   ├── scrapeURLAction.ts            # URL scraping action
│   ├── reasoningPreambleAction.ts    # Reasoning action
│   └── doneAction.ts                  # Done action
└── prompts/
    ├── classifier.ts                  # Classification prompts
    ├── researcher.ts                  # Research prompts
    └── writer.ts                      # Answer generation prompts
```

### Routes (Required)
```
node/src/routes/
├── chat.ts                            # Main streaming chat endpoint (POST /api/chat)
├── chats.ts                           # Chat history endpoints (GET /api/chats)
├── autocomplete.ts                    # Autocomplete suggestions (GET /api/autocomplete)
└── reconnect.ts                       # SSE reconnection endpoint
```

### Services (Required)
```
node/src/services/
├── searchService.ts                   # Web search service (SerpAPI)
├── searxngService.ts                  # SearxNG search service
├── queryGenerator.ts                  # Query generation/rewriting
└── database.ts                        # Database connection
```

### Models (Required - LLM Provider System)
```
node/src/models/
├── base/
│   ├── llm.ts                         # Base LLM interface
│   ├── embedding.ts                  # Base embedding interface
│   └── provider.ts                    # Base provider interface
├── llms/
│   └── openai.ts                      # OpenAI LLM implementation
├── embeddings/
│   └── openai.ts                      # OpenAI embedding implementation
├── providers/
│   ├── openai.ts                      # OpenAI provider
│   └── registry.ts                    # Provider registry
├── registry.ts                        # Model registry
└── types.ts                           # Model types
```

### Configuration (Required)
```
node/src/config/
├── accessors.ts                       # Config accessors
├── configManager.ts                   # Configuration management
├── serverRegistry.ts                  # Server registry
└── types.ts                           # Config types
```

### Middleware (Required)
```
node/src/middleware/
├── errorHandler.ts                    # Error handling
├── notFoundHandler.ts                  # 404 handler
└── validation.ts                      # Request validation
```

### Utils (Required)
```
node/src/utils/
├── agentConfigHelper.ts               # Agent configuration helper
├── formatHistory.ts                   # Chat history formatting
├── errorResponse.ts                   # Error response formatting
└── serverUtils.ts                     # Server utilities
```

### Follow-up System (Required)
```
node/src/followup/
├── index.ts                           # Follow-up generation entry
├── smartFollowups.ts                  # Smart follow-up generation
├── answerCoverage.ts                  # Answer coverage analysis
├── answerGapExtractor.ts              # Gap extraction
├── attributeExtractor.ts              # Attribute extraction
├── cardAnalyzer.ts                    # Card analysis
├── followupScorer.ts                  # Follow-up scoring
├── intentStage.ts                     # Intent stage detection
├── rerankFollowups.ts                 # Follow-up reranking
├── slotFiller.ts                      # Slot filling
└── templates.ts                      # Follow-up templates
```

### Database (Required)
```
node/src/db/
├── index.ts                           # Database connection
├── schema.ts                          # Database schema
└── migrate.ts                         # Migration utilities
```

### Main Entry Point (Required)
```
node/src/index.ts                      # Express server entry point
node/package.json                      # Dependencies
node/tsconfig.json                     # TypeScript config
```

---

## Configuration Files

### Frontend
```
pubspec.yaml                           # Flutter dependencies
analysis_options.yaml                  # Dart analyzer config
```

### Backend
```
node/.env.example                      # Environment variables template
node/package.json                      # Node.js dependencies
node/tsconfig.json                     # TypeScript configuration
```

---

## Documentation
```
README.md                              # Main README
```

---

## Files to EXCLUDE (Not Needed for Open Source)

### Frontend
- `lib/screens/ShopScreenExtras.dart` - Extra features (notifications, quick actions, nav bar)
- `lib/screens/AccountScreen.dart` - Account management
- `lib/screens/FeedScreen.dart` - Feed screen
- `lib/screens/WardrobeScreen.dart` - Wardrobe screen
- `lib/screens/WishlistScreen.dart` - Wishlist screen
- `lib/screens/LoginPage.dart` - Authentication (if not needed)
- `lib/screens/RegisterPage.dart` - Registration (if not needed)
- `lib/screens/CollageEditorPage.dart` - Collage features
- `lib/screens/PersonaDetailPage.dart` - Persona features
- All other non-essential screens

### Backend
- `node/src/routes/collages.ts` - Collage routes
- `node/src/routes/personas.ts` - Persona routes
- `node/src/routes/users.ts` - User management
- `node/src/routes/auth.ts` - Authentication (if not needed)
- `node/src/services/personalization/` - Personalization features
- `node/src/services/widgets/` - Widget system (optional, can be included if needed)

---

## Summary

**Minimum Required Files:**
- 2 screens (ShopScreen, ClonarAnswerScreen)
- 3-4 core widgets
- 11 providers
- 3 services
- 2 models
- Core utilities and theme
- All agent system files
- 4 main routes (chat, chats, autocomplete, reconnect)
- Core services and models
- Configuration and middleware

**Total: ~80-100 files** for a fully functional agent system with query input, answer display, and chat history.

