# RAG Query Flow — Open-Source Architecture

This repository open-sources the **RAG (retrieval-augmented generation) query pipeline**: from a user question to a grounded answer with citations. The design is **Perplexity-style**: rewrite → extract filters → grounding decision → decompose → route by content → search in parallel → merge, dedupe, rerank → synthesize once.

**You do not need any frontend to use it.** The pipeline is fully specified by **[docs/QUERY_FLOW_STORY.md](docs/QUERY_FLOW_STORY.md)**. Run the Node backend and call the API with any HTTP client (curl, Postman, or your own app).

---

## What’s in this release

- **Single source of truth:** [docs/QUERY_FLOW_STORY.md](docs/QUERY_FLOW_STORY.md) — step-by-step flow with real file names and responsibilities. No extra “frontend” doc; that story is the spec.
- **Backend:** Node.js service that implements the flow. Entry points: **POST /api/query** (single JSON) and **GET /api/query/stream** (SSE: token → citations → done).

---

## Files involved (query flow only)

Only the following files are part of the supported query-flow release. Everything else in the repo is either optional or for other features.

### Core query flow (from [QUERY_FLOW_STORY.md](docs/QUERY_FLOW_STORY.md))

| Layer | Files |
|-------|--------|
| **Entry** | `node/src/routes/query.ts` — POST / and GET /stream, buildPipelineContext, getSession, getUserMemory, runPipeline / runPipelineStream |
| **Orchestration** | `node/src/services/orchestrator.ts`, `node/src/services/orchestrator-stream.ts` |
| **Rewrite & filters** | `node/src/services/query-rewrite.ts`, `node/src/services/filter-extraction.ts` |
| **Grounding & decompose** | `node/src/services/grounding-decision.ts`, `node/src/services/query-understanding.ts`, `node/src/services/query-decomposition.ts` |
| **Retrieval** | `node/src/services/retrieval-router.ts`, `node/src/services/pipeline-deps.ts` |
| **LLM & synthesis** | `node/src/services/llm-main.ts`, `node/src/services/llm-small.ts` |
| **Deep mode** | `node/src/services/planner-agent.ts`, `node/src/services/critique-agent.ts` |
| **Session & memory** | `node/src/memory/sessionMemory.ts`, `node/src/memory/userMemory.ts` |
| **Observability** | `node/src/services/query-processing-trace.ts`, `node/src/services/query-processing-metrics.ts`, `node/src/services/eval-sampling.ts`, `node/src/services/eval-automated.ts` |
| **Web retrieval** | `node/src/services/providers/web/perplexity-web.ts` |
| **Routing utils** | `node/src/services/providers/retrieval-vector-utils.ts`, `node/src/services/cache.ts` |
| **UI hints (backend)** | `node/src/services/ui_decision/*` — genericUiDecision, productUiDecision, hotelUiDecision, movieUiDecision, flightUiDecision |
| **Vertical agents (deep)** | `node/src/services/vertical/product-agent.ts`, `hotel-agent.ts`, `flight-agent.ts`, `movie-agent.ts` |

### Supported files (needed to run the flow)

| Purpose | Files |
|--------|--------|
| **Types** | `node/src/types/core.ts`, `node/src/types/verticals.ts`, `node/src/types/index.ts` |
| **Session store** | `node/src/memory/SessionStore.ts`, `node/src/memory/InMemorySessionStore.ts`, `node/src/memory/RedisSessionStore.ts` |
| **Infra** | `node/src/services/logger.ts`, `node/src/services/cache.ts` (incl. initRedis if Redis used) |
| **Pipeline deps** | `node/src/services/pipeline-deps.ts` — builds retrievers; see below for provider files |
| **Providers (retrieval)** | `node/src/services/providers/catalog/` (catalog-provider, product-retriever, product-retriever-hybrid, sql-catalog), `hotels/` (hotel-provider, hotel-retriever, hotel-retriever-hybrid, sql-hotel), `flights/` (same pattern), `movies/` (same pattern), `web/simple-embedder.ts` |
| **Reranker** | `node/src/services/passage-reranker.ts` (optional; used when pipeline-deps supplies it) |
| **Server entry** | `node/src/index.ts` — mounts `/api/query` and other routes; for a minimal run you need at least health + query route + their middleware/deps |

Optional for evals/observability: `eval-alerting.ts`, `metrics-aggregator.ts`, `human-review-labels.ts`. Optional for MCP: `node/src/mcp/*` (retrievers/servers) when `USE_MCP_RETRIEVERS=1`.

---

## Clone and run (backend only)

No Flutter or other frontend is required. Use the backend and call the API.

### Prerequisites

- Node.js 18+
- Optional: Redis (for shared session cache), PostgreSQL (for SQL-backed retrievers)

### 1. Clone and install

```bash
git clone <repository-url>
cd clonar/node
npm install
```

### 2. Environment

Create `node/.env`:

```env
PORT=4000
NODE_ENV=development
OPENAI_API_KEY=your_openai_key
PERPLEXITY_API_KEY=your_perplexity_key
# Optional: REDIS_URL, DATABASE_URL (or SQLite/pg for catalog/hotel/flight/movie SQL providers)
```

### 3. Start the server

```bash
npm run dev
```

- Health: [http://localhost:4000/health](http://localhost:4000/health)
- Query API: [http://localhost:4000/api/query](http://localhost:4000/api/query)

### 4. Call the API (no frontend)

**Single response (POST):**

```bash
curl -X POST http://localhost:4000/api/query \
  -H "Content-Type: application/json" \
  -d '{"message": "boutique hotels near Boston with good workspaces", "history": [], "mode": "quick"}'
```

**Streaming (GET):**

```bash
curl -N "http://localhost:4000/api/query/stream?message=boutique%20hotels%20near%20Boston&mode=quick&history=%5B%5D"
```

Response shape (POST or `done` event): `summary`, `citations`, `vertical`, `hotels`|`products`|`flights`|`showtimes`, `debug` (trace, routing, searchQueries), `followUpSuggestions`, etc. — as in [QUERY_FLOW_STORY.md](docs/QUERY_FLOW_STORY.md) Step 10.

---

## Flow in one sentence

The server loads session (conversation thread, last-used filters, user memory), **rewrites** the query, **extracts filters**, **decides** whether retrieval is needed; if yes, **decomposes** into sub-queries, **routes** each by content (keyword + similarity, optional confidence-based narrowing), runs **retrievers in parallel**, **merges, dedupes, reranks**, **synthesizes** one answer from retrieved chunks, then returns JSON or SSE. Full step-by-step: **[docs/QUERY_FLOW_STORY.md](docs/QUERY_FLOW_STORY.md)**.

---

## Project layout (query-flow + supported only)

```
<repo>/
├── docs/
│   └── QUERY_FLOW_STORY.md          # The only “frontend” — full flow spec
├── node/
│   ├── src/
│   │   ├── routes/
│   │   │   └── query.ts
│   │   ├── services/
│   │   │   ├── orchestrator.ts
│   │   │   ├── orchestrator-stream.ts
│   │   │   ├── query-rewrite.ts
│   │   │   ├── filter-extraction.ts
│   │   │   ├── grounding-decision.ts
│   │   │   ├── query-understanding.ts
│   │   │   ├── query-decomposition.ts
│   │   │   ├── retrieval-router.ts
│   │   │   ├── pipeline-deps.ts
│   │   │   ├── cache.ts
│   │   │   ├── llm-main.ts
│   │   │   ├── llm-small.ts
│   │   │   ├── planner-agent.ts
│   │   │   ├── critique-agent.ts
│   │   │   ├── passage-reranker.ts
│   │   │   ├── query-processing-trace.ts
│   │   │   ├── query-processing-metrics.ts
│   │   │   ├── eval-sampling.ts
│   │   │   ├── eval-automated.ts
│   │   │   ├── logger.ts
│   │   │   ├── ui_decision/
│   │   │   ├── vertical/
│   │   │   └── providers/
│   │   │       ├── catalog/   (provider, retriever, retriever-hybrid, sql-catalog)
│   │   │       ├── hotels/    (same pattern)
│   │   │       ├── flights/  (same pattern)
│   │   │       ├── movies/   (same pattern)
│   │   │       ├── web/      (perplexity-web, simple-embedder)
│   │   │       ├── retrieval-vector-utils.ts
│   │   │       └── retrieval-types.ts
│   │   ├── memory/
│   │   │   ├── sessionMemory.ts
│   │   │   ├── userMemory.ts
│   │   │   ├── SessionStore.ts
│   │   │   ├── InMemorySessionStore.ts
│   │   │   └── RedisSessionStore.ts
│   │   ├── types/
│   │   │   ├── core.ts
│   │   │   ├── verticals.ts
│   │   │   └── index.ts
│   │   └── index.ts
│   ├── package.json
│   └── tsconfig.json
└── README.md
```

Other directories (e.g. `lib/` Flutter app, other routes) are not required for the open-source RAG flow; the story and the files above are sufficient to clone and run.

---

## License

This project is open source. See the LICENSE file for details.
