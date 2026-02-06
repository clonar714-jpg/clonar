// src/services/orchestrator.ts — all four verticals + deep planner + multi-vertical + self-healing
import crypto from 'crypto';
import { QueryContext, QueryMode, Vertical, type PlanCandidate, type UiDecision } from '@/types/core';
import {
  VerticalPlan,
  ProductFilters,
  HotelFilters,
  FlightFilters,
  MovieTicketFilters,
} from '@/types/verticals';
import { getCache, setCache } from './cache';
import { logger } from './logger';
import { critiqueAndRefineSummary } from './critique-agent';
import { planResearchStep } from './planner-agent';
import { rewriteQuery } from './query-rewrite';
import { extractFilters, type ExtractedFilters } from './filter-extraction';
import { getRewrittenQueriesForMode, safeParseJson, decomposeIntoSubQueries } from './query-understanding';
import { callSmallLLM } from './llm-small';
import { perplexityOverview } from './providers/web/perplexity-web';
import type { PerplexityCitation } from './providers/web/perplexity-web';
import { callMainLLM } from './llm-main';
import { runProductAgent } from './vertical/product-agent';
import { runHotelAgent } from './vertical/hotel-agent';
import { runFlightAgent } from './vertical/flight-agent';
import { runMovieAgent } from './vertical/movie-agent';
import { ProductRetriever } from './providers/catalog/product-retriever';
import { HotelRetriever } from './providers/hotels/hotel-retriever';
import { FlightRetriever } from './providers/flights/flight-retriever';
import { MovieRetriever } from './providers/movies/movie-retriever';
import { buildHotelUiDecision } from './ui_decision/hotelUiDecision';
import { buildProductUiDecision } from './ui_decision/productUiDecision';
import { buildFlightUiDecision } from './ui_decision/flightUiDecision';
import { buildMovieUiDecision } from './ui_decision/movieUiDecision';
import { buildGenericUiDecision } from './ui_decision/genericUiDecision';
import { updateSession } from '@/memory/sessionMemory';
import { routeAndRetrieve } from './retrieval-router';
import { shouldUseGroundedRetrieval } from './grounding-decision';
import { createTrace, addSpan, finishTrace } from './query-processing-trace';
import { createRequestMetrics } from './query-processing-metrics';
import { shouldSampleForEval, submitForHumanReview } from './eval-sampling';
import { runAutomatedEvals } from './eval-automated';

export interface OrchestratorDeps {
  productRetriever: ProductRetriever;
  hotelRetriever: HotelRetriever;
  flightRetriever: FlightRetriever;
  movieRetriever: MovieRetriever;
  /** Optional key for retrieved-content cache (dual memory); set in runPipeline from makePlanCacheKey(ctx). */
  retrievedContentCacheKey?: string;
  /** Optional: used by retrieval router for semantic routing (query vs vertical profile embeddings). */
  embedder?: import('./providers/retrieval-vector-utils').Embedder;
  /** Optional: lightweight reranker for merged chunks before synthesis. */
  passageReranker?: import('./retrieval-router').PassageReranker;
}

export type Citation = {
  id: string;
  url: string;
  title?: string;
  snippet?: string;
  /** Source freshness (e.g. from Perplexity date/last_updated). */
  date?: string;
  last_updated?: string;
};

export interface RetrievalStats {
  vertical: string;
  itemCount: number;
  maxItems?: number;
  quality?: 'good' | 'weak' | 'fallback_other';
  /** Average rerank score (0–1); used to avoid treating small but highly relevant result sets as weak. */
  avgScore?: number;
  /** Perplexity-style: average of top-3 snippet scores; used for vertical ordering when available. */
  topKAvg?: number;
}

export interface BasePipelineResult {
  intent: VerticalPlan['intent'];
  summary: string;
  citations?: Citation[];
  /** Short answer (2–4 sentences) for definition box; optional, Flutter can derive from first paragraph. */
  definitionBlurb?: string;
  /** Numbered references line (e.g. "1. Title – domain"); optional, Flutter can build from citations. */
  referencesSection?: string;
  /** ISO timestamp when answer was generated (sources as of). */
  answerGeneratedAt?: string;
  /** Next-step links: Compare, Pricing, Talk to expert (Unusual.ai bridge modules). */
  bridgeLinks?: Array<{ label: string; url: string }>;
  /** When critique suggests a clearer query (wrong domain / vague); show "For a better answer, try: …" */
  suggestedQuery?: string;
  /** True when we actually used suggestedQuery to replan (so user sees "We used a refined question"). */
  suggestedQueryUsed?: boolean;
  /** Context-sensitive follow-up prompts (e.g. "Compare options", "Show on map"); optional intent can be used for sort/group in UI. */
  followUpSuggestions?: string[];
  retrievalStats?: RetrievalStats;
  debug?: DebugInfo;
  /** Vertical-agnostic UI: list vs detail, map, hero images, cards, primary actions. Backend fills; Flutter reads. */
  ui?: UiDecision;
  /** Perplexity-style: vertical hypothesis may be semantically downgraded after retrieval (guide/exploratory vs transactional). Presentation only. */
  semanticFraming?: 'guide' | 'transactional';
  /** Point 2: When flight + hotel results imply different airports (e.g. JFK vs LGA), surface conflict and suggestion. */
  crossPartHint?: { conflict: string; suggestion: string };
}

type Product = import('./providers/catalog/catalog-provider').Product;
type Hotel = import('./providers/hotels/hotel-provider').Hotel;
type Flight = import('./providers/flights/flight-provider').Flight;
type MovieShowtime = import('./providers/movies/movie-provider').MovieShowtime;

export type PipelineResult =
  | (BasePipelineResult & {
      vertical: 'product';
      products: Product[];
      secondaryHotels?: Hotel[];
      secondaryFlights?: Flight[];
      secondaryShowtimes?: MovieShowtime[];
    })
  | (BasePipelineResult & {
      vertical: 'hotel';
      hotels: Hotel[];
      secondaryProducts?: Product[];
      secondaryFlights?: Flight[];
      secondaryShowtimes?: MovieShowtime[];
    })
  | (BasePipelineResult & {
      vertical: 'flight';
      flights: Flight[];
      secondaryProducts?: Product[];
      secondaryHotels?: Hotel[];
      secondaryShowtimes?: MovieShowtime[];
    })
  | (BasePipelineResult & {
      vertical: 'movie';
      showtimes: MovieShowtime[];
      secondaryProducts?: Product[];
      secondaryHotels?: Hotel[];
      secondaryFlights?: Flight[];
    })
  | (BasePipelineResult & {
      vertical: 'other';
    });

export interface DebugInfo {
  originalQuery: string;
  rewrittenQuery: string;
  usedHistory: string[];
  mode?: QueryMode;
  /** Gated typo correction: confidence in [0,1] for the rewrite; when low, UI may show rewriteAlternatives. */
  rewriteConfidence?: number;
  /** Alternative phrasings when rewrite confidence is low (for "Did you mean?" in UI). */
  rewriteAlternatives?: string[];
  /** Confidence in [0,1] for intent classification (browse/compare/buy/book). */
  intentConfidence?: number;

  routing?: {
    candidates: Array<{
      vertical: Vertical;
      intent: VerticalPlan['intent'];
      score: number;
      /** Confidence in [0,1] for this vertical choice. */
      confidence?: number;
    }>;
    chosen: Vertical;
    multiVertical?: boolean;
    /** Intent/confidence-based routing from retrieval layer (for evals and metrics). */
    routingDecision?: import('./retrieval-router').RoutingDecision;
  };

  /** One-line interpretation for UI: "Searching for hotels in downtown NYC and attractions in Philadelphia." */
  interpretationSummary?: string;
  /** Actual search queries run (for "SEARCHING" / transparency in UI). */
  searchQueries?: string[];
  /** Decomposed parts when multi-part: [{ part, vertical }, ...]. */
  decomposedParts?: Array<{ part: string; vertical: string }>;

  /** Extracted filters from NL (temporal, categorical) for retrieval/APIs; for evals and monitoring. */
  extractedFilters?: ExtractedFilters;

  /** True when deep mode ran the critique pass. */
  deepRefined?: boolean;

  /** Deep mode: planner decision and optional extra query (dev/debug). */
  deepPlanner?: {
    decision: string;
    newQuery?: string;
  };

  /** Per-query retrieval counts (for evals / tuning). */
  retrieval?: {
    vertical: string;
    items: number;
    snippets: number;
    quality: 'good' | 'weak' | 'fallback_other';
    maxItems?: number;
  };

  /** When we skip retrieval (conceptual query): grounding decision and reason. */
  groundingDecision?: {
    needs_grounding: false;
    reason: string;
  };

  /** Structured trace (spans) for query processing; for online eval and observability. */
  trace?: import('./query-processing-trace').QueryProcessingTrace;

  /** Automated component-level eval scores (rewrite, filter, routing) when available. */
  automatedEvalScores?: import('./eval-automated').AutomatedEvalScores;
}

// ---------- Type guards for PipelineResult union ----------

function isProductResult(
  r: PipelineResult,
): r is Extract<PipelineResult, { vertical: 'product' }> {
  return r.vertical === 'product';
}
function isHotelResult(
  r: PipelineResult,
): r is Extract<PipelineResult, { vertical: 'hotel' }> {
  return r.vertical === 'hotel';
}
function isFlightResult(
  r: PipelineResult,
): r is Extract<PipelineResult, { vertical: 'flight' }> {
  return r.vertical === 'flight';
}
function isMovieResult(
  r: PipelineResult,
): r is Extract<PipelineResult, { vertical: 'movie' }> {
  return r.vertical === 'movie';
}

// ---------- Helpers ----------

function getResultItemsCount(r: PipelineResult): number {
  if (r.vertical === 'product') return r.products.length;
  if (r.vertical === 'hotel') return r.hotels.length;
  if (r.vertical === 'flight') return r.flights.length;
  if (r.vertical === 'movie') return r.showtimes.length;
  return 0;
}

/** Quality score for adaptive primary/secondary ordering: presentation reflects what actually worked best. Uses topKAvg when available (Perplexity-style: weight by best results, not only global average). */
function retrievalQualityScore(r: PipelineResult): number {
  const count = getResultItemsCount(r);
  const score = r.retrievalStats?.topKAvg ?? r.retrievalStats?.avgScore ?? 0.5;
  return count * Math.max(0.1, score);
}

/** Perplexity-style, answer-specific follow-up questions via one small-LLM call. */
async function buildDynamicFollowUps(
  result: PipelineResult,
  ctx: QueryContext,
): Promise<string[]> {
  const summary = result.summary ?? '';
  if (!summary || summary.length < 80) return [];

  const prompt = `
You are generating follow-up questions for a user based on their question and the answer.

Rules:
- Return ONLY valid JSON: {"followUps":[string, string, ...]}
- Do NOT include markdown or code fences.
- Make each follow-up specific to this topic, not generic.
- Avoid repeating the original question.
- Prefer questions that deepen or extend the topic (comparisons, trade-offs, implications, next steps).
- Keep each follow-up under 120 characters.

Original question: ${JSON.stringify(ctx.message)}

Answer summary:
${summary.slice(0, 2000)}

Return 3–5 follow-up questions as described.
`;

  const raw = await callSmallLLM(prompt);
  const parsed = safeParseJson(raw, 'buildDynamicFollowUps');
  const arr = Array.isArray(parsed?.followUps) ? parsed.followUps : [];
  const cleaned = arr
    .filter((x: unknown) => typeof x === 'string')
    .map((s: string) => s.trim())
    .filter((s: string) => s.length > 0 && s.length <= 200);

  return cleaned.slice(0, 5);
}

function makePipelineCacheKey(ctx: QueryContext): string {
  const mode = ctx.mode ?? 'quick';
  const historyKey = JSON.stringify(ctx.history ?? []);
  const raw = `${mode}:${ctx.message}:${historyKey}`;
  const hash = crypto.createHash('sha256').update(raw).digest('hex').slice(0, 32);
  return `pipeline:${hash}`;
}

/** Plan cache key: message + history only (plan is mode-agnostic). Avoids recomputing understandQuery on duplicate/retry. */
function makePlanCacheKey(ctx: QueryContext): string {
  const historyKey = JSON.stringify(ctx.history ?? []);
  const raw = `${ctx.message}:${historyKey}`;
  const hash = crypto.createHash('sha256').update(raw).digest('hex').slice(0, 32);
  return `plan:${hash}`;
}

const PIPELINE_CACHE_TTL_SECONDS = 60;

type CandidateLike = { vertical: Vertical; intent: VerticalPlan['intent']; score: number };

const MAX_VERTICALS_FAN_OUT = 5;

function selectVerticals<T extends CandidateLike>(candidates: T[]): T[] {
  if (!candidates?.length) return [];
  const sorted = [...candidates].sort((a, b) => b.score - a.score);
  const primary = sorted[0];
  const selected: T[] = [primary];
  const seen = new Set([primary.vertical]);
  for (let i = 1; i < sorted.length && selected.length < MAX_VERTICALS_FAN_OUT; i++) {
    const next = sorted[i];
    if (
      next &&
      !seen.has(next.vertical) &&
      next.score >= primary.score - 0.15 &&
      next.score >= 0.5
    ) {
      seen.add(next.vertical);
      selected.push(next);
    }
  }
  return selected;
}

/** Build a full VerticalPlan from a candidate when it has its own filters; otherwise merge vertical/intent onto basePlan. When basePlan has decomposedContext for this vertical (query decomposition), use it as preferenceContext so each vertical gets focused context. Search queries are generated inside each vertical agent (adaptive retrieval), not passed from the plan. */
function planFromCandidate(
  candidate: PlanCandidate,
  basePlan: VerticalPlan,
): VerticalPlan {
  const { vertical, intent } = candidate;
  const preferenceContext =
    basePlan.decomposedContext?.[vertical] ?? basePlan.preferenceContext;
  const planOverrides = {
    vertical,
    intent,
    ...(preferenceContext != null && { preferenceContext }),
  };
  if (vertical === 'product' && candidate.productFilters) {
    return {
      ...basePlan,
      ...planOverrides,
      product: candidate.productFilters as ProductFilters,
    } as VerticalPlan;
  }
  if (vertical === 'hotel' && candidate.hotelFilters) {
    return {
      ...basePlan,
      ...planOverrides,
      hotel: candidate.hotelFilters as HotelFilters,
    } as VerticalPlan;
  }
  if (vertical === 'flight' && candidate.flightFilters) {
    return {
      ...basePlan,
      ...planOverrides,
      flight: candidate.flightFilters as FlightFilters,
    } as VerticalPlan;
  }
  if (vertical === 'movie' && candidate.movieFilters) {
    return {
      ...basePlan,
      ...planOverrides,
      movie: candidate.movieFilters as MovieTicketFilters,
    } as VerticalPlan;
  }
  return { ...basePlan, ...planOverrides } as VerticalPlan;
}

function classifyRetrievalQuality(
  items: number,
  maxItems: number | undefined,
): 'good' | 'weak' {
  if (!maxItems || maxItems <= 0) return 'good';
  const hitRate = items / maxItems;
  return hitRate < 0.2 ? 'weak' : 'good';
}

// ---------- Vertical runner (unchanged shape per agent) ----------

async function runVerticalSingle(
  plan: VerticalPlan,
  deps: OrchestratorDeps,
  ctx: QueryContext,
): Promise<PipelineResult> {
  switch (plan.vertical) {
    case 'product': {
      const res = await runProductAgent(plan, { retriever: deps.productRetriever, retrievedContentCacheKey: deps.retrievedContentCacheKey });
      const out: PipelineResult = {
        vertical: 'product',
        intent: plan.intent,
        summary: res.summary,
        products: res.products,
        citations: res.citations,
        retrievalStats: res.retrievalStats,
      };
      return res.searchQueries?.length ? { ...out, searchQueries: res.searchQueries } as PipelineResult & { searchQueries: string[] } : out;
    }
    case 'hotel': {
      const res = await runHotelAgent(plan, { retriever: deps.hotelRetriever, retrievedContentCacheKey: deps.retrievedContentCacheKey });
      const out: PipelineResult = {
        vertical: 'hotel',
        intent: plan.intent,
        summary: res.summary,
        hotels: res.hotels,
        citations: res.citations,
        retrievalStats: res.retrievalStats,
      };
      return res.searchQueries?.length ? { ...out, searchQueries: res.searchQueries } as PipelineResult & { searchQueries: string[] } : out;
    }
    case 'flight': {
      const res = await runFlightAgent(plan, { retriever: deps.flightRetriever });
      const out: PipelineResult = {
        vertical: 'flight',
        intent: plan.intent,
        summary: res.summary,
        flights: res.flights,
        citations: res.citations,
        retrievalStats: res.retrievalStats,
      };
      return res.searchQueries?.length ? { ...out, searchQueries: res.searchQueries } as PipelineResult & { searchQueries: string[] } : out;
    }
    case 'movie': {
      const res = await runMovieAgent(plan, { retriever: deps.movieRetriever, retrievedContentCacheKey: deps.retrievedContentCacheKey });
      const out: PipelineResult = {
        vertical: 'movie',
        intent: plan.intent,
        summary: res.summary,
        showtimes: res.showtimes,
        citations: res.citations,
        retrievalStats: res.retrievalStats,
      };
      return res.searchQueries?.length ? { ...out, searchQueries: res.searchQueries } as PipelineResult & { searchQueries: string[] } : out;
    }
    case 'other':
    default: {
      // Other = web search only (Perplexity API). Grounding decision at pipeline start already skips retrieval when not needed.
      const prefStr =
        plan.preferenceContext != null
          ? Array.isArray(plan.preferenceContext)
            ? plan.preferenceContext.join(' ')
            : plan.preferenceContext
          : '';
      let userPrompt =
        prefStr ? `${plan.rewrittenPrompt}\n\nUser preferences / context: ${prefStr}` : plan.rewrittenPrompt;
      const locations = plan.entities?.locations ?? [];
      const entities = plan.entities?.entities ?? [];
      const anchors = [...locations, ...entities].filter(Boolean).slice(0, 3);
      if (anchors.length) {
        userPrompt = `${userPrompt}\n\nKey places/entities: ${anchors.join(', ')}`;
      }
      const overview = await perplexityOverview(userPrompt);
      const citations: Citation[] = (overview.citations ?? []).map((c: PerplexityCitation) => ({
        id: c.id,
        url: c.url,
        title: c.title,
        snippet: c.snippet,
        date: c.date,
        last_updated: c.last_updated,
      }));
      const out: PipelineResult = {
        vertical: 'other',
        intent: plan.intent,
        summary: overview.summary,
        ...(citations.length > 0 && { citations }),
      };
      return { ...out, searchQueries: [plan.rewrittenPrompt] } as PipelineResult & { searchQueries: string[] };
    }
  }
}

/** Merge primary + secondary results into one PipelineResult (primary slot + secondary* slots). */
function mergeVerticalResults(
  primaryResult: PipelineResult,
  secondaryResults: PipelineResult[],
): PipelineResult {
  type WithSecondaries = PipelineResult & {
    secondaryProducts?: Product[];
    secondaryHotels?: Hotel[];
    secondaryFlights?: Flight[];
    secondaryShowtimes?: MovieShowtime[];
  };
  let merged: WithSecondaries = primaryResult as WithSecondaries;
  let allCitations: Citation[] = primaryResult.citations ?? [];

  for (const verticalResult of secondaryResults) {
    const sectionHeader = `\n\n---\n\nAlso relevant (${verticalResult.vertical}):\n`;
    merged = {
      ...merged,
      summary: (merged.summary ?? '') + sectionHeader + (verticalResult.summary ?? ''),
    };

    if (verticalResult.vertical === 'product' && isProductResult(verticalResult)) {
      merged = {
        ...merged,
        secondaryProducts: [...(merged.secondaryProducts ?? []), ...(verticalResult.products ?? [])],
      };
    } else if (verticalResult.vertical === 'hotel' && isHotelResult(verticalResult)) {
      merged = {
        ...merged,
        secondaryHotels: [...(merged.secondaryHotels ?? []), ...(verticalResult.hotels ?? [])],
      };
    } else if (verticalResult.vertical === 'flight' && isFlightResult(verticalResult)) {
      merged = {
        ...merged,
        secondaryFlights: [...(merged.secondaryFlights ?? []), ...(verticalResult.flights ?? [])],
      };
    } else if (verticalResult.vertical === 'movie' && isMovieResult(verticalResult)) {
      merged = {
        ...merged,
        secondaryShowtimes: [...(merged.secondaryShowtimes ?? []), ...(verticalResult.showtimes ?? [])],
      };
    }

    allCitations = [...allCitations, ...(verticalResult.citations ?? [])];
  }

  return { ...merged, citations: allCitations } as PipelineResult;
}

/**
 * Reorder [primary, ...secondaries] by retrieval quality so the best vertical is first.
 * Affects presentation priority only (UI shows what worked best); does not rerun query understanding.
 */
function reorderByRetrievalQuality(
  primaryResult: PipelineResult,
  secondaryResults: PipelineResult[],
): { primary: PipelineResult; secondaries: PipelineResult[] } {
  const all = [primaryResult, ...secondaryResults];
  const sorted = [...all].sort((a, b) => retrievalQualityScore(b) - retrievalQualityScore(a));
  return { primary: sorted[0], secondaries: sorted.slice(1) };
}

/** Normalize airport mention to a canonical key for comparison (JFK, LGA, EWR). */
function normalizeAirport(text: string | undefined): string | undefined {
  if (!text || typeof text !== 'string') return undefined;
  const lower = text.toLowerCase().replace(/\s+/g, ' ');
  if (lower.includes('jfk')) return 'jfk';
  if (lower.includes('lga') || lower.includes('laguardia') || lower.includes('la guardia')) return 'lga';
  if (lower.includes('ewr') || lower.includes('newark')) return 'ewr';
  return undefined;
}

/** Point 2: Detect flight+hotel cross-part conflict (e.g. flying into JFK but hotel search near LGA). */
function checkCrossPartConflict(
  primaryResult: PipelineResult,
  secondaryResults: PipelineResult[],
  basePlan: VerticalPlan,
): { conflict: string; suggestion: string } | undefined {
  const flightDest = (() => {
    if (isFlightResult(primaryResult) && primaryResult.flights?.length) {
      return normalizeAirport(primaryResult.flights[0].destination);
    }
    const secFlights = (primaryResult as any).secondaryFlights as Flight[] | undefined;
    if (secFlights?.length) return normalizeAirport(secFlights[0].destination);
    for (const r of secondaryResults) {
      if (isFlightResult(r) && r.flights?.length) return normalizeAirport(r.flights[0].destination);
    }
    const flightCandidate = basePlan.candidates?.find((c) => c.vertical === 'flight');
    return normalizeAirport(flightCandidate?.flightFilters?.destination);
  })();
  const hotelArea = (() => {
    if (isHotelResult(primaryResult) && primaryResult.hotels?.length) {
      return normalizeAirport(primaryResult.hotels[0].location);
    }
    const secHotels = (primaryResult as any).secondaryHotels as Hotel[] | undefined;
    if (secHotels?.length) return normalizeAirport(secHotels[0].location);
    for (const r of secondaryResults) {
      if (isHotelResult(r) && r.hotels?.length) return normalizeAirport(r.hotels[0].location);
    }
    const hotelCandidate = basePlan.candidates?.find((c) => c.vertical === 'hotel');
    return normalizeAirport(hotelCandidate?.hotelFilters?.area ?? hotelCandidate?.hotelFilters?.destination);
  })();
  if (!flightDest || !hotelArea || flightDest === hotelArea) return undefined;
  const airportNames: Record<string, string> = { jfk: 'JFK', lga: 'LaGuardia (LGA)', ewr: 'Newark (EWR)' };
  return {
    conflict: `You're flying into ${airportNames[flightDest] ?? flightDest.toUpperCase()}, but hotel results are for ${airportNames[hotelArea] ?? hotelArea.toUpperCase()}.`,
    suggestion: `Want hotels near ${airportNames[flightDest] ?? flightDest.toUpperCase()} to match your flight?`,
  };
}

async function runVerticalAgentMulti(
  basePlan: VerticalPlan,
  deps: OrchestratorDeps,
  ctx: QueryContext,
): Promise<{
  result: PipelineResult;
  citations: Citation[];
  routingInfo: DebugInfo['routing'];
  searchQueries: string[];
}> {
  const candidates = basePlan.candidates ?? [];
  const selected = selectVerticals(candidates);
  const primary = selected[0];

  if (!primary) {
    const fallbackResult = await runVerticalSingle(basePlan, deps, ctx);
    const sq = (fallbackResult as PipelineResult & { searchQueries?: string[] }).searchQueries ?? [];
    return {
      result: fallbackResult,
      citations: fallbackResult.citations ?? [],
      routingInfo: {
        candidates: [],
        chosen: basePlan.vertical,
        multiVertical: false,
      },
      searchQueries: sq,
    };
  }

  const multiVertical = selected.length > 1;
  const routingInfo: DebugInfo['routing'] = {
    candidates: candidates.map((c) => ({
      vertical: c.vertical,
      intent: c.intent,
      score: c.score,
      ...(c.confidence != null && { confidence: c.confidence }),
    })),
    chosen: primary.vertical,
    multiVertical,
  };

  // Run all selected verticals in parallel (primary + secondaries); total time ≈ slowest vertical instead of sum.
  const allResults = await Promise.all(
    selected.map((candidate) => {
      const verticalPlan = planFromCandidate(candidate, basePlan);
      return runVerticalSingle(verticalPlan, deps, ctx);
    }),
  );

  const primaryResult = allResults[0];
  const secondaryResults = allResults.slice(1);

  // Adaptive primary vs secondary: promote the vertical with best retrieval quality (presentation only)
  const { primary: orderedPrimary, secondaries: orderedSecondaries } =
    reorderByRetrievalQuality(primaryResult, secondaryResults);

  let mergedResult = mergeVerticalResults(orderedPrimary, orderedSecondaries);
  const allCitations = mergedResult.citations ?? [];

  // Point 2: Cross-part conflict — e.g. flight into JFK vs hotel near LGA; surface hint so user can align.
  const crossPartHint = checkCrossPartConflict(orderedPrimary, orderedSecondaries, basePlan);
  if (crossPartHint) {
    mergedResult = { ...mergedResult, crossPartHint } as PipelineResult;
  }

  // Perplexity-style: vertical hypothesis may be semantically downgraded after retrieval (guide vs transactional).
  const primaryStructured =
    orderedPrimary.vertical === 'hotel' ||
    orderedPrimary.vertical === 'flight' ||
    orderedPrimary.vertical === 'product' ||
    orderedPrimary.vertical === 'movie';
  const primaryWeak =
    (getResultItemsCount(orderedPrimary) <= 3 &&
      (orderedPrimary.retrievalStats?.avgScore ?? 0.5) < 0.6) ||
    (orderedPrimary.retrievalStats?.quality === 'weak');
  const otherStrong = orderedSecondaries.some(
    (r) =>
      r.vertical === 'other' && (r.summary?.length ?? 0) > 150,
  );
  if (primaryStructured && primaryWeak && otherStrong) {
    mergedResult = { ...mergedResult, semanticFraming: 'guide' } as PipelineResult;
  }

  const allSearchQueries = allResults.flatMap(
    (r) => (r as PipelineResult & { searchQueries?: string[] }).searchQueries ?? [],
  );

  return { result: mergedResult, citations: allCitations, routingInfo, searchQueries: allSearchQueries };
}

/** Perplexity-style central retrieval: flat sub-queries → router → multiple retrievers per query → merge + rerank. No vertical ownership of retrieval. */
const ROUTER_GROUNDING_SYSTEM = `You are a search assistant. You receive Working memory (context only) and Retrieved content (factual sources only).
Use ONLY the Retrieved content for factual claims; cite [1], [2], etc.
Do not invent details. Do not infer facts from the plan or assume vertical correctness.
If the list doesn't cover something, say so.`;

/**
 * Central retrieval is the default fast path. Builds a minimal plan internally for the retrieval layer only.
 * Sub-queries (or single [rewrittenPrompt] when decomposition is empty) always go to routeAndRetrieve; the router decides verticals.
 * There is always a rewritten prompt by the time we get here; if we have no sub-queries we return a minimal empty result.
 */
async function runCentralRetrieval(
  rewrittenPrompt: string,
  subQueries: string[] | undefined,
  deps: OrchestratorDeps,
  ctx: QueryContext,
  extractedFilters?: ExtractedFilters,
): Promise<{
  result: PipelineResult;
  citations: Citation[];
  routingInfo: DebugInfo['routing'];
  searchQueries: string[];
  primaryVertical: Vertical;
}> {
  // Always send at least [rewrittenPrompt] to routing when we have a message; router decides verticals. Empty decomposition → single-query fallback.
  const fallbackQuery = [rewrittenPrompt?.trim() || ctx.message.trim()].filter(Boolean);
  const flatSubQueries =
    (subQueries?.length
      ? (subQueries.filter((q) => typeof q === 'string' && q.trim().length > 0) as string[])
      : undefined) ?? fallbackQuery;

  // Minimal plan only for retrieval layer (router + getHotelFilters etc.). Merge extracted filters so APIs get structured params.
  const planForRetrieval = {
    vertical: 'other' as const,
    intent: 'browse' as const,
    rewrittenPrompt,
    subQueries: flatSubQueries.length > 0 ? flatSubQueries : undefined,
    ...(extractedFilters?.hotel && {
      hotel: {
        destination: extractedFilters.hotel.destination ?? 'unknown',
        checkIn: extractedFilters.hotel.checkIn ?? new Date().toISOString().slice(0, 10),
        checkOut: extractedFilters.hotel.checkOut ?? new Date(Date.now() + 86400000).toISOString().slice(0, 10),
        guests: extractedFilters.hotel.guests ?? 2,
        ...extractedFilters.hotel,
      } as HotelFilters,
    }),
    ...(extractedFilters?.flight && {
      flight: {
        origin: extractedFilters.flight.origin ?? '',
        destination: extractedFilters.flight.destination ?? 'unknown',
        departDate: extractedFilters.flight.departDate ?? new Date().toISOString().slice(0, 10),
        adults: extractedFilters.flight.adults ?? 1,
        ...extractedFilters.flight,
      } as FlightFilters,
    }),
    ...(extractedFilters?.product && {
      product: {
        query: extractedFilters.product.query ?? rewrittenPrompt.slice(0, 200),
        ...extractedFilters.product,
      } as ProductFilters,
    }),
    ...(extractedFilters?.movie && {
      movie: {
        city: extractedFilters.movie.city ?? 'unknown',
        date: extractedFilters.movie.date ?? new Date().toISOString().slice(0, 10),
        tickets: extractedFilters.movie.tickets ?? 2,
        ...extractedFilters.movie,
      } as MovieTicketFilters,
    }),
  } as VerticalPlan;

  // Should not happen: we always have rewrittenPrompt (or ctx.message) so fallbackQuery is non-empty. Guard for safety.
  if (flatSubQueries.length === 0) {
    const emptyResult: PipelineResult = {
      intent: 'browse',
      summary: '',
      citations: [],
      vertical: 'other',
      retrievalStats: { vertical: 'other', itemCount: 0, quality: 'good' },
    };
    return {
      result: emptyResult,
      citations: [],
      routingInfo: { candidates: [], chosen: 'other', multiVertical: false },
      searchQueries: [],
      primaryVertical: 'other',
    };
  }

  const { chunks, bySource, searchQueries, routingDecision } = await routeAndRetrieve(flatSubQueries, deps, ctx, planForRetrieval);

  const citations: Citation[] = chunks.map((c) => ({
    id: c.id,
    url: c.url,
    title: c.title,
    snippet: c.text,
  }));

  const workingMemory = {
    userQuery: rewrittenPrompt,
    preferenceContext: undefined,
  };
  const retrievedPassages = chunks
    .map((c, i) => `[${i + 1}] ${(c.title ? c.title + ': ' : '')}${c.text.replace(/\s+/g, ' ').slice(0, 400)}`)
    .join('\n');
  const userContent = `
Working memory (context only; do not cite as source):
${JSON.stringify(workingMemory)}

Retrieved content (cite as [1], [2], ...):
${retrievedPassages}
`;
  const summary = await callMainLLM(ROUTER_GROUNDING_SYSTEM, userContent);

  // UI vertical is post-hoc only: choose after retrieval.
  const withCounts = (
    [
      { v: 'hotel' as Vertical, n: bySource.hotel?.length ?? 0 },
      { v: 'flight' as Vertical, n: bySource.flight?.length ?? 0 },
      { v: 'product' as Vertical, n: bySource.product?.length ?? 0 },
      { v: 'movie' as Vertical, n: bySource.movie?.length ?? 0 },
    ] as { v: Vertical; n: number }[]
  ).filter((x) => x.n > 0);
  const primaryVertical: Vertical =
    withCounts.length > 0 ? withCounts.reduce((a, b) => (a.n >= b.n ? a : b)).v : 'other';

  const baseResult: BasePipelineResult = {
    intent: 'browse',
    summary: summary.trim(),
    citations,
    retrievalStats: {
      vertical: primaryVertical,
      itemCount:
        (bySource.hotel?.length ?? 0) +
        (bySource.flight?.length ?? 0) +
        (bySource.product?.length ?? 0) +
        (bySource.movie?.length ?? 0),
      quality: 'good',
    },
  };

  let result: PipelineResult;
  if (primaryVertical === 'hotel' && (bySource.hotel?.length ?? 0) > 0) {
    result = { ...baseResult, vertical: 'hotel', hotels: bySource.hotel ?? [] };
  } else if (primaryVertical === 'flight' && (bySource.flight?.length ?? 0) > 0) {
    result = { ...baseResult, vertical: 'flight', flights: bySource.flight ?? [] };
  } else if (primaryVertical === 'product' && (bySource.product?.length ?? 0) > 0) {
    result = { ...baseResult, vertical: 'product', products: bySource.product ?? [] };
  } else if (primaryVertical === 'movie' && (bySource.movie?.length ?? 0) > 0) {
    result = { ...baseResult, vertical: 'movie', showtimes: bySource.movie ?? [] };
  } else {
    result = { ...baseResult, vertical: 'other' };
  }

  const routingInfo: DebugInfo['routing'] = {
    candidates: [{ vertical: primaryVertical, intent: 'browse', score: 1 }],
    chosen: primaryVertical,
    multiVertical: false,
    ...(routingDecision && { routingDecision }),
  };

  return {
    result,
    citations,
    routingInfo,
    searchQueries,
    primaryVertical,
  };
}

/** Attach UI hints (layouts, map possible, cards, actions). Frontend chooses final presentation. */
function attachUiDecision(
  result: PipelineResult,
  originalQuery: string,
): PipelineResult {
  switch (result.vertical) {
    case 'hotel':
      return isHotelResult(result)
        ? { ...result, ui: buildHotelUiDecision(originalQuery, result.hotels) }
        : result;
    case 'product':
      return isProductResult(result)
        ? { ...result, ui: buildProductUiDecision(originalQuery, result.products) }
        : result;
    case 'flight':
      return isFlightResult(result)
        ? { ...result, ui: buildFlightUiDecision(originalQuery, result.flights) }
        : result;
    case 'movie':
      return isMovieResult(result)
        ? { ...result, ui: buildMovieUiDecision(originalQuery, result.showtimes) }
        : result;
    case 'other':
    default:
      return { ...result, ui: buildGenericUiDecision(originalQuery) };
  }
}

// ---------- Main pipeline ----------

export async function runPipeline(
  ctx: QueryContext,
  deps: OrchestratorDeps,
): Promise<PipelineResult> {
  const startedAt = Date.now();
  const mode: QueryMode = ctx.mode ?? 'quick';
  const cacheKey = makePipelineCacheKey(ctx);

  const truncatedMessage = ctx.message.slice(0, 200);

  if (mode === 'quick') {
    const cached = await getCache<PipelineResult>(cacheKey);
    if (cached) {
      logger.info('pipeline:cache_hit', {
        mode,
        message: truncatedMessage,
      });
      return cached;
    }
  }

  logger.info('runPipeline:start', {
    message: truncatedMessage,
    mode,
  });

  const pipelineStartedAt = Date.now();
  const rewriteVariant = ctx.rewriteVariant ?? 'default';
  const trace = createTrace({ originalQuery: ctx.message, variant: rewriteVariant });
  const metrics = createRequestMetrics();

  try {
    const understandStarted = Date.now();
    let rewrittenPrompt: string;
    if (rewriteVariant === 'none') {
      rewrittenPrompt = ctx.message?.trim() ?? '';
      metrics.recordRewrite(false);
      addSpan(trace, 'rewrite', understandStarted, {
        metadata: { variant: 'none', skipped: true },
        output: { rewrittenPrompt },
      });
    } else {
      const rewriteResult = await rewriteQuery(ctx);
      rewrittenPrompt = rewriteResult.rewrittenPrompt;
      metrics.recordRewrite(rewrittenPrompt !== (ctx.message?.trim() ?? ''));
      addSpan(trace, 'rewrite', understandStarted, {
        input: { message: ctx.message },
        output: { rewrittenPrompt },
      });
      trace.rewrittenQuery = rewrittenPrompt;
    }

    const understandDuration = Date.now() - understandStarted;
    logger.info('runPipeline:rewrite:done', { mode, durationMs: understandDuration });

    const filterExtractStarted = Date.now();
    let extractedFilters: ExtractedFilters = {};
    try {
      extractedFilters = await extractFilters(ctx, rewrittenPrompt);
      const hasHotel = !!extractedFilters.hotel;
      const hasFlight = !!extractedFilters.flight;
      const hasProduct = !!extractedFilters.product;
      const hasMovie = !!extractedFilters.movie;
      addSpan(trace, 'filter_extraction', filterExtractStarted, {
        output: { hasHotel, hasFlight, hasProduct, hasMovie },
      });
    } catch (err) {
      logger.warn('runPipeline:filter_extraction_failed', { err: err instanceof Error ? err.message : String(err) });
      addSpan(trace, 'filter_extraction', filterExtractStarted, { error: String(err) });
    }

    const groundingStarted = Date.now();
    let grounding: { needs_grounding: boolean; reason: string };
    try {
      grounding = await shouldUseGroundedRetrieval(ctx, rewrittenPrompt);
    } catch (err) {
      logger.warn('runPipeline:grounding_failed', { err: err instanceof Error ? err.message : String(err) });
      grounding = { needs_grounding: true, reason: 'Grounding check failed, continuing with retrieval' };
    }
    addSpan(trace, 'grounding_decision', groundingStarted, {
      output: { needs_grounding: grounding.needs_grounding, reason: grounding.reason?.slice(0, 100) },
    });
    metrics.recordGroundingSkipped(!grounding.needs_grounding);

    if (!grounding.needs_grounding) {
      try {
        // No retrieval: answer from knowledge only.
        const systemPrompt =
          'You are a helpful assistant. Answer the user\'s question clearly using your knowledge. Do not cite external sources; this is a conceptual or general-knowledge question. Be concise and accurate.';
        const summary = await callMainLLM(systemPrompt, rewrittenPrompt);
        const ungroundedResult = {
        vertical: 'other' as Vertical,
        intent: 'browse' as const,
        summary: summary.trim(),
      } as PipelineResult;
      const resultWithUi = attachUiDecision(ungroundedResult, ctx.message);
      const usedHistory = ctx.history?.slice(-5) ?? [];
      const debug: DebugInfo = {
        originalQuery: ctx.message,
        rewrittenQuery: rewrittenPrompt,
        usedHistory,
        mode,
        interpretationSummary: 'Answered from general knowledge (no search).',
        groundingDecision: { needs_grounding: false, reason: grounding.reason },
        trace,
      };
      const firstParagraph = (resultWithUi.summary ?? '').split(/\n\n+/)[0]?.trim() ?? '';
      const definitionBlurb =
        firstParagraph.length > 0 && firstParagraph.length <= 600 ? firstParagraph : undefined;
      const followUpSuggestions = await buildDynamicFollowUps(resultWithUi, ctx);
      const finalPayload: PipelineResult = {
        ...resultWithUi,
        debug,
        citations: [],
        answerGeneratedAt: new Date().toISOString(),
        ...(definitionBlurb && { definitionBlurb }),
        ...(followUpSuggestions.length > 0 && { followUpSuggestions }),
      };
      if (shouldSampleForEval()) {
        submitForHumanReview({
          traceId: trace.traceId,
          trace,
          originalQuery: ctx.message,
          rewrittenQuery: rewrittenPrompt,
          summary: resultWithUi.summary,
          routing: undefined,
        });
      }
      if (mode === 'quick') {
        await setCache(cacheKey, finalPayload, PIPELINE_CACHE_TTL_SECONDS);
      }
      if (ctx.sessionId) {
        try {
          await updateSession(ctx.sessionId, {
            appendTurn: { query: ctx.message, answer: resultWithUi.summary ?? '' },
          });
        } catch (sessionErr) {
          logger.warn('runPipeline:updateSession failed (ungrounded)', { sessionId: ctx.sessionId });
        }
      }
      logger.info('runPipeline:ungrounded:done', { reason: grounding.reason.slice(0, 80) });
      return finalPayload;
      } catch (ungroundedErr) {
        logger.warn('runPipeline:ungrounded_failed', { err: ungroundedErr instanceof Error ? ungroundedErr.message : String(ungroundedErr) });
        // Fall through to normal retrieval so we don't get stuck.
      }
    }

    const decomposeStarted = Date.now();
    const subQueries = await decomposeIntoSubQueries(ctx, rewrittenPrompt);
    const totalSubQueries = subQueries.length;
    addSpan(trace, 'decompose', decomposeStarted, {
      output: { subQueryCount: totalSubQueries },
    });
    metrics.recordDecomposition(totalSubQueries);
    if (subQueries.length > 0) {
      logger.info('runPipeline:decomposeIntoSubQueries:done', { totalSub: totalSubQueries });
    }

    const usedHistory = ctx.history.slice(-5);
    const debug: DebugInfo = {
      originalQuery: ctx.message,
      rewrittenQuery: rewrittenPrompt,
      usedHistory,
      mode,
      trace,
      ...((extractedFilters?.hotel ?? extractedFilters?.flight ?? extractedFilters?.product ?? extractedFilters?.movie) && { extractedFilters }),
    };

    const retrievalStarted = Date.now();
    const depsWithCacheKey = { ...deps, retrievedContentCacheKey: makePlanCacheKey(ctx) };
    const { result: initialResult, citations: initialCitations, routingInfo, searchQueries: firstPassSearchQueries, primaryVertical } =
      await runCentralRetrieval(rewrittenPrompt, subQueries, depsWithCacheKey, ctx, extractedFilters);
    addSpan(trace, 'retrieval', retrievalStarted, {
      output: {
        searchQueriesCount: firstPassSearchQueries?.length ?? 0,
        chosen: routingInfo?.chosen,
        routingRationale: routingInfo?.routingDecision?.rationale,
        retrievalQuality: initialResult.retrievalStats?.quality,
        topKAvg: initialResult.retrievalStats?.topKAvg,
      },
    });
    metrics.recordRouting(routingInfo?.chosen ? [routingInfo.chosen] : []);
    if (routingInfo?.routingDecision) {
      metrics.recordRoutingDecision(
        routingInfo.routingDecision.primary,
        routingInfo.routingDecision.confidence,
        routingInfo.routingDecision.intentBasedNarrowed,
      );
    }
    metrics.recordRetrievalQuality(initialResult.retrievalStats?.topKAvg ?? initialResult.retrievalStats?.avgScore ?? 0);
    let result: PipelineResult = initialResult;
    let citations: Citation[] = initialCitations;

    debug.routing = routingInfo;
    debug.searchQueries = firstPassSearchQueries.length > 0 ? firstPassSearchQueries : undefined;
    const retrievalCounts = {
      hotel: initialResult.vertical === 'hotel' ? (initialResult.retrievalStats?.itemCount ?? 0) : 0,
      flight: initialResult.vertical === 'flight' ? (initialResult.retrievalStats?.itemCount ?? 0) : 0,
      product: initialResult.vertical === 'product' ? (initialResult.retrievalStats?.itemCount ?? 0) : 0,
      movie: initialResult.vertical === 'movie' ? (initialResult.retrievalStats?.itemCount ?? 0) : 0,
    };
    debug.automatedEvalScores = runAutomatedEvals({
      originalQuery: ctx.message ?? '',
      rewrittenQuery: rewrittenPrompt,
      extractedFilters: extractedFilters as Record<string, unknown> | undefined,
      primaryRoute: routingInfo?.routingDecision?.primary ?? undefined,
      sourcesUsed: routingInfo?.routingDecision?.sourcesUsed,
      retrievalCounts,
    });
    if (!debug.interpretationSummary) {
      debug.interpretationSummary = 'Searching for ' + (rewrittenPrompt || ctx.message).trim() + '.';
    }

    const firstPassDuration = Date.now() - retrievalStarted;
    const baseItemsCount =
      result.retrievalStats?.itemCount ?? getResultItemsCount(result);
    const maxItemsHint = result.retrievalStats?.maxItems ?? 20;
    const avgScore = result.retrievalStats?.avgScore ?? 0;

    let retrievalQuality = classifyRetrievalQuality(baseItemsCount, maxItemsHint);

    if (
      retrievalQuality === 'weak' &&
      baseItemsCount > 0 &&
      baseItemsCount <= 3 &&
      avgScore >= 0.7
    ) {
      retrievalQuality = 'good';
    }

    logger.info('runPipeline:firstPass:done', {
      mode,
      vertical: result.vertical,
      durationMs: firstPassDuration,
      items: baseItemsCount,
      retrievalQuality,
    });

    if (retrievalQuality === 'weak' && result.vertical !== 'other') {
      logger.info('runPipeline:retrieval_weak_fallback_to_other', {
        mode,
        originalVertical: result.vertical,
        items: baseItemsCount,
      });

      const fallbackOverview = await perplexityOverview(rewrittenPrompt);
      const fallbackCitations: Citation[] = (fallbackOverview.citations ?? []).map((c: PerplexityCitation) => ({
        id: c.id,
        url: c.url,
        title: c.title,
        snippet: c.snippet,
        date: c.date,
        last_updated: c.last_updated,
      }));
      // Point 7: Reframe so user sees why web overview is there (avoid contradiction with cards).
      const relaxHint = '';
      const fallbackReframe =
        `We found few structured options. ${relaxHint}Here's a broader view from the web:\n\n`;
      result = {
        ...result,
        vertical: 'other',
        intent: 'browse',
        summary:
          (result.summary ?? '') +
          '\n\n---\n\n' +
          fallbackReframe +
          fallbackOverview.summary,
        citations: [...(result.citations ?? []), ...fallbackCitations],
        retrievalStats: {
          vertical: 'other',
          itemCount: baseItemsCount,
          maxItems: undefined,
          quality: 'fallback_other',
        },
      } as PipelineResult;
      citations = result.citations ?? citations;
      retrievalQuality = 'weak';
    }

    if (mode === 'deep') {
      if (result.vertical === 'other') {
        const extraStarted = Date.now();
        const extraQuery = `${rewrittenPrompt} key facts, pros and cons, timeline`;
        const extraOverview = await perplexityOverview(extraQuery);
        const extraDuration = Date.now() - extraStarted;

        logger.info('runPipeline:other_extra_wave:done', {
          durationMs: extraDuration,
        });

        const extraCitations: Citation[] = (extraOverview.citations ?? []).map((c: PerplexityCitation) => ({
          id: c.id,
          url: c.url,
          title: c.title,
          snippet: c.snippet,
          date: c.date,
          last_updated: c.last_updated,
        }));
        result = {
          ...result,
          summary:
            (result.summary ?? '') +
            '\n\nAdditional perspective from the web:\n' +
            extraOverview.summary,
          citations: [...(result.citations ?? []), ...extraCitations],
        } as PipelineResult;
        citations = result.citations ?? citations;
      }

      const plannerStarted = Date.now();
      const decision = await planResearchStep({
        userQuery: ctx.message,
        rewrittenQuery: rewrittenPrompt,
        vertical: primaryVertical,
        summaryDraft: result.summary ?? '',
        mode: 'deep',
      });
      const plannerDuration = Date.now() - plannerStarted;
      debug.deepPlanner =
        decision.type === 'extra_research'
          ? { decision: decision.type, newQuery: decision.newQuery }
          : { decision: decision.type };
      const decisionExtras = decision as { confidence?: number; newQuery?: string };
      logger.info('runPipeline:planner:done', {
        decision: decision.type,
        confidence: decisionExtras.confidence,
        hasNewQuery: !!decisionExtras.newQuery,
        durationMs: plannerDuration,
      });

      // Deep mode: alternate phrasing, extra retrieval. Build minimal plan only for runVerticalSingle.
      if (result.vertical !== 'other') {
        const rewrites = await getRewrittenQueriesForMode(ctx, primaryVertical);
        if (rewrites.length > 1) {
          const extraStarted = Date.now();
          const extraCitations: Citation[] = [];
          let mergedSummary = result.summary ?? '';

          for (const rq of rewrites.slice(1)) {
            const planWithRewrite = { vertical: primaryVertical, intent: 'browse' as const, rewrittenPrompt: rq } as VerticalPlan;
            const extraResult = await runVerticalSingle(planWithRewrite, depsWithCacheKey, ctx);
            extraCitations.push(...(extraResult.citations ?? []));
            mergedSummary += '\n\nAdditional angle:\n' + (extraResult.summary ?? '');
          }

          const extraDuration = Date.now() - extraStarted;
          logger.info('runPipeline:deep_fanout:done', {
            vertical: primaryVertical,
            rewritesCount: rewrites.length,
            durationMs: extraDuration,
          });

          result = { ...result, summary: mergedSummary } as PipelineResult;
          citations = [...citations, ...extraCitations];
        }
      }

      // Extra research: new query phrasing; run primary vertical only and merge.
      const extraResearch = decision.type === 'extra_research' ? decision as { type: 'extra_research'; newQuery?: string; confidence?: number } : null;
      if (
        extraResearch &&
        extraResearch.newQuery &&
        (extraResearch.confidence ?? 0) >= 0.5
      ) {
        const extraStarted = Date.now();
        const planWithNewQuery = { vertical: primaryVertical, intent: 'browse' as const, rewrittenPrompt: extraResearch.newQuery } as VerticalPlan;
        const extraResult = await runVerticalSingle(planWithNewQuery, depsWithCacheKey, ctx);
        const extraDuration = Date.now() - extraStarted;
        logger.info('runPipeline:extraResearch:done', {
          vertical: primaryVertical,
          durationMs: extraDuration,
          items: extraResult.retrievalStats?.itemCount ?? getResultItemsCount(extraResult),
        });

        result = {
          ...result,
          summary:
            (result.summary ?? '') + '\n\nAdditional findings:\n' + (extraResult.summary ?? ''),
        } as PipelineResult;
        citations = [...citations, ...(extraResult.citations ?? [])];
      }

      const critiqueStarted = Date.now();
      const critiqueResult = await critiqueAndRefineSummary({
        userQuery: ctx.message,
        summary: result.summary ?? '',
        citations: citations.map((c) => ({
          id: c.id,
          snippet: c.snippet ?? c.title ?? '',
        })),
        allowReplan: true,
      });
      const critiqueDuration = Date.now() - critiqueStarted;
      logger.info('runPipeline:critique:done', {
        durationMs: critiqueDuration,
        needsReplan: critiqueResult.needsReplan ?? false,
        confidence: critiqueResult.confidence,
      });

      // Point 6: When critique signals wrong domain / misunderstanding with high confidence, replan and run with suggested query.
      const shouldReplan =
        critiqueResult.needsReplan === true &&
        !!critiqueResult.suggestedQuery?.trim() &&
        (critiqueResult.confidence ?? 0) >= 0.6;

      if (shouldReplan) {
        const replanCtx: QueryContext = {
          ...ctx,
          message: critiqueResult.suggestedQuery!.trim(),
          history: [...(ctx.history ?? []), ctx.message],
        };
        const replanStarted = Date.now();
        const rewriteResultReplan = await rewriteQuery(replanCtx);
        const rewrittenPromptReplan = rewriteResultReplan.rewrittenPrompt;
        const subQueriesReplan = await decomposeIntoSubQueries(replanCtx, rewrittenPromptReplan);
        let extractedFiltersReplan: ExtractedFilters = {};
        try {
          extractedFiltersReplan = await extractFilters(replanCtx, rewrittenPromptReplan);
        } catch (_) {
          // use empty; retrieval will use defaults
        }
        const replanCacheKey = makePlanCacheKey(replanCtx);
        const depsReplan = { ...deps, retrievedContentCacheKey: replanCacheKey };
        const { result: replanResult, citations: replanCitations, searchQueries: replanSearchQueries } =
          await runCentralRetrieval(rewrittenPromptReplan, subQueriesReplan, depsReplan, replanCtx, extractedFiltersReplan);
        if (replanSearchQueries.length > 0) {
          debug.searchQueries = replanSearchQueries;
          debug.interpretationSummary = 'Searching for ' + (rewrittenPromptReplan || '').trim() + '.';
        }
        const replanDuration = Date.now() - replanStarted;
        logger.info('runPipeline:deepReplan:done', {
          durationMs: replanDuration,
          suggestedQuery: critiqueResult.suggestedQuery,
        });
        result = {
          ...replanResult,
          suggestedQuery: critiqueResult.suggestedQuery,
          suggestedQueryUsed: true,
        } as PipelineResult;
        citations = replanCitations;
      } else {
        result = {
          ...result,
          summary: critiqueResult.refinedSummary,
        } as PipelineResult;
        if (critiqueResult.suggestedQuery) {
          result = {
            ...result,
            suggestedQuery: critiqueResult.suggestedQuery,
            suggestedQueryUsed: false,
          } as PipelineResult;
        }
      }
      debug.deepRefined = true;
    } else {
      debug.deepRefined = false;
    }

    const itemsCount = getResultItemsCount(result);
    const finalQuality: 'good' | 'weak' | 'fallback_other' =
      result.vertical === 'other' && retrievalQuality === 'weak'
        ? 'fallback_other'
        : retrievalQuality;

    const maxItemsUsed = result.retrievalStats?.maxItems ?? maxItemsHint;

    debug.retrieval = {
      vertical: result.vertical,
      items: itemsCount,
      snippets: citations.length,
      quality: finalQuality,
      maxItems: maxItemsUsed,
    } as DebugInfo['retrieval'];

    const totalDuration = Date.now() - startedAt;
    logger.info('runPipeline:success', {
      mode,
      vertical: result.vertical,
      totalDurationMs: totalDuration,
    });

    const resultWithUi = attachUiDecision(result, ctx.message);
    const summary = resultWithUi.summary ?? '';
    const firstParagraph = summary.split(/\n\n+/)[0]?.trim() ?? '';
    const definitionBlurb =
      firstParagraph.length > 0 && firstParagraph.length <= 600 ? firstParagraph : undefined;
    // Scannable references: "<index>. <Title> – <domain>[ – Updated <YYYY-MM-DD>]"
    const referencesSection =
      citations.length > 0
        ? citations
            .map((c, i) => {
              const domain = (() => {
                try {
                  return new URL(c.url).hostname.replace(/^www\./, '');
                } catch {
                  return c.url.replace(/^https?:\/\//, '').split('/')[0] ?? '';
                }
              })();
              const title = c.title?.trim() || 'Source';
              const rawDate = c.date ?? c.last_updated;
              let dateSuffix = '';
              if (rawDate && typeof rawDate === 'string') {
                try {
                  const d = new Date(rawDate);
                  if (!Number.isNaN(d.getTime())) {
                    const y = d.getFullYear();
                    const m = String(d.getMonth() + 1).padStart(2, '0');
                    const day = String(d.getDate()).padStart(2, '0');
                    dateSuffix = ` – Updated ${y}-${m}-${day}`;
                  }
                } catch {
                  dateSuffix = ` – Updated ${rawDate}`;
                }
              }
              return `${i + 1}. ${title} – ${domain}${dateSuffix}`;
            })
            .join('\n')
        : undefined;
    const suggestedQuery = (resultWithUi as any).suggestedQuery ?? undefined;
    const suggestedQueryUsed = (resultWithUi as any).suggestedQueryUsed === true;
    const followUpSuggestions = await buildDynamicFollowUps(resultWithUi, ctx);
    const finalPayload: PipelineResult = {
      ...resultWithUi,
      debug,
      citations,
      answerGeneratedAt: new Date().toISOString(),
      ...(definitionBlurb && { definitionBlurb }),
      ...(referencesSection && { referencesSection }),
      ...(resultWithUi.bridgeLinks && resultWithUi.bridgeLinks.length > 0 && { bridgeLinks: resultWithUi.bridgeLinks }),
      ...(suggestedQuery && { suggestedQuery }),
      ...(suggestedQueryUsed && { suggestedQueryUsed }),
      ...(followUpSuggestions.length > 0 && { followUpSuggestions }),
    };
    if (mode === 'quick') {
      await setCache(cacheKey, finalPayload, PIPELINE_CACHE_TTL_SECONDS);
      logger.info('pipeline:cache_set', {
        mode,
        message: truncatedMessage,
      });
    }

    // Persist conversation thread (Perplexity-style).
    if (ctx.sessionId) {
      try {
        await updateSession(ctx.sessionId, {
          appendTurn: { query: ctx.message, answer: resultWithUi.summary ?? '' },
        });
      } catch (sessionErr) {
        logger.warn('runPipeline:updateSession failed', {
          sessionId: ctx.sessionId,
          err: sessionErr instanceof Error ? sessionErr.message : String(sessionErr),
        });
      }
    }

    if (
      shouldSampleForEval({
        routingConfidence: finalPayload.debug?.routing?.routingDecision?.confidence,
        primaryRoute:
          finalPayload.debug?.routing?.routingDecision?.primary ??
          finalPayload.debug?.routing?.chosen ??
          null,
        automatedEvalScores: finalPayload.debug?.automatedEvalScores,
      })
    ) {
      submitForHumanReview({
        traceId: trace.traceId,
        trace,
        originalQuery: ctx.message,
        rewrittenQuery: rewrittenPrompt,
        searchQueries: finalPayload.debug?.searchQueries,
        routing: finalPayload.debug?.routing,
        summary: finalPayload.summary,
      });
    }
    return finalPayload;
  } catch (err) {
    const totalDuration = Date.now() - startedAt;
    logger.error('runPipeline:error', {
      mode,
      error: err instanceof Error ? err.message : String(err),
      totalDurationMs: totalDuration,
    });
    throw err;
  } finally {
    finishTrace(trace);
    metrics.finish(pipelineStartedAt);
  }
}
