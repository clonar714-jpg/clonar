# RAG Query Flow with Multihop Reasoning — Open-Source Architecture

This repository open-sources the RAG (retrieval-augmented generation) query pipeline: from a user question to a grounded answer with citations. The design is Perplexity-style and centers on **explicit multihop reasoning**—each step conditions on the outputs of prior steps, with optional iterative refinement when the system detects insufficient coverage.

You do not need any frontend to use it. The pipeline is fully specified by **docs/QUERY_FLOW_STORY.md**. Run the Node backend and call the API with any HTTP client (curl, Postman, or your own app).

---

## Multihop reasoning (design highlight)

The pipeline implements **structured multihop reasoning** rather than a single monolithic retrieval-and-synthesize pass. Each hop consumes the results of previous hops and decides the next action; the final answer is produced only after this chain completes. Key mechanisms:

| Hop / mechanism | What the system reasons over | Outcome |
|-----------------|------------------------------|---------|
| **1. Query rewrite** | Raw message + conversation thread + user memory | Normalized prompt; optional *needsClarification* (conflicts/underspecification). |
| **2. Clarification gate** | Rewrite output | If clarification needed → return questions and **stop** (no retrieval). Else continue. |
| **3. Filter extraction** | Rewritten prompt | Structured filters per vertical + preference context. |
| **4. Grounding decision** | Rewritten prompt + context | **none** \| **hybrid** \| **full** — whether to skip retrieval, use web-only, or run full 7-stage. |
| **5. Retrieval plan** (full path) | Rewritten prompt + extracted filters + session | **RetrievalPlan**: ordered steps (tool + args). Primary vertical and search strategy. |
| **6. Execute plan** | Plan + context | Chunks from multiple sources; executor fills defaults (e.g. dates/guests) when planner omitted them. |
| **7. Merge → quality → synthesize** | Chunks, scores, vertical | Dedupe, rerank, cap; **deriveRetrievalQuality**; **buildFormattingGuidance** from quality; single synthesis pass. |
| **8. Deep-mode refinement** (optional) | First-pass answer | **Critique** (sufficient vs insufficient). If insufficient → **second full 7-stage run** with expanded prompt; replace result. |
| **9. Post-retrieval** | Result quality + vertical | Optional weak fallback (append web overview); **deriveAnswerConfidence** → UI (showCards, answerConfidence); **buildDynamicFollowUps** from vertical, intent, filters, top results. |

**Why this is multihop:** The model does not perform one “retrieve everything then answer” step. It (1) **reasons** about whether to clarify, (2) **reasons** about which verticals and tools to use and in what order, (3) **executes** that plan, (4) **reasons** about retrieval quality and formatting, (5) **synthesizes** once from the chosen evidence, and optionally (6) **reasons** again in deep mode (critique → second retrieval hop). Session state (conversation thread, last filters, last successful vertical) feeds back into the next query, so **cross-turn multihop** is supported as well.



---

## What's in this release

- **Multihop reasoning pipeline:** Explicit chain of reasoning steps (rewrite → clarification gate → filter extraction → grounding → plan → execute → merge/quality → synthesize), with optional deep-mode critique and second retrieval pass. Each step conditions on prior outputs; no single-shot “retrieve-then-answer” black box.
- **Single source of truth:** **docs/QUERY_FLOW_STORY.md** — step-by-step flow with real file names and responsibilities. No extra “frontend” doc; that story is the spec.
- **Backend:** Node.js service that implements the flow. Entry points: **POST /api/query** (single JSON) and **GET /api/query/stream** (SSE: token → citations → done).

## Files involved (query flow only)

Only the following files are part of the supported query-flow release. Everything else in the repo is either optional or for other features.

### Core query flow

| Layer | Files |
|-------|--------|
| **Entry** | `node/src/routes/query.ts` — POST / and GET /stream, buildPipelineContext, getSession, getUserMemory, runPipeline / runPipelineStream |
| **Orchestration** | `node/src/services/orchestrator.ts`, `node/src/services/orchestrator-stream.ts` |
| **Rewrite & filters** | `node/src/services/query-rewrite.ts`, `node/src/services/filter-extraction.ts` |
| **Grounding & plan** | `node/src/services/grounding-decision.ts`, `node/src/services/retrieval-plan.ts`, `node/src/services/retrieval-plan-executor.ts` |
| **Retrieval** | `node/src/services/retrieval-router.ts`, `node/src/services/pipeline-deps.ts` |
| **LLM & synthesis** | `node/src/services/llm-main.ts`, `node/src/services/llm-small.ts` |
| **Deep mode** | Inline in orchestrator: critique via callSmallLLM; if insufficient, run 7-stage again with expanded prompt |
| **Session & memory** | `node/src/memory/sessionMemory.ts`, `node/src/memory/userMemory.ts` |
| **Observability** | `node/src/services/query-processing-trace.ts`, `node/src/services/query-processing-metrics.ts`, `node/src/services/eval-sampling.ts`, `node/src/services/eval-automated.ts` |
| **Web retrieval** | `node/src/services/providers/web/perplexity-web.ts` |
| **Routing & utils** | `node/src/services/cache.ts`, `node/src/services/rerank.ts`, `node/src/services/passage-reranker.ts`, `node/src/services/safe-parse-json.ts` |
| **UI hints (backend)** | `node/src/services/ui-intent.ts`, `node/src/services/ui_decision/*`

### Supported files (needed to run the flow)

| Purpose | Files |
|---------|--------|
| **Types** | `node/src/types/core.ts`, `node/src/types/verticals.ts`, `node/src/types/index.ts` |
| **Session store** | `node/src/memory/SessionStore.ts`, `node/src/memory/InMemorySessionStore.ts`, `node/src/memory/RedisSessionStore.ts` |
| **Infra** | `node/src/services/logger.ts`, `node/src/services/cache.ts` (incl. initRedis if Redis used) |
| **Pipeline deps** | `node/src/services/pipeline-deps.ts` — builds retrievers; see below for provider files |
| **Providers (retrieval)** | `node/src/services/providers/` — `retrieval-types.ts`, `retrieval-vector-utils.ts`|
| **Reranker** | `node/src/services/passage-reranker.ts` (optional; used when pipeline-deps supplies it) |
| **Server entry** | `node/src/index.ts` — mounts /api/query and other routes; for a minimal run you need at least health + query route + their middleware/deps |

Optional for evals/observability: `eval-alerting.ts`, `metrics-aggregator.ts`, `human-review-labels.ts`. Optional for MCP: `node/src/mcp/*` when enabled.

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

- **Health:** http://localhost:4000/health  
- **Query API:** http://localhost:4000/api/query  

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

**Response shape** (POST or done event): `summary`, `citations`, `verticals`, `debug` (trace, routing, searchQueries), `followUpSuggestions`, etc. — as described in **docs/QUERY_FLOW_STORY.md**.

---

## Flow in one sentence

The server loads **session** (conversation thread, last-used filters, lastSuccessfulVertical, lastResultStrength) and **user memory**, checks **pipeline cache** (return if hit), then **plan cache** (rewrite + filters + grounding, TTL 60s). On plan cache miss, a **multihop reasoning chain** runs: **rewrite** → if **needsClarification** return clarification (no retrieval); else **extract filters** → **grounding decision** (none | hybrid | full). **None** → LLM-only answer. **Hybrid** → Perplexity web overview + derive retrieval quality + synthesize. **Full** → **7-stage**: plan retrieval steps → execute → merge, dedupe, rerank → derive retrieval quality → build formatting guidance → synthesize. Optional **deep mode** (second reasoning hop): critique answer; if insufficient, run 7-stage once more with expanded prompt. Then: retrieval quality (with optional weak fallback to web), **attachUiDecision** (answer confidence, showCards), **buildDynamicFollowUps**, **updateSession**, cache, return. 

---

## Project layout (query-flow + supported only)

```
<repo>/
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
│   │   │   ├── retrieval-plan.ts
│   │   │   ├── retrieval-plan-executor.ts
│   │   │   ├── retrieval-router.ts
│   │   │   ├── pipeline-deps.ts
│   │   │   ├── cache.ts
│   │   │   ├── llm-main.ts
│   │   │   ├── llm-small.ts
│   │   │   ├── rerank.ts
│   │   │   ├── passage-reranker.ts
│   │   │   ├── safe-parse-json.ts
│   │   │   ├── ui-intent.ts
│   │   │   ├── query-processing-trace.ts
│   │   │   ├── query-processing-metrics.ts
│   │   │   ├── eval-sampling.ts
│   │   │   ├── eval-automated.ts
│   │   │   ├── logger.ts
│   │   │   ├── ui_decision   
│   │   │   └── providers
│   │   │       
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
