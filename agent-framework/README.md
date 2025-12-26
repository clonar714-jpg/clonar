# Agentic Framework

A production-ready, simplified agentic framework for building AI-powered query processing systems. Inspired by LangChain's MetaSearchAgent but with a cleaner, more maintainable architecture.

> **New to programming?** Check out [SIMPLE_GUIDE.md](./SIMPLE_GUIDE.md) for step-by-step instructions in plain language!

## ✨ Features

- **🚀 Simplified Architecture** - Clean 82-line handler vs 700+ line alternatives
- **🔍 LangChain-Style Flow** - Familiar pattern: Query → Search → Summarize → Rerank → Answer
- **📡 Streaming Support** - Real-time Server-Sent Events (SSE) streaming
- **🎯 Query Optimization** - LLM-powered query generation for better search results
- **📄 Document Summarization** - Cost-effective handling of long documents (80% cost savings)
- **🔢 Embedding Reranking** - Semantic relevance scoring using OpenAI embeddings
- **🛡️ Production-Ready** - Rate limiting, circuit breakers, error handling, memory management
- **💾 Flexible Memory** - In-memory or Redis session storage
- **📦 TypeScript** - Fully typed for better developer experience

## 🏗️ Architecture

```
User Query
  ↓
agent.handler.simple.ts (82 lines)
  ↓
perplexityAnswer.ts
  ├─→ Query Generation (queryGenerator.ts)
  ├─→ Web Search (SerpAPI or custom provider)
  ├─→ Link Retrieval (fetchDocumentFromUrl)
  ├─→ Document Summarization (documentSummarizer.ts)
  ├─→ Embedding Reranking (embeddingClient.ts)
  ├─→ Answer Generation (LLM)
  ├─→ Answer Parsing (answerParser.ts)
  └─→ Streaming (SSE)
  ↓
Response (sections + sources + follow-ups)
```

## 📦 Installation

### For Developers

```bash
npm install
```

### For Non-Technical Users

If you're not familiar with programming, please see [SIMPLE_GUIDE.md](./SIMPLE_GUIDE.md) for detailed, step-by-step instructions in simple language.

## ⚙️ Configuration

1. Copy `.env.example` to `.env`:

```bash
cp .env.example .env
```

2. Configure your environment variables:

```env
# Required
OPENAI_API_KEY=your_openai_api_key_here

# Optional
PORT=4000
NODE_ENV=development
CORS_ORIGIN=http://localhost:3000
REDIS_URL=redis://localhost:6379
SESSION_STORAGE_TYPE=memory
```

## 🚀 Quick Start

### Basic Usage

```typescript
import express from 'express';
import agentRoutes from './routes/agent';

const app = express();
app.use(express.json());
app.use('/api/agent', agentRoutes);

app.listen(4000, () => {
  console.log('Server running on http://localhost:4000');
});
```

### Making a Request

```bash
curl -X POST http://localhost:4000/api/agent \
  -H "Content-Type: application/json" \
  -d '{
    "query": "What are the best running shoes for marathon training?",
    "stream": false
  }'
```

### Streaming Request

```bash
curl -X POST "http://localhost:4000/api/agent?stream=true" \
  -H "Content-Type: application/json" \
  -d '{
    "query": "Explain quantum computing",
    "stream": true
  }'
```

## 📚 API Reference

### POST `/api/agent`

Process a query and return an AI-generated answer.

#### Request Body

```typescript
{
  query: string;                    // User's query
  conversationHistory?: Array<{     // Optional conversation context
    query: string;
    summary: string;
  }>;
  stream?: boolean;                 // Enable streaming (default: true)
}
```

#### Response (Non-Streaming)

```typescript
{
  success: true;
  intent: "answer";
  summary: string;                  // Brief summary
  answer: string;                   // Full answer text
  sections: Array<{                 // Structured sections
    title: string;
    content: string;
  }>;
  sources: Array<{                  // Source citations
    title: string;
    url: string;
  }>;
  followUpSuggestions: string[];    // Suggested follow-up questions
}
```

#### Response (Streaming)

Streams Server-Sent Events (SSE) with the following format:

```
data: {"type": "chunk", "content": "partial text"}
data: {"type": "done", "result": {...}}
```

## 🔧 Core Components

### 1. Agent Handler (`agent/agent.handler.simple.ts`)

The main entry point - a clean, 82-line handler that orchestrates the entire flow.

```typescript
import { handleAgentRequestSimple } from './agent/agent.handler.simple';

// Use in your Express route
router.post('/', handleAgentRequestSimple);
```

### 2. Perplexity Answer Service (`services/perplexityAnswer.ts`)

The core service implementing the LangChain-style flow:

- Query generation
- Web search
- Document retrieval
- Summarization
- Embedding reranking
- Answer generation
- Streaming support

### 3. Query Generator (`services/queryGenerator.ts`)

Optimizes user queries using LLM for better search results.

```typescript
import { generateSearchQuery } from './services/queryGenerator';

const optimizedQuery = await generateSearchQuery(
  "best running shoes",
  conversationHistory
);
```

### 4. Document Summarizer (`services/documentSummarizer.ts`)

Summarizes long documents to reduce token usage and improve quality.

```typescript
import { summarizeDocument } from './services/documentSummarizer';

const summary = await summarizeDocument(
  longDocumentContent,
  userQuery
);
```

### 5. Answer Parser (`services/answerParser.ts`)

Parses LLM responses into structured sections and metadata.

```typescript
import { parseStructuredAnswer } from './services/answerParser';

const parsed = parseStructuredAnswer(llmResponse);
// Returns: { answer, summary, sections, followUpSuggestions }
```

### 6. Embedding Client (`embeddings/embeddingClient.ts`)

Generates embeddings and calculates cosine similarity for reranking.

```typescript
import { getEmbedding, cosine } from './embeddings/embeddingClient';

const embedding = await getEmbedding("text");
const similarity = cosine(embedding1, embedding2);
```

## 🛡️ Stability Features

### Rate Limiting

```typescript
import { agentRateLimiter } from './stability/rateLimiter';

app.use('/api/agent', agentRateLimiter);
```

### Circuit Breaker

```typescript
import { agentCircuitBreaker } from './stability/circuitBreaker';

const result = await agentCircuitBreaker.execute(() => {
  return processQuery(query);
});
```

### Error Handling

Global error handlers are automatically set up for:
- Unhandled promise rejections
- Uncaught exceptions
- Graceful shutdown

## 💾 Memory Management

### In-Memory Storage (Default)

```typescript
import { InMemorySessionStore } from './memory/InMemorySessionStore';

const store = new InMemorySessionStore();
```

### Redis Storage

```typescript
import { RedisSessionStore } from './memory/RedisSessionStore';

const store = new RedisSessionStore({
  url: process.env.REDIS_URL
});
```

## 🔌 Customization

### Custom Search Provider

The framework uses SerpAPI by default, but you can implement a custom search provider:

```typescript
interface SearchProvider {
  search(query: string): Promise<SearchResult[]>;
}

// Implement your provider and pass it to perplexityAnswer
```

### Custom LLM Provider

Currently uses OpenAI, but can be extended to support other providers:

```typescript
interface LLMProvider {
  chat(messages: Message[]): Promise<string>;
  embed(text: string): Promise<number[]>;
}
```

## 📊 Performance

- **Query Processing**: ~2-5 seconds (depending on query complexity)
- **Streaming Latency**: <100ms first token
- **Token Efficiency**: 80% reduction with document summarization
- **Memory Usage**: ~50-100MB (in-memory mode)

## 🧪 Testing

```bash
npm test
```

## 📝 Examples

See the `examples/` directory for:
- Basic integration
- Streaming implementation
- Custom provider integration
- Memory management
- Error handling

## 🤝 Contributing

Contributions are welcome! Please read our contributing guidelines first.

## 📄 License

MIT License - see LICENSE file for details

## 🙏 Acknowledgments

- Inspired by LangChain's MetaSearchAgent
- Built with OpenAI's GPT models
- Uses SerpAPI for web search

## 📞 Support

- GitHub Issues: [Report bugs or request features]
- Documentation: [Link to full docs]
- Discussions: [Community discussions]

## 🗺️ Roadmap

- [ ] Support for multiple LLM providers (Anthropic, Cohere, etc.)
- [ ] Plugin system for custom search providers
- [ ] GraphQL API support
- [ ] WebSocket streaming
- [ ] Advanced caching strategies
- [ ] Multi-language support

---

**Made with ❤️ for the open source community**

