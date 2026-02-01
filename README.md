# Clonar 🔍

An **agentic query pipeline** that turns natural-language questions into structured, citation-backed answers. It uses query understanding, multi-vertical orchestration, hybrid retrieval (BM25 + dense), and citation-first synthesis. Unlike single-pass search UIs, Clonar decomposes mixed queries (e.g. “flights to NYC and hotels near the airport”), runs verticals in parallel, reorders by retrieval quality, and can replan in Deep mode when the answer is for the wrong question.

**This repository** contains the **agentic framework**: the backend query pipeline (query understanding, orchestration, vertical agents, retrieval, synthesis). It does **not** include the full product surface or the Flutter client; those are separate. You get the core that turns a message + history + mode into a plan, runs the right verticals, merges results, and returns summary, cards, citations, and UI hints.

---

## What's in this repo

- **Query understanding** (`node/src/services/query-understanding.ts`) — Rewrite, decompose, vertical classification, intent, **ordered preferences**, **soft constraints** (e.g. airport not pinned until results), filters.
- **Orchestrator** (`node/src/services/orchestrator.ts`) — Plan cache, vertical selection, parallel run, merge, **adaptive primary by retrieval quality**, **cross-part conflict** detection (e.g. JFK vs LGA), **fallback reframe** when structured results are thin, **Deep replan** when critique signals wrong domain.
- **Vertical agents** (`node/src/services/vertical/`) — Product, hotel, flight, movie, and **other** (web overview, e.g. Perplexity). Each does retrieval (hybrid BM25 + dense + rerank), dedup, summarization with **citation-first** instructions and dual memory (working memory vs retrieved content).
- **API** — `POST /api/query` (JSON in/out) and `GET /api/query/stream` (SSE) with `message`, `history`, `mode` (quick | deep).

---

## Architecture

**1. Query understanding (plan only, no search yet)**  
The pipeline rewrites the message (resolve “there”, “this weekend”, same-query refs like “the airport” → “NYC airport”), decomposes into parts (e.g. flight + hotel), assigns verticals (product, hotel, flight, movie, other), intent, and **ordered preferences**. It fills structured filters per vertical and marks **soft constraints** (e.g. “airport” unspecified) so downstream can align after retrieval. Output: a **plan** (what to look for). Plan is cached by message+history.

**2. Orchestration**  
The orchestrator selects which verticals to run from the plan’s candidates, builds a per-vertical plan, and runs **all selected verticals in parallel**. It then reorders by **retrieval quality** (e.g. top-K snippet average), merges summaries and cards, and combines citations. It **checks cross-part conflicts** (e.g. flight into JFK vs hotel area LaGuardia) and attaches a hint when they don’t align. If structured results are weak, it **adds a web overview** with a **reframe** (“We found few structured options. You might relax X. Here’s a broader view from the web:”) and **relaxation hint** using the lowest-priority preference.

**3. Vertical agents**  
Each vertical (product, hotel, flight, movie) derives search queries from the plan, runs **hybrid retrieval** (BM25 + dense, then LLM rerank), dedupes, merges snippets, and runs **one** summarizer. Summarizer prompts use **dual memory**: “Working memory (conversation context)” for intent/preferences only; “Retrieved content” as numbered passages; **every factual claim must cite** [1], [2], etc. The **other** vertical uses a web overview (e.g. Perplexity) for time-sensitive questions and returns summary + citations when the API provides them.

**4. Deep mode**  
When `mode` is **deep**, the pipeline can: run a planner (extra research?), alternate query phrasings for more retrieval angles, and a **critique** step. If the critique decides the answer is for the **wrong** question (with sufficient confidence), the pipeline **replans**: it runs query understanding again with the suggested query, then runs the pipeline with the new plan and **replaces** the answer (`suggestedQueryUsed: true`). Otherwise the suggested query is shown as a hint only.

---

## Modes and features

| Mode   | Behavior |
|--------|----------|
| **Quick** | Single pass: plan → run verticals → merge → payload. Result is cached by message+history+mode. |
| **Deep**  | Extra planner, alternate rewrites, extra research, critique; optionally **replan** with suggested query. |

**Verticals:** product, hotel, flight, movie, **other** (web overview for weather, things to do, general questions).

**Pipeline behaviors (newer):**  
- **Soft constraints** — e.g. “airport” kept unspecified until results so flight/hotel can align (e.g. hotels near JFK when flights are JFK).  
- **Preference priority** — Ordered preferences (e.g. price > location > wifi); when results are thin, fallback suggests relaxing the **lowest-priority** first.  
- **Cross-part conflict** — If flight results are JFK and hotel results are LaGuardia, the response includes a hint and suggestion (e.g. “Want hotels near JFK to match your flight?”).  
- **Fallback reframe** — When appending a web overview, the server explains why and optionally suggests which preference to relax.  
- **Deep replan** — When critique says “wrong domain,” the pipeline can replan and replace the answer with one from the suggested query.

---

## Project structure (agentic framework)

```
node/
├── src/
│   ├── routes/
│   │   └── query.ts          # POST /api/query, GET /api/query/stream
│   ├── services/
│   │   ├── query-understanding.ts   # Plan: rewrite, decompose, classify, filters, preferencePriority, softConstraints
│   │   ├── orchestrator.ts          # Run verticals, merge, quality reorder, fallback, crossPartHint, Deep replan
│   │   ├── orchestrator-stream.ts   # SSE streaming wrapper
│   │   ├── critique-agent.ts        # Deep: refine summary, optional needsReplan + suggestedQuery
│   │   ├── planner-agent.ts         # Deep: extra research?
│   │   ├── vertical/
│   │   │   ├── product-agent.ts
│   │   │   ├── hotel-agent.ts
│   │   │   ├── flight-agent.ts
│   │   │   └── movie-agent.ts
│   │   └── providers/
│   │       ├── catalog/      # Product: hybrid retriever, SQL provider
│   │       ├── hotels/       # Hotel: hybrid retriever, SQL provider
│   │       ├── flights/      # Flight: hybrid retriever, SQL provider
│   │       ├── movies/       # Movie: hybrid retriever, SQL provider
│   │       └── web/
│   │           └── perplexity-web.ts   # Other: web overview + citations
│   ├── types/
│   │   ├── core.ts           # QueryContext, PlanCandidate, VerticalPlan, etc.
│   │   └── verticals.ts      # Filters per vertical
│   └── ...
├── package.json
└── ...
docs/
├── QUERY_FLOW_STORY.md       # End-to-end flow in plain language (query → UI)
├── PERPLEXITY_FLOW_GAP_ANALYSIS.md
└── PIPELINE_VS_PERPLEXITY.md
```

The **Flutter client** (screens, widgets, state) is not part of this release; this repo is the agentic backend pipeline only.

---

## API

### POST /api/query

Request body:

```json
{
  "message": "Flights to NYC and hotels near the airport",
  "history": ["I'm thinking next month"],
  "mode": "quick",
  "userId": "optional"
}
```

Response: JSON with `summary`, `definitionBlurb`, `referencesSection`, `citations`, `vertical`, `products` | `hotels` | `flights` | `showtimes`, `ui`, `followUpSuggestions`, `suggestedQuery`, `suggestedQueryUsed`, `crossPartHint` (when flight+hotel airports differ), `semanticFraming`, `answerGeneratedAt`, `debug`, etc.

### GET /api/query/stream

Query params: `message`, `history` (JSON array), `mode`, `userId` (optional).

Response: Server-Sent Events — `token` (chunks), `citations`, `done` (full payload), `error`.

---

## Installation (backend)

**Prerequisites:** Node.js 18+, npm.

1. Clone and install:

   ```bash
   git clone <repository-url>
   cd clonar/node
   npm install
   ```

2. Environment (e.g. `.env` in `node/`):

   ```env
   OPENAI_API_KEY=your_key
   PERPLEXITY_API_KEY=optional_for_other_vertical
   PORT=4000
   ```

3. Run:

   ```bash
   npm run dev
   ```

   API: `http://localhost:4000`. Use `POST /api/query` or `GET /api/query/stream` with `message`, `history`, `mode`.

---



---

## Contributing

Contributions are welcome. For large changes, open an issue first.

---

## License

See LICENSE file.
