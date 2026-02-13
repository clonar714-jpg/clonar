# Query Flow: From Your Question to the Answer

This document describes **exactly** what happens when you ask a question in the app: which files run, in what order, and how data flows from the request to the final answer and cards.

**Example:** *"boutique hotels near Boston's convention center with good workspaces and close to restaurants"*

---

## One-Sentence Overview

The app sends **message** (and history, userId, sessionId, mode) to **POST /api/query**. The server builds **QueryContext** (session: conversation thread, last-used filters, lastSuccessfulVertical, lastResultStrength), checks **pipeline cache** (return if hit), then **plan cache** (key: message + history, TTL 60s). On plan cache **miss**: **rewrite** → if **needsClarification** return early with clarification payload (no retrieval); else **extract filters** → **grounding decision** (none | hybrid | full) → **set plan cache**. **None** → LLM-only answer. **Hybrid** → perplexityOverview only; **deriveRetrievalQuality** (citation/item count); synthesize with **formatting guidance** from derived confidence. **Full** → **7-stage**: plan → execute → merge → **deriveRetrievalQuality** (itemCount, citationCount, avgScore, topKAvg) → **buildFormattingGuidance** from that quality → synthesize → result with **retrievalStats.quality**. Optional **deep mode** (ctx.mode === 'deep'): critique answer; if insufficient, run 7-stage once more with expanded prompt. Then: **retrievalQuality** from result.retrievalStats ?? classifyRetrievalQuality; optional **weak fallback** (web overview when weak + vertical ≠ other); **attachUiDecision** (deriveAnswerConfidence → showCards/answerConfidence); **buildDynamicFollowUps** with vertical, intent, filter summary, top result names; **updateSession**; cache; return. **Debug** includes derived quality, answerConfidence, clarificationTriggered, deepRefined.

---

## Flow Diagram (High Level)

```
[App]  →  POST /api/query  →  [query.ts]  →  build context, load session (thread, last*Filters, lastSuccessfulVertical, lastResultStrength) & user memory
                ↓
        [orchestrator.runPipeline]  →  pipeline cache check (return if hit)
                ↓
        plan cache check (plan:${makePlanCacheKey(ctx)}, TTL 60s)
                ↓
        ┌─ cache HIT  →  use cached rewrittenPrompt, extractedFilters, grounding  →  skip to "grounding_mode?"
        │
        └─ cache MISS  →  rewrite
                            ↓
                          needsClarification?  →  YES  →  return clarification payload (summary, needsClarification, clarificationQuestions)
                            |                     attachUiDecision, updateSession(appendTurn), debug.clarificationTriggered  →  DONE
                            NO
                            ↓
                          extractFilters  →  grounding decision (LLM)  →  set plan cache
                            ↓
        grounding_mode?
         ├─ none   →  LLM-only answer  →  attachUiDecision  →  follow-ups  →  updateSession(appendTurn)  →  cache  →  return
         │
         ├─ hybrid →  perplexityOverview  →  deriveRetrievalQuality(itemCount, citationCount)
         │           →  buildFormattingGuidance(synthesisAnswerConfidence(quality))  →  synthesize
         │           →  result.retrievalStats.quality = derived  →  (join below at "post-retrieval")
         │
         └─ full   →  7-stage: planRetrievalSteps  →  executeRetrievalPlan  →  smartDedupeChunks  →  rerankChunks  →  cap 50
                        →  deriveRetrievalQuality(itemCount, citationCount, avgScore, topKAvg)
                        →  buildFormattingGuidance(synthesisAnswerConfidence(quality))  →  synthesize
                        →  result.retrievalStats = { quality, avgScore, topKAvg }
                        ↓
                     [optional] ctx.mode === 'deep': critique  →  if insufficient  →  run 7-stage again (expanded prompt)  →  debug.deepRefined = true
                        ↓
        post-retrieval:
          retrievalQuality = result.retrievalStats?.quality ?? classifyRetrievalQuality(...)
          optional upgrade: weak + 1–3 items + avgScore >= 0.7  →  good
          weak fallback? (vertical ≠ other)  →  append perplexityOverview, quality = 'fallback_other'
          attachUiDecision (deriveAnswerConfidence  →  showCards, answerConfidence)
          debug.retrieval.quality, debug.answerConfidence
          buildDynamicFollowUps(result, ctx, { primaryVertical, intent, filterSummary, topResultNames })
          updateSession(appendTurn, lastSuccessfulVertical, lastResultStrength)
          cache  →  return
```

---

## Stage 0: Request and Context

**What happens:** The app sends **POST** to `/api/query` with `message`, `history`, `userId`, `sessionId`, and optionally `mode`. The route validates the body, builds **QueryContext**, normalizes **mode** (`'deep'` or `'pro'` → `'deep'`, otherwise `'quick'`), loads **session state** (conversation thread, last-used filters per vertical, **lastSuccessfulVertical**, **lastResultStrength**), and when `userId` is present loads **user memory**. No rewrite or retrieval runs here—only context attachment. Pipeline then checks **pipeline cache** (by cacheKey from mode + message + history); on hit, returns cached result. A **GET /api/query/stream** endpoint exists with the same context building (plus optional **conversationThread** and **previousFeedback** from the feedback store for the stream path); it uses **runPipelineStream** for SSE delivery.

| File | Role |
|------|------|
| **`lib/screens/ShopScreen.dart`** | Search UI; user types and taps search; triggers API call with message. |
| **`lib/providers/agent_provider.dart`** | Exposes submit action; calls API client (POST /api/query or GET /api/query/stream). |
| **`lib/core/api_client.dart`** / **`lib/services/query_api_client.dart`** | Builds HTTP request: `POST` to `/api/query` with body `{ message, history, userId, sessionId, mode }`. |
| **`node/src/routes/query.ts`** | Reads body; **buildPipelineContext** validates and builds **QueryContext**. **getSession(sessionKey)** loads session; sets **ctx.conversationThread**, **ctx.lastHotelFilters**, **ctx.lastFlightFilters**, **ctx.lastMovieFilters**, **ctx.lastProductFilters**, **ctx.lastSuccessfulVertical**, **ctx.lastResultStrength**. **getUserMemory(userId)** sets **ctx.userMemory**. Calls **runPipeline(ctx, deps)**. |
| **`node/src/memory/sessionMemory.ts`** | **SessionState**: `conversationThread`, `last*Filters`, **lastSuccessfulVertical**, **lastResultStrength**. **getSession**, **updateSession**. |
| **`node/src/memory/userMemory.ts`** | **getUserMemory(userId)** for preferences/location. |
| **`node/src/types/core.ts`** | **QueryContext** (message, history, userId, sessionId, mode, conversationThread, last*Filters, lastSuccessfulVertical, lastResultStrength, userMemory, rewriteVariant, previousFeedback). |

**Result:** **ctx** is ready. Pipeline runs next.

---

## Stage 1: Plan Cache and Understand Phase

**What happens:** Pipeline computes **planCacheKey = plan:${makePlanCacheKey(ctx)}** (message + history hash). If **rewriteVariant !== 'none'**, it tries **getCache(planCacheKey)**. On **hit**: use cached **rewrittenPrompt**, **extractedFilters**, **groundingDecision**; add **plan_cache_hit** span; skip rewrite, filter extraction, and grounding. On **miss** (or rewriteVariant === 'none'): run the understand phase below; then when rewriteVariant !== 'none', **setCache(planCacheKey, { rewrittenPrompt, extractedFilters, groundingDecision }, 60)**.

### 1a. Rewrite (on plan cache miss)

Unless **ctx.rewriteVariant === 'none'**, **rewriteQuery(ctx)** runs. It calls a small LLM to normalize language (typos, follow-ups from **ctx.conversationThread** and **ctx.userMemory**). It returns **RewriteOnlyResult**: **rewrittenPrompt**, **confidence**, **rewriteAlternatives**, **conflicts**, **needsClarification**. If **needsClarification === true**, the pipeline **returns immediately** with a clarification payload: summary = "To give you a better answer, could you clarify: …", **needsClarification: true**, **clarificationQuestions: rewriteResult.conflicts ?? []**, **attachUiDecision**, **updateSession(appendTurn)**, **debug.clarificationTriggered: true**. No filter extraction, grounding, or retrieval run; response is not cached in pipeline cache.

| File | Role |
|------|------|
| **`node/src/services/orchestrator.ts`** | **runPipeline**: plan cache get/set; on miss: **rewriteQuery(ctx)**; if **rewriteResult.needsClarification** → build clarification result, attachUiDecision, updateSession, return (no cache). Else continue to filter extraction. |
| **`node/src/services/query-rewrite.ts`** | **rewriteQuery(ctx)** → **normalizeQuery(ctx)**. Returns **rewrittenPrompt**, **needsClarification**, **conflicts** when rewrite detects conflicts/underspecification. |
| **`node/src/services/query-processing-trace.ts`** | **createTrace**, **addSpan** (rewrite, plan_cache_hit). |

**Result:** **rewrittenPrompt** (or clarification early exit).

### 1b. Filter Extraction (on plan cache miss, after rewrite)

**extractFilters(ctx, rewrittenPrompt)** runs. LLM extracts **structured filters** per vertical (hotel, flight, product, movie) and **preferenceDescription**. Merge: minimal non-date defaults + session + extracted. **preferenceDescription** becomes **preferenceContext** for ranking only.

| File | Role |
|------|------|
| **`node/src/services/orchestrator.ts`** | Calls **extractFilters(ctx, rewrittenPrompt)**; **filter_extraction** span; **debug.extractedFilters** when any. |
| **`node/src/services/filter-extraction.ts`** | **extractFilters**: LLM extract + merge with session; **getHotelMergeDefaults** etc. (no date/guest injection here; executor fills later). |
| **`node/src/types/verticals.ts`** | **HotelFilters**, **FlightFilters**, **ProductFilters**, **MovieTicketFilters**; **ExtractedFilters**. |

**Result:** **extractedFilters** for planning.

### 1c. Grounding Decision (on plan cache miss)

**shouldUseGroundedRetrieval(ctx, rewrittenPrompt)** uses a small LLM to decide **grounding_mode**: **none** | **hybrid** | **full**. On timeout/parse failure, default is **full**.

| File | Role |
|------|------|
| **`node/src/services/orchestrator.ts`** | **grounding_decision** span; then **setCache(planCacheKey, { rewrittenPrompt, extractedFilters, groundingDecision: grounding }, 60)** when rewriteVariant !== 'none'. |
| **`node/src/services/grounding-decision.ts`** | **shouldUseGroundedRetrieval**: prompt + **callSmallLLM**; parses **grounding_mode** and **reason**. |

**Result:** **grounding** (none | hybrid | full). Plan cache is written so the next identical message+history can skip rewrite/filter/grounding.

---

## Stage 2: Branch by Grounding Mode

### 2a. grounding_mode === 'none'

LLM-only answer: **callMainLLM** with a general-knowledge system prompt and **rewrittenPrompt**. Result: **vertical: 'other'**, **intent: 'browse'**, **summary**. **attachUiDecision**; **buildDynamicFollowUps(result, ctx)** (no extra context); **updateSession(appendTurn)**; **setCache(cacheKey, finalPayload)**; return. No retrieval.

### 2b. grounding_mode === 'hybrid'

- **perplexityOverview(rewrittenPrompt)** → web citations.
- **deriveRetrievalQuality({ itemCount: citationCount, citationCount })** → **good** | **weak** | **fallback_other** (rules: citationCount 0 → fallback_other; itemCount >= 4 → good; else weak; optional downgrade when avgScore < 0.5 and itemCount <= 2).
- **buildFormattingGuidance** with **answerConfidence = synthesisAnswerConfidence(derivedQuality)** (strong | medium | weak).
- **callMainLLM(ROUTER_GROUNDING_SYSTEM, userContent)** with retrieved passages + formatting guidance → **summary**.
- **result** = vertical 'other', **retrievalStats.quality = derivedQuality** (no hardcoded 'good' or 'fallback_other').
- Then flow joins **post-retrieval** (weak fallback, attachUiDecision, follow-ups, session, cache).

### 2c. grounding_mode === 'full' — 7-Stage Retrieval

**run7StageRetrievalAndSynthesize(ctx, rewrittenPrompt, extractedFilters, deps)**:

1. **Plan:** **planRetrievalSteps(ctx, rewrittenPrompt, extractedFilters)** → **RetrievalPlan** (steps with tool + args). **getPlannedPrimaryVertical(steps)** from first step.
2. **Execute:** **executeRetrievalPlan(plan, ctx)** → chunks, **bySource** (hotel[], flight[], product[], movie[]), **searchQueries**, **primaryVertical**. Executor injects system defaults for dates/guests when planner omitted them.
3. **Merge:** **smartDedupeChunks** → **rerankChunks** → **capped = slice(0, 50)**. Build **citations**.
4. **Quality:** **avgScore** / **topKAvg** from capped chunk scores. **deriveRetrievalQuality({ itemCount, citationCount: capped.length, avgScore, topKAvg })** → **retrievalQuality**.
5. **Formatting:** **synthesisAnswerConfidence(retrievalQuality)** → **buildFormattingGuidance** (answerConfidence, itemCount, primaryVertical, comparableAttributes).
6. **Synthesize:** **callMainLLM(ROUTER_GROUNDING_SYSTEM, userContent)** with workingMemory + retrievedPassages + formattingGuidance → **summary**.
7. **Result:** **baseResult** + vertical-specific fields; **retrievalStats** = { vertical, itemCount, **quality: retrievalQuality**, avgScore, topKAvg }.

Return: **result**, **citations**, **searchQueries**, **primaryVertical**, **plannedPrimaryVertical**, **stepCount**. No hardcoded quality.

| File | Role |
|------|------|
| **`node/src/services/orchestrator.ts`** | **run7StageRetrievalAndSynthesize**; **deriveRetrievalQuality**, **synthesisAnswerConfidence**, **buildFormattingGuidance**; **runAutomatedEvals** → **debug.automatedEvalScores**. |
| **`node/src/services/retrieval-plan.ts`** | **planRetrievalSteps**; **getPlannedPrimaryVertical**. |
| **`node/src/services/retrieval-plan-executor.ts`** | **executeRetrievalPlan**; capability-client calls; system defaults. |
| **`node/src/services/retrieval-router.ts`** | **smartDedupeChunks**, **rerankChunks**; **RetrievedChunk**. |
| **`node/src/services/llm-main.ts`** | **callMainLLM**; **ROUTER_GROUNDING_SYSTEM**. |

---

## Stage 3: Optional Deep Mode (full path only)

When **ctx.mode === 'deep'** and **grounding.grounding_mode === 'full'**:

- **Critique:** Small LLM asked whether the current answer is "sufficient" or "insufficient" (coverage weak/incomplete).
- If **insufficient:** **expandedPrompt** = rewrittenPrompt + (rewrittenPrompt.includes('?') ? " Include more specific options and details." : ""); **run7StageRetrievalAndSynthesize** runs **once more**; result, citations, effectivePlannedVertical, effectiveUiIntent, routingInfo, primaryVertical are replaced; **debug.deepRefined = true**; **addSpan(trace, 'deep_refinement', …)**.

Max one extra retrieval pass. Default (mode !== 'deep') unchanged.

---

## Stage 4: Post-Retrieval (hybrid + full)

**What happens:** Single path for both hybrid and full.

1. **Retrieval quality:** **retrievalQuality = result.retrievalStats?.quality ?? classifyRetrievalQuality(baseItemsCount, maxItemsHint)**. Optional upgrade: if retrievalQuality === 'weak' and 1 ≤ baseItemsCount ≤ 3 and avgScore >= 0.7 → set retrievalQuality = 'good'.
2. **Weak fallback:** If **retrievalQuality === 'weak'** and **result.vertical !== 'other'**, append **perplexityOverview(rewrittenPrompt)** to summary, set result vertical to 'other', merge citations, **retrievalStats.quality = 'fallback_other'**.
3. **finalQuality** for **debug.retrieval** (good | weak | fallback_other).
4. **attachUiDecision(result, originalQuery, uiIntent, plannedPrimaryVertical, lastResultStrength):**
   - **deriveAnswerConfidence(result, lastResultStrength, uiIntent)** uses **result.retrievalStats?.quality** first, then lastResultStrength, then uiIntent.confidenceExpectation → 'strong' | 'medium' | 'weak'.
   - If answerConfidence === 'weak' → **showCards: false**.
   - **ui.answerConfidence** set.
5. **debug.answerConfidence** = resultWithUi.ui?.answerConfidence; **debug.retrieval** = { vertical, items, snippets, quality: finalQuality, maxItems }.
6. **buildDynamicFollowUps(resultWithUi, ctx, { primaryVertical, intent, filterSummary, topResultNames }):**
   - **buildFilterSummary(extractedFilters)** → short string (e.g. "Boston, check-in 2025-03-01, 2 guests").
   - **getTopResultNames(result)** → up to 3 hotel names / product titles / flight routes / movie titles.
   - Prompt includes vertical, intent, filters, top results; LLM returns up to **3** contextual follow-ups (JSON array of strings).
7. **updateSession(ctx.sessionId, { appendTurn, lastSuccessfulVertical, lastResultStrength })** where lastResultStrength is derived from **result.retrievalStats?.quality** (good → strong, weak/fallback_other → weak, else ok).
8. **setCache(cacheKey, finalPayload)**; **shouldSampleForEval** → **submitForHumanReview** when sampled; **finishTrace**; **metrics.finish**; return **finalPayload**.

| File | Role |
|------|------|
| **`node/src/services/orchestrator.ts`** | **deriveRetrievalQuality**, **synthesisAnswerConfidence**, **buildFormattingGuidance**, **deriveAnswerConfidence**, **attachUiDecision**; **buildFilterSummary**, **getTopResultNames**, **buildDynamicFollowUps** with context; weak fallback; debug; **updateSession**; cache. |
| **`node/src/services/ui-intent.ts`** | **computeUiIntent(grounding, plannedPrimaryVertical)** → preferredLayout, confidenceExpectation. |
| **`node/src/services/ui_decision/*.ts`** | **buildHotelUiDecision**, **buildProductUiDecision**, etc. |
| **`node/src/memory/sessionMemory.ts`** | **updateSession**. |
| **`node/src/services/eval-sampling.ts`** | **shouldSampleForEval**, **submitForHumanReview**. |

**Result:** Full **PipelineResult** (summary, citations, vertical, cards, ui with answerConfidence, debug with quality/answerConfidence/clarificationTriggered/deepRefined, followUpSuggestions, needsClarification/clarificationQuestions when applicable).

---

## Stage 5: App Receives and Renders

The HTTP client receives the JSON. The answer screen shows interpretation, summary, vertical cards (hotels, products, flights, showtimes), map if applicable, citations, and follow-up suggestions. When **needsClarification** is true, the client can show **clarificationQuestions** and avoid treating the response as a full answer.

| File | Role |
|------|------|
| **`lib/core/api_client.dart`** / **`lib/services/query_api_client.dart`** | Parses response. |
| **`lib/widgets/ClonarAnswerWidget.dart`** | Renders summary, cards, citations, follow-ups. |
| **`lib/screens/ClonarAnswerScreen.dart`** | Answer screen driven by pipeline response. |

---

## Summary Table: One Query, All Stages

| Stage | What happens | Key files |
|-------|------------------------|-----------|
| 0 | Request; build **QueryContext**; load **session** (thread, last*Filters, lastSuccessfulVertical, lastResultStrength); **user memory**; **pipeline cache** check (return if hit). | **query.ts**, **sessionMemory.ts**, **userMemory.ts**, **api_client.dart**, **agent_provider.dart**, **ShopScreen.dart** |
| 1 | **Plan cache** (key: message+history, TTL 60s). **Hit:** use cached rewrite/filters/grounding. **Miss:** **rewrite** → if **needsClarification** return clarification payload (no retrieval); else **extractFilters** → **grounding** → **set plan cache**. | **orchestrator.ts**, **query-rewrite.ts**, **filter-extraction.ts**, **grounding-decision.ts** |
| 2 | **grounding_mode**: **none** → LLM-only, attachUi, follow-ups, session, cache, return. **hybrid** → overview + **deriveRetrievalQuality** + **buildFormattingGuidance** + synthesize; **retrievalStats.quality** derived. **full** → **7-stage** (plan → execute → merge → **deriveRetrievalQuality** + **buildFormattingGuidance** + synthesize); **retrievalStats.quality**, avgScore, topKAvg. | **orchestrator.ts**, **retrieval-plan.ts**, **retrieval-plan-executor.ts**, **retrieval-router.ts**, **llm-main.ts**, **perplexity-web.ts** |
| 3 | **Deep mode** (optional): if **ctx.mode === 'deep'** and full path, **critique** → if insufficient, **run 7-stage again** (expanded prompt); **debug.deepRefined = true**. | **orchestrator.ts** |
| 4 | **Post-retrieval:** retrievalQuality from result.retrievalStats ?? classifyRetrievalQuality; optional upgrade; **weak fallback** (web overview); **attachUiDecision** (deriveAnswerConfidence → showCards, answerConfidence); **debug.answerConfidence**, **debug.retrieval.quality**; **buildDynamicFollowUps** with vertical, intent, filterSummary, topResultNames; **updateSession**; cache; return. | **orchestrator.ts**, **ui-intent.ts**, **ui_decision/*.ts**, **sessionMemory.ts**, **eval-sampling.ts** |
| 5 | App receives JSON; renders summary, cards, sources, follow-ups; handles **needsClarification** / **clarificationQuestions** when present. | **api_client.dart**, **ClonarAnswerWidget.dart**, **ClonarAnswerScreen.dart** |

---

## Confidence and Quality Flow

- **deriveRetrievalQuality**: Deterministic. **citationCount === 0** → 'fallback_other'; **itemCount >= 4** → 'good'; else 'weak'. If quality would be 'good' and **avgScore < 0.5** and **itemCount <= 2** → downgrade to 'weak'. Used in **hybrid** and **7-stage**; no hardcoded 'good' or 'fallback_other'.
- **synthesisAnswerConfidence(quality)**: good → 'strong', weak/fallback_other → 'weak', else 'medium'. Drives **buildFormattingGuidance** (tables allowed only when strong + itemCount >= 2 + comparableAttributes).
- **deriveAnswerConfidence(result, lastResultStrength, uiIntent)**: Uses **result.retrievalStats?.quality** first, then lastResultStrength, then uiIntent.confidenceExpectation. Feeds **attachUiDecision** (showCards, ui.answerConfidence).
- **Debug:** **debug.retrieval.quality**, **debug.answerConfidence**, **debug.clarificationTriggered** (when clarification returned), **debug.deepRefined** (when deep refinement ran).

---

## Observability

- **Trace:** **debug.trace** (traceId, spans: rewrite, plan_cache_hit, filter_extraction, grounding_decision, plan, execute, merge, synthesize, hybrid_retrieval, deep_refinement). **query-processing-trace.ts**.
- **Metrics:** **query_processing_metrics**; **setMetricsCallback**. **query-processing-metrics.ts**.
- **Eval:** **debug.automatedEvalScores**; **shouldSampleForEval** → **submitForHumanReview**. **eval-sampling.ts**, **eval-automated.ts**.

---

## Design Notes

- **Plan cache:** Reduces redundant rewrite + filter + grounding on duplicate/retry (same message + history). TTL 60s. Clarification path does not set plan cache (early return before cache write).
- **Clarification loop:** When rewrite returns **needsClarification**, the pipeline returns immediately with **needsClarification: true** and **clarificationQuestions** (from conflicts). No retrieval; client can prompt user and resubmit.
- **Confidence:** One consistent signal: **deriveRetrievalQuality** → **retrievalStats.quality** → **synthesisAnswerConfidence** (formatting) and **deriveAnswerConfidence** (UI). No hardcoded confidence in hybrid or 7-stage.
- **Follow-ups:** **buildDynamicFollowUps** receives **primaryVertical**, **intent**, **filterSummary** (from **buildFilterSummary(extractedFilters)**), **topResultNames** (from **getTopResultNames(result)**) so follow-ups are contextual. Returns up to 3 suggestions.
- **Deep mode:** Optional second pass only when **ctx.mode === 'deep'** (or **mode === 'pro'**, normalized to deep) and full retrieval; critique decides; max one extra 7-stage run. Expanded prompt adds " Include more specific options and details." only when the rewritten prompt contains a question mark.
- **Dates/guests:** Planner may omit when user didn’t specify; **executor** injects system defaults. **preferenceDescription** is **preferenceContext** for scoring/rerank only, never hard filters.
- **Planned vs observed vertical:** **plannedPrimaryVertical** (first step); **observedPrimaryVertical** = result.vertical. Both in **debug**; **attachUiDecision** uses **resolveUiVertical** (observed, or planned when result is 'other').
- **Session:** **lastSuccessfulVertical**, **lastResultStrength** (from retrievalStats.quality) stored for next request.
- **Previous feedback:** When the user marked the previous answer as unhelpful (e.g. from the stream path via **getAndClearLastFeedback**), **ctx.previousFeedback** is set. The pipeline injects this into the LLM prompt for the ungrounded path and into synthesis so the model can improve (e.g. "The user marked the previous answer as unhelpful. For this follow-up, be more helpful, specific, or accurate.").
