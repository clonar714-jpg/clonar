# Open Source Strategy for Agentic Framework

## 🎯 Goal
Create a clean, reusable, production-ready agentic framework that can be easily integrated into any application.

## 📦 What to Include

### ✅ Core Framework Files (MUST INCLUDE)

#### 1. **Agent Core** (`node/src/agent/`)
- ✅ `agent.handler.simple.ts` - Main simplified handler (82 lines, clean architecture)
- ✅ `agent.validation.ts` - Request validation with Zod
- ✅ `agent.queue.ts` - Request queuing system
- ✅ `index.ts` - Route handler
- ❌ `detail.handler.ts` - App-specific (hotel/product details), exclude

**Why**: These are the core entry points. The simple handler is the main innovation - clean, maintainable, and easy to understand.

#### 2. **Core Services** (`node/src/services/`)
- ✅ `perplexityAnswer.ts` - Main service (LangChain-style flow)
- ✅ `queryGenerator.ts` - Query optimization
- ✅ `documentSummarizer.ts` - Document summarization
- ✅ `answerParser.ts` - Structured answer parsing
- ❌ `llmAnswer.ts` - Legacy, replaced by perplexityAnswer
- ❌ `llmQueryRefiner.ts` - App-specific logic
- ❌ `llmContextExtractor.ts` - App-specific
- ❌ `llmContextCache.ts` - App-specific
- ❌ `imageAnalysis.ts` - Optional, can be included if generic enough
- ❌ All personalization files - App-specific
- ❌ All provider files - App-specific (hotels, products, etc.)
- ❌ All domain-specific services (hotelSearch, productSearch, etc.)

**Why**: `perplexityAnswer.ts` is the heart of the framework - it implements the LangChain-style flow. Query generation and document summarization are reusable utilities.

#### 3. **Embeddings** (`node/src/embeddings/`)
- ✅ `embeddingClient.ts` - Embedding generation and cosine similarity

**Why**: Essential for reranking search results by relevance.

#### 4. **Utilities** (`node/src/utils/`)
- ✅ `errorResponse.ts` - Standardized error responses
- ✅ `sse.ts` - Server-Sent Events for streaming
- ✅ `retryWithBackoff.ts` - Retry logic
- ❌ `cardFetchDecision.ts` - App-specific
- ❌ `semanticIntent.ts` - App-specific
- ❌ `followUpIntent.ts` - App-specific
- ❌ `streamingOptimizer.ts` - App-specific
- ❌ `userIdHelper.ts` - App-specific

**Why**: Error handling and streaming are core features. Retry logic is a good utility.

#### 5. **Stability** (`node/src/stability/`)
- ✅ `rateLimiter.ts` - Rate limiting
- ✅ `circuitBreaker.ts` - Circuit breaker pattern
- ✅ `errorHandlers.ts` - Global error handling
- ✅ `memoryFlush.ts` - Memory management
- ✅ `streamingSessionManager.ts` - Streaming session management
- ✅ `userThrottle.ts` - User-level throttling

**Why**: Production-ready stability features that make the framework robust.

#### 6. **Middleware** (`node/src/middleware/`)
- ✅ `errorHandler.ts` - Error handling middleware
- ✅ `validation.ts` - Request validation middleware
- ✅ `notFoundHandler.ts` - 404 handler
- ❌ `auth.ts` - App-specific authentication
- ❌ `upload.ts` - App-specific file upload
- ❌ `skipAuthInDev.ts` - App-specific

**Why**: Core middleware that's framework-agnostic.

#### 7. **Routes** (`node/src/routes/`)
- ✅ `agent.ts` - Main agent route
- ❌ All other routes - App-specific

**Why**: Only the agent route is part of the framework.

#### 8. **Memory** (`node/src/memory/`) - OPTIONAL
- ✅ `SessionStore.ts` - Abstract session store interface
- ✅ `InMemorySessionStore.ts` - In-memory implementation
- ✅ `RedisSessionStore.ts` - Redis implementation
- ✅ `sessionMemory.ts` - Session memory utilities
- ❌ `genderDetector.ts` - App-specific

**Why**: Memory management is useful but optional. Include abstract interfaces so users can implement their own.

### ❌ Exclude (App-Specific)

1. **Domain-Specific Services**
   - Product search, hotel search, restaurant search, flight search
   - TMDB service, places search
   - All provider implementations

2. **Personalization**
   - All personalization files (user preferences, etc.)

3. **App-Specific Routes**
   - Auth, users, uploads, chats, etc.

4. **App-Specific Utilities**
   - Card fetching, intent detection, etc.

5. **Empty/Deleted Folders**
   - filters/, correctors/, reranker/, slots/, followup/, planner/

## 📁 Recommended Structure

```
agent-framework/
├── README.md                    # Comprehensive documentation
├── LICENSE                      # MIT or your choice
├── .env.example                 # Environment variables template
├── package.json                 # Filtered dependencies
├── tsconfig.json               # TypeScript config
├── node/
│   └── src/
│       ├── index.ts             # Minimal Express server example
│       ├── agent/
│       │   ├── agent.handler.simple.ts
│       │   ├── agent.validation.ts
│       │   ├── agent.queue.ts
│       │   └── index.ts
│       ├── services/
│       │   ├── perplexityAnswer.ts
│       │   ├── queryGenerator.ts
│       │   ├── documentSummarizer.ts
│       │   └── answerParser.ts
│       ├── embeddings/
│       │   └── embeddingClient.ts
│       ├── utils/
│       │   ├── errorResponse.ts
│       │   ├── sse.ts
│       │   └── retryWithBackoff.ts
│       ├── stability/
│       │   ├── rateLimiter.ts
│       │   ├── circuitBreaker.ts
│       │   ├── errorHandlers.ts
│       │   ├── memoryFlush.ts
│       │   ├── streamingSessionManager.ts
│       │   └── userThrottle.ts
│       ├── middleware/
│       │   ├── errorHandler.ts
│       │   ├── validation.ts
│       │   └── notFoundHandler.ts
│       ├── routes/
│       │   └── agent.ts
│       └── memory/              # Optional
│           ├── SessionStore.ts
│           ├── InMemorySessionStore.ts
│           ├── RedisSessionStore.ts
│           └── sessionMemory.ts
└── examples/
    └── basic-usage.ts           # Example integration
```

## 🔧 Configuration Files

### package.json
- Keep only framework dependencies
- Remove app-specific dependencies
- Add clear description and keywords

### .env.example
```env
# OpenAI Configuration
OPENAI_API_KEY=your_openai_api_key_here

# Server Configuration
PORT=4000
NODE_ENV=development

# CORS Configuration
CORS_ORIGIN=http://localhost:3000

# Redis Configuration (optional)
REDIS_URL=redis://localhost:6379
SESSION_STORAGE_TYPE=memory
```

### tsconfig.json
- Keep standard TypeScript config
- Use path aliases (@/) if needed

## 📝 Documentation Requirements

1. **README.md** - Comprehensive guide (see separate file)
2. **API Documentation** - OpenAPI/Swagger or simple markdown
3. **Architecture Diagram** - Visual flow diagram
4. **Examples** - Multiple use cases
5. **Contributing Guide** - How to contribute
6. **License** - MIT recommended

## 🚀 Key Features to Highlight

1. **Simplified Architecture** - 82-line handler vs 700+ line alternatives
2. **LangChain-Style Flow** - Familiar pattern for developers
3. **Production-Ready** - Rate limiting, circuit breakers, error handling
4. **Streaming Support** - Real-time response streaming
5. **Embedding Reranking** - Semantic relevance scoring
6. **Query Optimization** - LLM-powered query generation
7. **Document Summarization** - Cost-effective long document handling

## ⚠️ Abstraction Needed

1. **Search Provider** - Abstract search interface (currently hardcoded to SerpAPI)
2. **LLM Provider** - Abstract LLM interface (currently OpenAI only)
3. **Storage** - Abstract storage interface (currently Redis/Memory)

## 🎨 Naming Suggestions

- `agentic-framework`
- `perplexity-agent`
- `langchain-simple`
- `query-agent-framework`

## 📊 File Count Estimate

- **Core Files**: ~15-20 files
- **Total Lines**: ~3,000-4,000 lines
- **Dependencies**: ~10-15 npm packages
- **Size**: Small, focused, maintainable

## ✅ Next Steps

1. Create extraction script (update existing one)
2. Remove app-specific code
3. Add abstraction interfaces
4. Write comprehensive README
5. Add examples
6. Set up CI/CD
7. Create GitHub repository
8. Add tests
9. Publish to npm (optional)

