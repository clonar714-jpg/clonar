// src/services/retrieval-router.ts
// Perplexity-style central retrieval router: route at retrieval-time by sub-query content.
// Retrieval routing is content-based only (subQuery + keywords + profile similarity). We ignore plan.vertical,
// plan.candidates, and intent. Web retriever is always included as a safety net.
// This guarantees robustness even if query understanding is wrong. Quality: composite rerank (no LLM), smart dedupe, budget caps, caching.
import crypto from 'crypto';
import type { QueryContext } from '@/types/core';
import type { VerticalPlan } from '@/types/verticals';
import type { HotelFilters, FlightFilters, ProductFilters, MovieTicketFilters } from '@/types/verticals';
import type { HotelRetriever } from './providers/hotels/hotel-retriever';
import type { FlightRetriever } from './providers/flights/flight-retriever';
import type { ProductRetriever } from './providers/catalog/product-retriever';
import type { MovieRetriever } from './providers/movies/movie-retriever';
import { perplexityOverview } from './providers/web/perplexity-web';
import { getCache, setCache } from './cache';
import { logger } from './logger';
import { tokenize, cosineSimilarity, type Embedder } from './providers/retrieval-vector-utils';

/** Deps for the router (same shape as OrchestratorDeps; avoid circular import). */
export interface RetrievalRouterDeps {
  productRetriever: ProductRetriever;
  hotelRetriever: HotelRetriever;
  flightRetriever: FlightRetriever;
  movieRetriever: MovieRetriever;
  /** Optional: when set, routing blends keyword/profile scores with semantic (query vs vertical profile embeddings). */
  embedder?: Embedder;
  /** Optional: when set, chunks are reranked by this before capping (e.g. lightweight cross-encoder or semantic). */
  passageReranker?: PassageReranker;
}

export type RetrievalSource = 'hotel' | 'flight' | 'product' | 'movie' | 'web';

/** Unified chunk from any retriever for merge + global rerank. */
export interface RetrievedChunk {
  id: string;
  url: string;
  title?: string;
  text: string;
  score: number;
  source: RetrievalSource;
  /** Optional date for recency boost (e.g. web citations). */
  date?: string;
  /** Raw item for bySource (Hotel, Product, etc.) when applicable. */
  rawItem?: unknown;
}

/** Rerank merged chunks by relevance to the query (e.g. semantic or cross-encoder). */
export interface PassageReranker {
  rerank(query: string, chunks: RetrievedChunk[]): Promise<RetrievedChunk[]>;
}

// ---------- Configurable caps (quality: reduce noise, keep synthesis cheap) ----------
const MAX_CHUNKS_PER_RETRIEVER_PER_SUBQUERY = 15;
const MAX_TOTAL_CHUNKS = 50;
const CACHE_TTL_WEB_SECONDS = 10 * 60;
const CACHE_TTL_STRUCTURED_SECONDS = 30 * 60;
const DEBUG_RETRIEVAL = process.env.DEBUG_RETRIEVAL === '1' || process.env.DEBUG_RETRIEVAL === 'true';

/** Cache key for retrieval by (subQuery, source); deterministic, no PII in key. */
function retrievalCacheKey(subQuery: string, source: RetrievalSource): string {
  return `retrieval:${source}:${crypto.createHash('sha256').update(subQuery.trim().toLowerCase()).digest('hex').slice(0, 32)}`;
}

export interface RouteAndRetrieveResult {
  chunks: RetrievedChunk[];
  bySource: {
    hotel?: import('./providers/hotels/hotel-provider').Hotel[];
    flight?: import('./providers/flights/flight-provider').Flight[];
    product?: import('./providers/catalog/catalog-provider').Product[];
    movie?: import('./providers/movies/movie-provider').MovieShowtime[];
  };
  searchQueries: string[];
  /** Intent/confidence-based routing decision for evals and metrics. */
  routingDecision?: RoutingDecision;
}

function formatDate(d: Date): string {
  return d.toISOString().slice(0, 10);
}
function addDays(d: Date, days: number): Date {
  const out = new Date(d);
  out.setDate(out.getDate() + days);
  return out;
}

/** Term-vector cosine similarity (no LLM, no network). Used for rerank and profile routing. */
function termVectorCosine(tokensA: string[], tokensB: string[]): number {
  const vecA = new Map<string, number>();
  const vecB = new Map<string, number>();
  for (const t of tokensA) vecA.set(t, (vecA.get(t) ?? 0) + 1);
  for (const t of tokensB) vecB.set(t, (vecB.get(t) ?? 0) + 1);
  let dot = 0, na = 0, nb = 0;
  const allTerms = new Set([...vecA.keys(), ...vecB.keys()]);
  for (const t of allTerms) {
    const a = vecA.get(t) ?? 0, b = vecB.get(t) ?? 0;
    dot += a * b;
    na += a * a;
    nb += b * b;
  }
  if (na === 0 || nb === 0) return 0;
  return dot / (Math.sqrt(na) * Math.sqrt(nb));
}

/** Normalize text for smart dedupe: lowercase, strip punctuation. */
function normalizeForDedupe(text: string): string {
  return text
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, ' ')
    .replace(/\s+/g, ' ')
    .trim();
}

/** Jaccard similarity on token sets. */
function jaccardTokens(tokensA: string[], tokensB: string[]): number {
  const setA = new Set(tokensA);
  const setB = new Set(tokensB);
  let intersection = 0;
  for (const t of setA) if (setB.has(t)) intersection++;
  const union = setA.size + setB.size - intersection;
  return union === 0 ? 0 : intersection / union;
}

/** Quality heuristic for dedupe: prefer longer text, higher score, richer metadata. */
function chunkQuality(c: RetrievedChunk): number {
  const len = (c.text?.length ?? 0) + (c.title?.length ?? 0) * 2;
  const meta = (c.title ? 5 : 0) + (c.date ? 3 : 0);
  return len * 0.01 + (c.score ?? 0) * 10 + meta;
}

/** Profile strings per retriever for optional similarity-based routing (no embedder, no network). */
const RETRIEVER_PROFILES: Record<RetrievalSource, string> = {
  hotel: 'hotel hotels stay accommodation booking room rooms wifi pool resort inn motel',
  flight: 'flight flights fly fare airline airport depart destination origin',
  product: 'buy price review product products shop shopping brand deal',
  movie: 'movie movies showtime showtimes cinema theater theatre ticket tickets',
  web: 'search web general information',
};

/** Per-vertical scores from keyword rules + profile similarity (no embedder). */
function getKeywordScores(subQuery: string): Record<RetrievalSource, number> {
  const lower = subQuery.toLowerCase().trim();
  const scores: Record<RetrievalSource, number> = {
    hotel: 0,
    flight: 0,
    product: 0,
    movie: 0,
    web: 0,
  };

  if (/\b(hotel|hotels|stay|stays|booking|accommodation|room|rooms|wifi|pool|resort|inn|motel)\b/.test(lower)) {
    scores.hotel = 1.0;
  }
  if (/\b(flight|flights|fly|flying|fare|airline|airport|depart|destination|origin)\b/.test(lower)) {
    scores.flight = 1.0;
  }
  if (/\b(buy|price|prices|review|reviews|product|products|shop|shopping|brand|deal)\b/.test(lower)) {
    scores.product = 1.0;
  }
  if (/\b(movie|movies|showtime|showtimes|cinema|theater|theatre|ticket|tickets)\b/.test(lower)) {
    scores.movie = 1.0;
  }

  const queryTokens = tokenize(subQuery);
  const PROFILE_THRESHOLD = 0.18;
  for (const source of VERTICAL_SOURCES) {
    if (scores[source] > 0) continue;
    const profileTokens = tokenize(RETRIEVER_PROFILES[source]);
    const sim = termVectorCosine(queryTokens, profileTokens);
    if (sim > PROFILE_THRESHOLD) scores[source] = Math.max(scores[source], sim);
  }
  scores.web = 1.0; // web always available
  return scores;
}

/** Derive sources, primary, confidence from score map. */
function scoresToRouting(scores: Record<RetrievalSource, number>): { sources: RetrievalSource[]; primary: RetrievalSource | null; confidence: number } {
  const verticalScores = VERTICAL_SOURCES.map((s) => ({ source: s, score: scores[s] })).filter((x) => x.score > 0);
  verticalScores.sort((a, b) => b.score - a.score);
  const top = verticalScores[0];
  const second = verticalScores[1];
  const primary: RetrievalSource | null =
    top && top.score >= 0.5 && (!second || second.score <= 0.3) ? top.source : null;
  const confidence = primary ? top!.score : (top ? Math.min(0.5, top.score) : 0);
  const selected = new Set<RetrievalSource>(VERTICAL_SOURCES.filter((s) => scores[s] > 0));
  selected.add('web');
  return { sources: Array.from(selected), primary, confidence };
}

/** Retrieval routing is content-based, not plan-based. Uses only subQuery text + keyword rules + profile similarity. No LLM. Overlap allowed. */
export function whichRetrievers(subQuery: string): RetrievalSource[] {
  return scoresToRouting(getKeywordScores(subQuery)).sources;
}

/** Per-vertical sources (keyword + profile). */
const VERTICAL_SOURCES: readonly RetrievalSource[] = ['hotel', 'flight', 'product', 'movie'];

export interface RoutingDecision {
  /** Sources actually used (after intent-based narrowing when confidence high). */
  sourcesUsed: RetrievalSource[];
  /** Single dominant vertical when confidence is high; null when ambiguous. */
  primary: RetrievalSource | null;
  /** 0–1: high = one clear intent, low = multiple or weak match. */
  confidence: number;
  /** True when routing was narrowed to primary + web due to high confidence. */
  intentBasedNarrowed: boolean;
  /** Human-readable reason for this routing (for debugging and evals). */
  rationale?: string;
}

/** Semantic weight for routing when embedder is set (env ROUTING_SEMANTIC_WEIGHT, default 0.4). Keyword gets 1 - weight. */
function getRoutingSemanticWeight(): number {
  const v = process.env.ROUTING_SEMANTIC_WEIGHT;
  if (v == null || v === '') return 0.4;
  const n = parseFloat(v);
  return Number.isFinite(n) && n >= 0 && n <= 1 ? n : 0.4;
}

let cachedProfileEmbeddings: Record<RetrievalSource, number[]> | null = null;

/** Returns routing scores (keyword + optional semantic blend when deps.embedder is set). */
async function getRoutingScoresAsync(
  deps: RetrievalRouterDeps,
  subQuery: string,
): Promise<Record<RetrievalSource, number>> {
  const keywordScores = getKeywordScores(subQuery);
  if (!deps.embedder) return keywordScores;

  const weight = getRoutingSemanticWeight();
  if (cachedProfileEmbeddings == null) {
    const entries = await Promise.all(
      (['hotel', 'flight', 'product', 'movie', 'web'] as RetrievalSource[]).map(async (s) => {
        const emb = await deps.embedder!.embed(RETRIEVER_PROFILES[s]);
        return [s, emb] as const;
      }),
    );
    cachedProfileEmbeddings = Object.fromEntries(entries) as Record<RetrievalSource, number[]>;
  }

  const queryEmb = await deps.embedder!.embed(subQuery.trim() || ' ');
  const semanticScores: Record<RetrievalSource, number> = {
    hotel: 0,
    flight: 0,
    product: 0,
    movie: 0,
    web: 0,
  };
  for (const s of ['hotel', 'flight', 'product', 'movie', 'web'] as RetrievalSource[]) {
    const sim = cosineSimilarity(queryEmb, cachedProfileEmbeddings[s]);
    semanticScores[s] = Math.max(0, sim);
  }

  const blended: Record<RetrievalSource, number> = {
    hotel: 0,
    flight: 0,
    product: 0,
    movie: 0,
    web: 0,
  };
  for (const s of ['hotel', 'flight', 'product', 'movie', 'web'] as RetrievalSource[]) {
    blended[s] = (1 - weight) * keywordScores[s] + weight * semanticScores[s];
  }
  return blended;
}

/** Returns sources plus confidence and primary for intent-based / confidence-based routing. */
export function whichRetrieversWithConfidence(subQuery: string): { sources: RetrievalSource[]; primary: RetrievalSource | null; confidence: number } {
  return scoresToRouting(getKeywordScores(subQuery));
}

/** Confidence threshold for intent-based narrowing (env ROUTING_CONFIDENCE_THRESHOLD, default 0.6). Above this we use primary + web only. */
function getRoutingConfidenceThreshold(): number {
  const v = process.env.ROUTING_CONFIDENCE_THRESHOLD;
  if (v == null || v === '') return 0.6;
  const n = parseFloat(v);
  return Number.isFinite(n) && n >= 0 && n <= 1 ? n : 0.6;
}

/** Minimal default filters when plan does not have that vertical's filters. */
function defaultHotelFilters(subQuery: string): HotelFilters & { rewrittenQuery: string } {
  const now = new Date();
  return {
    destination: 'unknown',
    checkIn: formatDate(now),
    checkOut: formatDate(addDays(now, 1)),
    guests: 2,
    rewrittenQuery: subQuery,
  };
}
function defaultFlightFilters(subQuery: string): FlightFilters & { rewrittenQuery: string } {
  const now = new Date();
  return {
    origin: '',
    destination: 'unknown',
    departDate: formatDate(now),
    adults: 1,
    rewrittenQuery: subQuery,
  };
}
function defaultProductFilters(subQuery: string): ProductFilters & { query: string; rewrittenQuery: string } {
  return { query: subQuery, rewrittenQuery: subQuery };
}
function defaultMovieFilters(subQuery: string): MovieTicketFilters & { rewrittenQuery: string } {
  const now = new Date();
  return { city: 'unknown', date: formatDate(now), tickets: 2, rewrittenQuery: subQuery };
}

/** Apply per-retriever per-subQuery cap: keep top N by score to reduce noise. */
function capChunks(chunks: RetrievedChunk[], max: number): RetrievedChunk[] {
  if (chunks.length <= max) return chunks;
  return [...chunks].sort((a, b) => b.score - a.score).slice(0, max);
}

/** Plan may have filters for one primary vertical; we use them when calling that retriever, else defaults. Extracted filters (destination, dates, amenities, etc.) come from plan; preferences are in rewrittenQuery. */
function getHotelFilters(plan: VerticalPlan, subQuery: string): HotelFilters & { rewrittenQuery: string } {
  const base = (plan as VerticalPlan & { hotel?: HotelFilters }).hotel
    ? { ...(plan as VerticalPlan & { hotel: HotelFilters }).hotel, rewrittenQuery: subQuery }
    : defaultHotelFilters(subQuery);
  return base;
}
function getFlightFilters(plan: VerticalPlan, subQuery: string): FlightFilters & { rewrittenQuery: string } {
  const base = (plan as VerticalPlan & { flight?: FlightFilters }).flight
    ? { ...(plan as VerticalPlan & { flight: FlightFilters }).flight!, rewrittenQuery: subQuery }
    : defaultFlightFilters(subQuery);
  return base;
}
function getProductFilters(plan: VerticalPlan, subQuery: string): ProductFilters & { rewrittenQuery: string } {
  const base = (plan as VerticalPlan & { product?: ProductFilters }).product
    ? { ...(plan as VerticalPlan & { product: ProductFilters }).product!, rewrittenQuery: subQuery }
    : defaultProductFilters(subQuery);
  return base;
}
function getMovieFilters(plan: VerticalPlan, subQuery: string): MovieTicketFilters & { rewrittenQuery: string } {
  const planMovie = (plan as VerticalPlan & { movie?: MovieTicketFilters }).movie;
  return planMovie ? { ...planMovie, rewrittenQuery: subQuery } : defaultMovieFilters(subQuery);
}

/** Smart dedupe: normalize text, then drop near-duplicates (Jaccard > 0.85) keeping higher-quality chunk. */
function smartDedupeChunks(chunks: RetrievedChunk[]): { kept: RetrievedChunk[]; droppedCount: number } {
  const byId = new Map<string, RetrievedChunk>();
  for (const c of chunks) {
    const key = c.id || `${c.url}|${c.title ?? ''}`;
    const existing = byId.get(key);
    if (!existing || chunkQuality(c) > chunkQuality(existing)) byId.set(key, c);
  }
  const afterId = Array.from(byId.values());
  const kept: RetrievedChunk[] = [];
  let droppedCount = 0;
  const SIMILARITY_THRESHOLD = 0.85;
  for (const c of afterId) {
    const normText = normalizeForDedupe(c.text);
    const tokensC = tokenize(normText);
    let isDuplicate = false;
    for (const k of kept) {
      const tokensK = tokenize(normalizeForDedupe(k.text));
      if (jaccardTokens(tokensC, tokensK) >= SIMILARITY_THRESHOLD) {
        if (chunkQuality(c) <= chunkQuality(k)) {
          isDuplicate = true;
          droppedCount++;
          break;
        }
        const idx = kept.findIndex((x) => x === k);
        if (idx >= 0) kept.splice(idx, 1);
        droppedCount++;
        break;
      }
    }
    if (!isDuplicate) kept.push(c);
  }
  return { kept, droppedCount };
}

/** Domain from URL for repetition penalty (hostname). */
function domainFromUrl(url: string): string {
  try {
    return new URL(url).hostname.replace(/^www\./, '') || url.slice(0, 50);
  } catch {
    return url.slice(0, 50);
  }
}

/** Parse date string to timestamp for recency; return 0 if unparseable. */
function parseDateToTime(dateStr: string | undefined): number {
  if (!dateStr) return 0;
  const t = Date.parse(dateStr);
  return Number.isNaN(t) ? 0 : t;
}

/**
 * Composite rerank (no LLM): base score + text similarity to best-matching subQuery + recency boost - domain penalty.
 * Improves relevance without adding cost.
 */
export function rerankChunks(chunks: RetrievedChunk[], subQueries: string[]): RetrievedChunk[] {
  const queryTokenLists = subQueries.map((q) => tokenize(q));
  const now = Date.now();
  const ONE_YEAR_MS = 365 * 24 * 60 * 60 * 1000;
  const domainCount = new Map<string, number>();
  for (const c of chunks) {
    const d = domainFromUrl(c.url);
    domainCount.set(d, (domainCount.get(d) ?? 0) + 1);
  }

  const scored = chunks.map((c) => {
    let composite = c.score;

    const chunkTokens = tokenize(c.text + ' ' + (c.title ?? ''));
    let bestSim = 0;
    for (const qt of queryTokenLists) {
      const sim = termVectorCosine(qt, chunkTokens);
      if (sim > bestSim) bestSim = sim;
    }
    composite += bestSim * 0.4;

    if (c.date && c.source === 'web') {
      const t = parseDateToTime(c.date);
      if (t > 0) {
        const ageMs = now - t;
        if (ageMs < ONE_YEAR_MS) composite += 0.1 * (1 - ageMs / ONE_YEAR_MS);
      }
    }

    const count = domainCount.get(domainFromUrl(c.url)) ?? 0;
    if (count > 2) composite -= 0.15 * (count - 2);

    return { chunk: c, composite };
  });

  scored.sort((a, b) => b.composite - a.composite);
  return scored.map((s) => s.chunk);
}

/**
 * Central retrieval router: for each sub-query, select retrievers by content only (whichRetrievers).
 * Plan is used only for filter hints (e.g. destination, dates), NOT for which retrievers run.
 * Perplexity-style: routing at retrieval-time; no vertical ownership of retrieval.
 */
export async function routeAndRetrieve(
  subQueries: string[],
  deps: RetrievalRouterDeps,
  ctx: QueryContext,
  plan: VerticalPlan,
): Promise<RouteAndRetrieveResult> {
  const tasks: Array<{ subQuery: string; source: RetrievalSource }> = [];
  const threshold = getRoutingConfidenceThreshold();
  const decisions: { primary: RetrievalSource | null; confidence: number; narrowed: boolean }[] = [];
  const allSourcesUsed = new Set<RetrievalSource>();

  for (const q of subQueries) {
    if (!q?.trim()) continue;
    const scores = await getRoutingScoresAsync(deps, q);
    const { sources, primary, confidence } = scoresToRouting(scores);
    const narrowed = confidence >= threshold && primary != null && primary !== 'web';
    const sourcesToUse = narrowed ? ([primary, 'web'] as RetrievalSource[]) : sources;
    decisions.push({ primary, confidence, narrowed });
    for (const source of sourcesToUse) {
      tasks.push({ subQuery: q.trim(), source });
      allSourcesUsed.add(source);
    }
  }

  const avgConfidence = decisions.length ? decisions.reduce((a, d) => a + d.confidence, 0) / decisions.length : 0;
  const primaryUsed = decisions.find((d) => d.primary != null)?.primary ?? null;
  const intentBasedNarrowed = decisions.some((d) => d.narrowed);
  const sourcesList = Array.from(allSourcesUsed);
  const rationale =
    intentBasedNarrowed && primaryUsed && primaryUsed !== 'web'
      ? `Primary ${primaryUsed} (confidence ${avgConfidence.toFixed(2)} ≥ ${threshold}); narrowed to ${primaryUsed} + web.`
      : `Multi-vertical (confidence ${avgConfidence.toFixed(2)} < ${threshold}); used ${sourcesList.join(', ')}.`;
  const routingDecision: RoutingDecision = {
    sourcesUsed: sourcesList,
    primary: primaryUsed,
    confidence: avgConfidence,
    intentBasedNarrowed,
    rationale,
  };

  const allChunks: RetrievedChunk[] = [];
  const bySource: RouteAndRetrieveResult['bySource'] = {};
  const hotelDedup = new Set<string>();
  const flightDedup = new Set<string>();
  const productDedup = new Set<string>();
  const movieDedup = new Set<string>();

  const runOne = async (
    subQuery: string,
    source: RetrievalSource,
  ): Promise<{ chunks: RetrievedChunk[]; bySource: Partial<RouteAndRetrieveResult['bySource']> }> => {
    const cacheKey = retrievalCacheKey(subQuery, source);
    const ttl = source === 'web' ? CACHE_TTL_WEB_SECONDS : CACHE_TTL_STRUCTURED_SECONDS;
    const cached = await getCache<{ chunks: RetrievedChunk[]; bySource: Partial<RouteAndRetrieveResult['bySource']> }>(cacheKey);
    if (cached != null) {
      if (DEBUG_RETRIEVAL) logger.info('retrieval-router:cache_hit', { subQuery: subQuery.slice(0, 60), source, chunkCount: cached.chunks.length });
      return cached;
    }

    try {
      if (source === 'hotel') {
        const filters = getHotelFilters(plan, subQuery);
        const { hotels, snippets } = await deps.hotelRetriever.searchHotels(filters);
        let chunks: RetrievedChunk[] = snippets.map((s) => ({
          id: s.id,
          url: s.url,
          title: s.title,
          text: s.text,
          score: s.score ?? 0,
          source: 'hotel',
        }));
        chunks = capChunks(chunks, MAX_CHUNKS_PER_RETRIEVER_PER_SUBQUERY);
        const hotelsToAdd = hotels.filter((h) => {
          const key = (h as { id?: string; name?: string }).id ?? (h as { name?: string }).name ?? '';
          if (hotelDedup.has(key)) return false;
          hotelDedup.add(key);
          return true;
        });
        const out = { chunks, bySource: { hotel: hotelsToAdd } as Partial<RouteAndRetrieveResult['bySource']> };
        await setCache(cacheKey, out, ttl);
        return out;
      }
      if (source === 'flight') {
        const filters = getFlightFilters(plan, subQuery);
        const { flights, snippets } = await deps.flightRetriever.searchFlights(filters);
        let chunks: RetrievedChunk[] = (snippets ?? []).map((s) => ({
          id: s.id,
          url: s.url,
          title: s.title,
          text: s.text,
          score: s.score ?? 0,
          source: 'flight',
        }));
        chunks = capChunks(chunks, MAX_CHUNKS_PER_RETRIEVER_PER_SUBQUERY);
        const flightsToAdd = (flights ?? []).filter((f) => {
          const key = (f as { id?: string }).id ?? JSON.stringify(f);
          if (flightDedup.has(key)) return false;
          flightDedup.add(key);
          return true;
        });
        const out = { chunks, bySource: { flight: flightsToAdd } as Partial<RouteAndRetrieveResult['bySource']> };
        await setCache(cacheKey, out, ttl);
        return out;
      }
      if (source === 'product') {
        const filters = getProductFilters(plan, subQuery);
        const { products, snippets } = await deps.productRetriever.searchProducts(filters);
        let chunks: RetrievedChunk[] = (snippets ?? []).map((s) => ({
          id: s.id,
          url: s.url,
          title: s.title,
          text: s.text,
          score: s.score ?? 0,
          source: 'product',
        }));
        chunks = capChunks(chunks, MAX_CHUNKS_PER_RETRIEVER_PER_SUBQUERY);
        const productsToAdd = (products ?? []).filter((p) => {
          const key = (p as { id?: string }).id ?? (p as { name?: string }).name ?? '';
          if (productDedup.has(key)) return false;
          productDedup.add(key);
          return true;
        });
        const out = { chunks, bySource: { product: productsToAdd } as Partial<RouteAndRetrieveResult['bySource']> };
        await setCache(cacheKey, out, ttl);
        return out;
      }
      if (source === 'movie') {
        const filters = getMovieFilters(plan, subQuery);
        const { showtimes, snippets } = await deps.movieRetriever.searchShowtimes(filters);
        let chunks: RetrievedChunk[] = (snippets ?? []).map((s) => ({
          id: s.id,
          url: s.url,
          title: s.title,
          text: s.text,
          score: s.score ?? 0,
          source: 'movie',
        }));
        chunks = capChunks(chunks, MAX_CHUNKS_PER_RETRIEVER_PER_SUBQUERY);
        const toAdd = (showtimes ?? []).filter((m) => {
          const key = JSON.stringify(m);
          if (movieDedup.has(key)) return false;
          movieDedup.add(key);
          return true;
        });
        const out = { chunks, bySource: { movie: toAdd } as Partial<RouteAndRetrieveResult['bySource']> };
        await setCache(cacheKey, out, ttl);
        return out;
      }
      if (source === 'web') {
        const overview = await perplexityOverview(subQuery);
        const citations = overview.citations ?? [];
        let chunks: RetrievedChunk[] = citations.map((c, i) => ({
          id: c.id || `web-${i}`,
          url: c.url,
          title: c.title,
          text: c.snippet ?? '',
          score: 0.7,
          source: 'web',
          date: (c as { date?: string; last_updated?: string }).date ?? (c as { last_updated?: string }).last_updated,
        }));
        chunks = capChunks(chunks, MAX_CHUNKS_PER_RETRIEVER_PER_SUBQUERY);
        const out = { chunks, bySource: {} };
        await setCache(cacheKey, out, ttl);
        return out;
      }
    } catch (err) {
      logger.warn('retrieval-router:retriever_error', { source, subQuery: subQuery.slice(0, 50), err: String(err) });
    }
    return { chunks: [], bySource: {} };
  };

  if (DEBUG_RETRIEVAL) {
    const subQueryToSources = new Map<string, RetrievalSource[]>();
    for (const t of tasks) {
      const arr = subQueryToSources.get(t.subQuery) ?? [];
      if (!arr.includes(t.source)) arr.push(t.source);
      subQueryToSources.set(t.subQuery, arr);
    }
    logger.info('retrieval-router:subqueries_and_retrievers', {
      subQueries: Array.from(subQueryToSources.keys()).map((q) => q.slice(0, 80)),
      selectedRetrievers: Object.fromEntries([...subQueryToSources].map(([q, s]) => [q.slice(0, 40), s])),
    });
  }

  const results = await Promise.all(tasks.map((t) => runOne(t.subQuery, t.source)));

  const chunksPerSource: Record<string, number> = {};
  for (const r of results) {
    allChunks.push(...r.chunks);
    for (const c of r.chunks) chunksPerSource[c.source] = (chunksPerSource[c.source] ?? 0) + 1;
    if (r.bySource.hotel?.length) bySource.hotel = [...(bySource.hotel ?? []), ...r.bySource.hotel];
    if (r.bySource.flight?.length) bySource.flight = [...(bySource.flight ?? []), ...r.bySource.flight];
    if (r.bySource.product?.length) bySource.product = [...(bySource.product ?? []), ...r.bySource.product];
    if (r.bySource.movie?.length) bySource.movie = [...(bySource.movie ?? []), ...r.bySource.movie];
  }
  if (DEBUG_RETRIEVAL) logger.info('retrieval-router:chunks_per_source', { chunksPerSource, totalBeforeDedupe: allChunks.length });

  // Smart dedupe (normalize + Jaccard > 0.85 → keep higher-quality chunk); improves answer quality by removing near-duplicates.
  const { kept: deduped, droppedCount } = smartDedupeChunks(allChunks);
  if (DEBUG_RETRIEVAL) logger.debug('retrieval-router:dedupe', { droppedCount, kept: deduped.length });

  // Composite rerank (no LLM): base score + text similarity to subQuery + recency boost - domain repetition penalty.
  const trimmedSubQueries = subQueries.filter((q) => q?.trim());
  let sorted = rerankChunks(deduped, trimmedSubQueries);
  if (deps.passageReranker && sorted.length > 0) {
    try {
      sorted = await deps.passageReranker.rerank(trimmedSubQueries.join(' '), sorted);
    } catch (err) {
      logger.warn('retrieval-router:passage_reranker_failed', { err: String(err) });
    }
  }
  const capped = sorted.slice(0, MAX_TOTAL_CHUNKS);
  if (DEBUG_RETRIEVAL) logger.info('retrieval-router:final', { finalChunkCount: capped.length, totalBeforeCap: sorted.length });

  return {
    chunks: capped,
    bySource,
    searchQueries: trimmedSubQueries,
    routingDecision,
  };
}
