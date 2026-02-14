# Clonar: 🚀 An 8-Stage Agentic RAG Orchestrator for High-Precision Reasoning

This repository open-sources Clonar, a production-ready RAG (Retrieval-Augmented Generation) query pipeline designed to move beyond "naive RAG" with explicit multihop reasoning. From a user question to a grounded answer with citations, Clonar's Node.js backend implements an intelligent, iterative flow that redefines accuracy in AI-powered search.

**The Problem:** Most RAG systems are "one-shot," performing a single retrieval and synthesis pass, leading to hallucinations and insufficient answers for complex queries.

**The Solution:** Clonar introduces an 8-stage agentic workflow that reasons before it retrieves, clarifies when necessary, and critiques its own output to ensure high-fidelity, grounded responses.

You do not need any frontend to use it. Run the Node backend and call the API with any HTTP client (curl, Postman, or your own app).

---

## 🎯 Key Architectural Highlights for Extraordinary Reasoning

Clonar's core innovation is its **8-Stage Reasoning Loop**. This isn't a simple concatenation of steps, but a dynamically conditioning, iterative process. Key mechanisms:

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
- **Backend:** Node.js service that implements the flow. Entry points: **POST /api/query** (single JSON) and **GET /api/query/stream** (SSE: token → citations → done).

## Files involved (query flow only)

Only the following files are part of the supported query-flow release. Everything else in the repo is either optional or for other features.

### Core query flow

| Layer | Files |
|-------|--------|
| **Entry** | `src/main/node/routes/query.ts` — POST / and GET /stream, buildPipelineContext, getSession, getUserMemory, runPipeline / runPipelineStream |
| **Orchestration** | `src/main/node/services/orchestrator.ts`, `orchestrator-stream.ts` |
| **Rewrite & filters** | `query-rewrite.ts`, `filter-extraction.ts` |
| **Grounding & plan** | `node/src/services/grounding-decision.ts`, `node/src/services/retrieval-plan.ts`, `node/src/services/retrieval-plan-executor.ts` |
| **Retrieval** | `retrieval-router.ts`, `pipeline-deps.ts` |
| **LLM & synthesis** | `node/src/services/llm-main.ts`, `node/src/services/llm-small.ts` |
| **Deep mode** | Inline in orchestrator: critique via callSmallLLM; if insufficient, run 7-stage again with expanded prompt |
| **Session & memory** | `src/main/node/services/session/sessionMemory.ts`, `userMemory.ts` |
| **Observability** | `node/src/services/query-processing-trace.ts`, `node/src/services/query-processing-metrics.ts`, `node/src/services/eval-sampling.ts`, `node/src/services/eval-automated.ts` |
| **Web retrieval** | `src/main/node/services/providers/web/perplexity-web.ts` |
| **Routing & utils** | `node/src/services/cache.ts`, `node/src/services/rerank.ts`, `node/src/services/passage-reranker.ts`, `node/src/services/safe-parse-json.ts` |
| **UI hints (backend)** | `ui-intent.ts`, `ui_decision/*`

### Supported files (needed to run the flow)

| Purpose | Files |
|---------|--------|
| **Types** | `src/main/node/types/core.ts`, `verticals.ts`, `index.ts` |
| **Session store** | `src/main/node/services/session/SessionStore.ts`, `InMemorySessionStore.ts`, `RedisSessionStore.ts` |
| **Infra** | `src/main/node/utils/logger.ts`, `services/cache.ts` (incl. initRedis if Redis used) |
| **Pipeline deps** | `services/pipeline-deps.ts` — builds retrievers; see providers below |
| **Providers (retrieval)** | `src/main/node/services/providers/` — `retrieval-types.ts`, `retrieval-vector-utils.ts` |
| **Reranker** | `passage-reranker.ts` (optional) |
| **Server entry** | `src/main/node/index.ts` — health + /api/query |

Optional: `metrics-aggregator.ts`, other eval/observability modules.

---

## Clone and run (backend only)

No Flutter or other frontend is required. Use the backend and call the API.

### Prerequisites

- Node.js 18+
- Optional: Redis (for shared session cache), PostgreSQL (for SQL-backed retrievers)

### 1. Clone and install

Run from the **repository root** (backend lives under `src/main/node/`):

```bash
git clone <repository-url>
cd clonar
npm install
```

### 2. Environment

Copy `.env.example` to `.env` in the repo root and set your keys:

```bash
cp .env.example .env
```

Edit `.env`: set `OPENAI_API_KEY`, `PERPLEXITY_API_KEY`; optionally `REDIS_URL`, `SERP_API_KEY`, `GOOGLE_MAPS_API_KEY`.

### 3. Start the server

From the repo root:

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

## Project layout (required structure)

The backend follows this layout under the repo root. Run from the root with `npm run dev`; `tsconfig` and scripts use `src/main/node` as the Node app.

```
<repo>/
├── src/
│   └── main/
│       └── node/
│           ├── config/          # app, redis, database config
│           ├── controllers/     # business logic (stubs)
│           ├── middlewares/     # auth, validation, error
│           ├── models/          # data models (stubs)
│           ├── routes/          # query.ts, index
│           ├── services/        # orchestrator, retrieval, session, providers
│           │   ├── session/     # SessionStore, sessionMemory, userMemory
│           │   └── providers/   # web, weather, catalog, hotels, flights, movies
│           ├── types/           # core, verticals, index
│           ├── utils/           # logger, helpers
│           ├── resources/       # database migrations/seeds, static
│           └── index.ts         # entry point
├── .env.example
├── package.json                 # scripts run src/main/node/index.ts
├── tsconfig.json                # rootDir: src/main/node, paths @/* → src/main/node/*
└── README.md
```

Query flow files: `routes/query.ts`, `services/orchestrator*.ts`, `services/query-rewrite.ts`, `services/filter-extraction.ts`, `services/grounding-decision.ts`, `services/retrieval-plan*.ts`, `services/retrieval-router.ts`, `services/pipeline-deps.ts`, `services/llm-*.ts`, `services/session/*`, `services/providers/*`, `utils/logger.ts`, `types/*`.

---

## License

This project is open source. See the LICENSE file for details.
