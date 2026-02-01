// src/services/query-understanding.ts
// Pipeline: (0) Decompose first → (A) Classify vertical/intent → (B) Rewrite → (C) Extract filters. Decomposition discovers all parts (including "other") before we commit to verticals.
import {
  QueryContext,
  Intent,
  Vertical,
  type PlanCandidate,
  type ExtractedEntities,
  type AmbiguityInfo,
} from '@/types/core';
import {
  VerticalPlan,
  ProductFilters,
  HotelFilters,
  FlightFilters,
  MovieTicketFilters,
} from '@/types/verticals';
import { callSmallLLM } from './llm-small';
import { logger } from '@/services/logger';

export function safeParseJson(raw: string, context: string): Record<string, any> {
  let txt = raw.trim();

  // Strip common ```json ... ``` or ``` ... ``` wrappers
  if (txt.startsWith('```')) {
    const firstNewline = txt.indexOf('\n');
    const lastFence = txt.lastIndexOf('```');
    if (firstNewline !== -1 && lastFence !== -1 && lastFence > firstNewline) {
      txt = txt.slice(firstNewline + 1, lastFence).trim();
    } else {
      txt = txt.replace(/^```\w*\n?/, '').replace(/\n?```$/, '').trim();
    }
  }

  try {
    let parsed = JSON.parse(txt);
    if (typeof parsed === 'object' && parsed !== null) return parsed;
    logger.warn('safeParseJson:non_object', { context, raw: txt.slice(0, 300) });
    return {};
  } catch {
    // Retry with single quotes normalized to double (LLM sometimes returns {'key':'value'})
    try {
      const normalized = txt.replace(/'/g, '"');
      const parsed = JSON.parse(normalized);
      if (typeof parsed === 'object' && parsed !== null) return parsed;
    } catch {
      // fall through to final warn
    }
    logger.warn('safeParseJson:parse_error', {
      context,
      error: 'Invalid JSON after stripping fences',
      raw: txt.slice(0, 300),
    });
    return {};
  }
}

/** One part of a decomposed query: the sub-query text and the vertical it belongs to (product, hotel, flight, movie, or other for web search / no vertical). */
export interface DecomposedPart {
  part: string;
  vertical: Vertical;
}

/**
 * Decompose the query into parts with verticals. When rewrittenQuery is provided, decompose that text
 * (so we split already-resolved text; we don't rely on the decomposer to add cities).
 * "other" = general web search, things to do, weather, or anything that doesn't fit the four structured verticals.
 * Returns empty array if decomposition fails (caller falls back to classify-then-extract).
 */
export async function decomposeQueryFirst(
  ctx: QueryContext,
  rewrittenQuery?: string,
): Promise<DecomposedPart[]> {
  const textToDecompose = rewrittenQuery != null && rewrittenQuery.trim() ? rewrittenQuery.trim() : ctx.message.trim();
  const recentHistory = (ctx.history ?? []).slice(-5);
  const historyBlock =
    recentHistory.length > 0
      ? `\nRecent conversation:\n${recentHistory.map((h, i) => `${i + 1}. ${h}`).join('\n')}\n`
      : '';

  const prompt = `
Decompose the user's query into logical parts. For each part, assign exactly one domain: "product" | "hotel" | "flight" | "movie" | "other".

Rules:
- "product" = buying products (laptops, shoes, etc.)
- "hotel" = accommodation, stays, rooms
- "flight" = plane tickets, air travel
- "movie" = cinema, showtimes, movie tickets
- "other" = general web search: things to do, weather, facts, "no vertical", or anything that doesn't fit the four above. Use "other" for half-query that belongs to no vertical.

If the query is a single clear intent (e.g. only "hotels in Boston"), return ONE part. If the user asked for multiple different things (e.g. flights to NYC + hotels in Philadelphia + weather there), return one part per thing. Half of the query can be one vertical and half "other". Each "part" should be a short sub-query that preserves the resolved wording (e.g. "hotels near NYC airport" not "hotels near airport" if the query already says NYC).

Query to decompose: ${JSON.stringify(textToDecompose)}
${historyBlock}

Return JSON only: [{"part": "short sub-query or request for this part", "vertical": "product"|"hotel"|"flight"|"movie"|"other"}, ...]. No markdown, no code fences. Use double quotes.
`;
  const raw = await callSmallLLM(prompt);
  const parsed = safeParseJson(raw, 'decomposeQueryFirst');
  const arr = Array.isArray(parsed) ? parsed : parsed?.parts ?? [];
  const valid: DecomposedPart[] = [];
  for (const item of arr) {
    const part = typeof item?.part === 'string' ? item.part.trim() : '';
    const v = item?.vertical;
    if (!part || part.length > 500) continue;
    if (typeof v === 'string' && ['product', 'hotel', 'flight', 'movie', 'other'].includes(v)) {
      valid.push({ part, vertical: v as Vertical });
    }
  }
  return valid;
}

export async function understandQuery(ctx: QueryContext): Promise<VerticalPlan> {
  // Step 1: Rewrite full query first (domain-agnostic). Resolves "airport" → "NYC airport" etc. so we don't rely on decomposer to add cities.
  const rewrittenQuery = await rewriteFullQuery(ctx);

  // Step 2: Decompose the rewritten query — discover all parts (including "other"). Parts get already-resolved text.
  const parts = await decomposeQueryFirst(ctx, rewrittenQuery);

  // If decomposition gave us 0 or 1 part, fall back to classic flow (classify whole query, then extract)
  const useDecomposedFlow = parts.length >= 2;
  let verticalScores: { vertical: Vertical; score: number }[];
  let intent: Intent;
  let preferenceContext: string | undefined;
  // Perplexity-aligned: "primary" is initial hypothesis only; orchestrator decides final presentation order from retrieval quality.
  let initialPrimary: { vertical: Vertical; score: number };
  let initialSecondary: { vertical: Vertical; score: number } | undefined;

  if (!useDecomposedFlow) {
    // Classic flow: classify whole query, use rewrittenQuery from step 1, then extract
    const [scores, intentResult] = await Promise.all([
      classifyVerticalWithScores(ctx),
      classifyIntent(ctx),
    ]);
    verticalScores = scores;
    intent = intentResult;
    initialPrimary = verticalScores[0] ?? { vertical: 'other' as Vertical, score: 1 };
    initialSecondary = verticalScores[1];
    preferenceContext = await extractPreferenceContext(ctx, rewrittenQuery, initialPrimary.vertical);
  } else {
    // Decomposed flow: parts are unordered; assign equal initial scores — orchestrator reorders by retrieval quality (no false priority from LLM order).
    intent = await classifyIntent(ctx);
    const partScores = parts.map((p) => ({ vertical: p.vertical, score: 0.9 }));
    verticalScores = partScores;
    initialPrimary = partScores[0];
    initialSecondary = partScores[1];
    preferenceContext = await extractPreferenceContext(ctx, rewrittenQuery, initialPrimary.vertical);
  }

  // Perplexity-aligned: when decomposed, derive intent and preference per vertical (scoped) so "compare flights and suggest hotels" gets compare vs browse.
  let partIntents: Intent[] = [];
  let partPreferenceContexts: (string | undefined)[] = [];
  if (useDecomposedFlow && parts.length >= 1) {
    partIntents = await Promise.all(parts.map((p) => classifyIntentForSlice(p.part)));
    partPreferenceContexts = await Promise.all(
      parts.map((p) => extractPreferenceContext(ctx, p.part, p.vertical)),
    );
  }

  // Step C: Extract structured filters — from rewritten query (classic) or from each part's text (decomposed)
  let product: ProductFilters | undefined;
  let hotel: HotelFilters | undefined;
  let flight: FlightFilters | undefined;
  let movie: MovieTicketFilters | undefined;

  if (useDecomposedFlow && parts.length >= 1) {
    for (const p of parts) {
      const text = p.part;
      if (p.vertical === 'product') product = await extractProductFilters(text, ctx);
      else if (p.vertical === 'hotel') hotel = await extractHotelFilters(text, ctx);
      else if (p.vertical === 'flight') flight = await extractFlightFilters(text, ctx);
      else if (p.vertical === 'movie') movie = await extractMovieFilters(text, ctx);
    }
  } else {
    // Use initial hypothesis only; orchestrator decides final order from retrieval quality.
    if (initialPrimary.vertical === 'product') {
      product = await extractProductFilters(rewrittenQuery, ctx);
    } else if (initialPrimary.vertical === 'hotel') {
      hotel = await extractHotelFilters(rewrittenQuery, ctx);
    } else if (initialPrimary.vertical === 'flight') {
      flight = await extractFlightFilters(rewrittenQuery, ctx);
    } else if (initialPrimary.vertical === 'movie') {
      movie = await extractMovieFilters(rewrittenQuery, ctx);
    }
    if (initialSecondary && initialSecondary.vertical !== initialPrimary.vertical) {
      if (initialSecondary.vertical === 'product' && product == null) product = await extractProductFilters(rewrittenQuery, ctx);
      else if (initialSecondary.vertical === 'hotel' && hotel == null) hotel = await extractHotelFilters(rewrittenQuery, ctx);
      else if (initialSecondary.vertical === 'flight' && flight == null) flight = await extractFlightFilters(rewrittenQuery, ctx);
      else if (initialSecondary.vertical === 'movie' && movie == null) movie = await extractMovieFilters(rewrittenQuery, ctx);
    }
  }

  // Build decomposedContext from parts so each vertical gets only its slice (and "other" gets merged other-parts)
  let decomposedContext: Partial<Record<Vertical, string>> | undefined;
  if (useDecomposedFlow && parts.length >= 1) {
    decomposedContext = {};
    const otherParts = parts.filter((p) => p.vertical === 'other').map((p) => p.part);
    if (otherParts.length) decomposedContext['other'] = otherParts.join('; ');
    for (const p of parts) {
      if (p.vertical !== 'other') {
        const existing = decomposedContext[p.vertical];
        decomposedContext[p.vertical] = existing ? `${existing}; ${p.part}` : p.part;
      }
    }
  } else if (initialSecondary && initialSecondary.vertical !== initialPrimary.vertical) {
    decomposedContext = await decomposeQueryForVerticals(ctx, rewrittenQuery, [initialPrimary.vertical, initialSecondary.vertical]);
    if (Object.keys(decomposedContext ?? {}).length === 0) decomposedContext = undefined;
  }

  // Entities/locations and ambiguity (optional steps for anchors and disambiguation)
  const [entities, ambiguity, preferencePriority] = await Promise.all([
    extractEntitiesAndLocations(ctx, rewrittenQuery),
    detectAmbiguity(ctx, rewrittenQuery),
    extractPreferencePriority(ctx, rewrittenQuery),
  ]);

  const softAirport = detectSoftAirport(rewrittenQuery);
  const softConstraints = softAirport ? { airport: softAirport } : undefined;

  // Step D: Build candidates from verticalScores (classic) or from parts (decomposed). When decomposed, attach scoped intent and preference per candidate.
  const candidates: PlanCandidate[] = verticalScores.map((vs, idx) => {
    const intentForCandidate = useDecomposedFlow && partIntents[idx] != null ? partIntents[idx]! : intent;
    const prefForCandidate = useDecomposedFlow ? partPreferenceContexts[idx] : undefined;
    const base: PlanCandidate = {
      vertical: vs.vertical,
      intent: intentForCandidate,
      score: vs.score,
      ...(prefForCandidate && { preferenceContext: prefForCandidate }),
    };
    if (vs.vertical === 'product' && product) base.productFilters = product;
    else if (vs.vertical === 'hotel' && hotel) base.hotelFilters = hotel;
    else if (vs.vertical === 'flight' && flight) base.flightFilters = flight;
    else if (vs.vertical === 'movie' && movie) base.movieFilters = movie;
    return base;
  });

  // Step E: Build plan with initialPrimary.vertical for API shape only; orchestrator decides final presentation from retrieval quality.
  const vertical = initialPrimary.vertical;
  const now = new Date();
  const timeSensitivity = await classifyTimeSensitivity(ctx);
  const planExtras = {
    ...(preferenceContext && { preferenceContext }),
    ...(decomposedContext && Object.keys(decomposedContext).length > 0 && { decomposedContext }),
    ...(entities && (entities.entities?.length || entities.locations?.length || entities.concepts?.length) && { entities }),
    // Only attach ambiguity when unresolved — suppresses noise when history/context already resolved it.
    ...(ambiguity && !ambiguity.resolved && { ambiguity }),
    timeSensitivity,
    ...(preferencePriority.length > 0 && { preferencePriority }),
    ...(softConstraints && { softConstraints }),
  };
  let plan: VerticalPlan;
  switch (vertical) {
    case 'product':
      plan = {
        vertical,
        intent,
        rewrittenPrompt: rewrittenQuery,
        product: product ?? { query: rewrittenQuery },
        candidates,
        ...planExtras,
      };
      break;
    case 'hotel':
      plan = {
        vertical,
        intent,
        rewrittenPrompt: rewrittenQuery,
        hotel:
          hotel ?? {
            destination: 'unknown',
            checkIn: formatDate(now),
            checkOut: formatDate(addDays(now, 1)),
            guests: 2,
          },
        candidates,
        ...planExtras,
      };
      break;
    case 'flight':
      plan = {
        vertical,
        intent,
        rewrittenPrompt: rewrittenQuery,
        flight:
          flight ?? {
            origin: 'unknown',
            destination: 'unknown',
            departDate: now.toISOString().slice(0, 10),
            adults: 1,
          },
        candidates,
        ...planExtras,
      };
      break;
    case 'movie':
      plan = {
        vertical,
        intent,
        rewrittenPrompt: rewrittenQuery,
        movie:
          movie ?? {
            city: 'unknown',
            date: now.toISOString().slice(0, 10),
            tickets: 2,
          },
        candidates,
        ...planExtras,
      };
      break;
    default:
      plan = {
        vertical: 'other',
        intent,
        rewrittenPrompt: rewrittenQuery,
        candidates,
        ...planExtras,
      };
  }
  return plan;
}

type VerticalScore = { vertical: Vertical; score: number };

// Step A: Vertical classification with top-2 scores for multi-vertical routing
async function classifyVerticalWithScores(ctx: QueryContext): Promise<VerticalScore[]> {
  const recentHistory = ctx.history.slice(-3);
  const prompt = `
Return JSON with the top 1 or 2 domains for the user's request, each with a score in [0,1].
Use: {"candidates":[{"vertical":"product"|"hotel"|"flight"|"movie"|"other","score":number}, ...]}.
Classify the main domain first (score 1 or 0.9), then an optional second domain if relevant (e.g. "weekend in NYC" -> hotel + flight).

Important:
- Return ONLY valid JSON.
- Do NOT include markdown, code fences (e.g. \`\`\`), or explanations.
- Use double quotes around keys and string values.

Examples:
- Hotels, stays -> [{"vertical":"hotel","score":1}]
- Flights, plane tickets -> [{"vertical":"flight","score":1}]
- Headphones, laptops -> [{"vertical":"product","score":1}]
- Movies, cinema, tickets -> [{"vertical":"movie","score":1}]
- "Weekend trip NYC" -> [{"vertical":"hotel","score":0.95},{"vertical":"flight","score":0.6}]
- Anything else -> [{"vertical":"other","score":1}]

Current query: ${JSON.stringify(ctx.message)}
Recent history: ${JSON.stringify(recentHistory)}
`;
  const raw = await callSmallLLM(prompt);
  const parsed = safeParseJson(raw, 'classifyVerticalWithScores');
  const arr = parsed?.candidates ?? parsed?.verticals ?? [];
  let valid: VerticalScore[];
  if (!Array.isArray(arr) || arr.length === 0) {
    const single = parsed?.vertical;
    if (typeof single === 'string' && ['product', 'hotel', 'flight', 'movie', 'other'].includes(single)) {
      valid = [{ vertical: single as Vertical, score: 1 }];
    } else {
      valid = [{ vertical: 'other', score: 1 }];
    }
  } else {
    valid = arr
      .filter((c: unknown) => {
        const v = c && typeof c === 'object' ? (c as { vertical?: string }).vertical : undefined;
        return typeof v === 'string' && ['product', 'hotel', 'flight', 'movie', 'other'].includes(v);
      })
      .map((c: { vertical: string; score?: number }) => {
        let score = typeof c.score === 'number' ? c.score : 1;
        if (score < 0) score = 0;
        if (score > 1) score = 1;
        return { vertical: c.vertical as Vertical, score };
      })
      .slice(0, 3);
  }
  let result =
    valid.length === 0 ? [{ vertical: 'other' as Vertical, score: 1 }] : valid;

  // Perplexity-aligned: nudge suspected vertical instead of hard override — preserves LLM candidates, less brittle for mixed/conversational queries.
  const q = ctx.message.toLowerCase();
  const looksHotel =
    /hotel|stay|hostel|airbnb|resort|room\b/.test(q) ||
    /check[- ]in|check[- ]out/.test(q);
  const looksFlight =
    /flight|plane|airline|ticket\b|one[- ]way|round[- ]trip/.test(q);
  const looksProduct =
    /buy|price|discount|deal|laptop|phone|headphone|shoes|camera/.test(q);
  const looksMovie =
    /movie|cinema|theater|tickets?\b|showtime/.test(q);

  const primary = result[0];
  if (primary.vertical === 'other') {
    let suspected: Vertical | null = null;
    if (looksHotel) suspected = 'hotel';
    else if (looksFlight) suspected = 'flight';
    else if (looksProduct) suspected = 'product';
    else if (looksMovie) suspected = 'movie';

    if (suspected) {
      const alreadyHas = result.some((r) => r.vertical === suspected);
      if (!alreadyHas) {
        // Nudge: add suspected vertical with boosted score; keep original candidates (other stays).
        const nudgeScore = 0.88;
        result = [{ vertical: suspected, score: nudgeScore }, ...result].slice(0, 3);
        logger.info('classifyVertical:nudge', {
          query: ctx.message.slice(0, 80),
          suspected,
          nudgeScore,
        });
      } else {
        // Slight score boost for existing candidate so it can compete
        result = result.map((r) =>
          r.vertical === suspected ? { ...r, score: Math.min(1, (r.score ?? 0.9) + 0.08) } : r,
        );
      }
    }
  }

  return result;
}

// Step A: Intent classification using query + history
async function classifyIntent(ctx: QueryContext): Promise<Intent> {
  const recentHistory = ctx.history.slice(-3);
  const prompt = `
Return JSON {"intent":"browse"|"compare"|"buy"|"book"}.

Rules:
- Return ONLY valid JSON.
- Do NOT wrap the JSON in markdown or code fences.
- Use double quotes for keys and string values.

- browse: wants ideas/options, not necessarily purchase
- compare: wants pros/cons or ranking
- buy: wants to purchase products
- book: wants to book hotels/flights/tickets

Current query: ${JSON.stringify(ctx.message)}
Recent history: ${JSON.stringify(recentHistory)}
`;
  const raw = await callSmallLLM(prompt);
  const parsed = safeParseJson(raw, 'classifyIntent');
  const i = parsed?.intent;
  if (typeof i === 'string' && ['browse', 'compare', 'buy', 'book'].includes(i)) return i as Intent;
  return 'browse';
}

/** Scoped intent: classify intent from a single slice (e.g. per-vertical when decomposed). Lightweight; used when decomposedContext exists. */
async function classifyIntentForSlice(sliceText: string): Promise<Intent> {
  if (!sliceText?.trim()) return 'browse';
  const prompt = `
Return JSON {"intent":"browse"|"compare"|"buy"|"book"}.

- browse: wants ideas/options
- compare: wants pros/cons or ranking
- buy: wants to purchase
- book: wants to book

Query slice: ${JSON.stringify(sliceText.slice(0, 300))}

Return ONLY valid JSON. No markdown. Use double quotes.`;
  const raw = await callSmallLLM(prompt);
  const parsed = safeParseJson(raw, 'classifyIntentForSlice');
  const i = parsed?.intent;
  if (typeof i === 'string' && ['browse', 'compare', 'buy', 'book'].includes(i)) return i as Intent;
  return 'browse';
}

export type TimeSensitivity = 'timeless' | 'time_sensitive';

export async function classifyTimeSensitivity(
  ctx: QueryContext,
): Promise<TimeSensitivity> {
  const recentHistory = ctx.history.slice(-3);
  const prompt = `
Return JSON {"time":"timeless"|"time_sensitive"}.

Rules:
- Return ONLY valid JSON.
- Do NOT wrap the JSON in markdown or code fences.
- Use double quotes for keys and string values.

- "timeless": general knowledge, explanations, definitions, things that don't change often
  Examples: "why is the sky blue", "how photosynthesis works", "what is quantum entanglement"

- "time_sensitive": news, latest updates, recent events, current status, "this year", "latest", "2025", etc.
  Examples: "latest advancements in AI", "who won the game last night", "current inflation rate in the US"

Current query: ${JSON.stringify(ctx.message)}
Recent history: ${JSON.stringify(recentHistory)}
`;

  const raw = await callSmallLLM(prompt);
  const parsed = safeParseJson(raw, 'classifyTimeSensitivity');
  const t = parsed?.time;
  if (t === 'timeless' || t === 'time_sensitive') return t as TimeSensitivity;
  return 'timeless';
}

/**
 * Single canonical semantic rewrite (domain-agnostic). All other rewrites (rewriteQueryWithHistory,
 * getRewrittenQueriesForMode) are retrieval-only variants — do not treat them as semantic truth.
 */
async function rewriteFullQuery(ctx: QueryContext): Promise<string> {
  const recentHistory = (ctx.history ?? []).slice(-5);
  const historyContext =
    recentHistory.length > 0
      ? `\n\nPrevious queries:\n${recentHistory.map((q, i) => `${i + 1}. ${q}`).join('\n')}\n`
      : '';

  const prompt = `
Rewrite the user's query as one clear, explicit sentence. Resolve vague references.

Rules:
- Use conversation history: "there", "that place", "same area" → use location from previous queries.
- TIME: You MUST convert relative time phrases to explicit dates. Output actual dates in YYYY-MM-DD or ranges (e.g. "2025-02-01 to 2025-02-02"). Examples: "this weekend" → use the next Saturday–Sunday as YYYY-MM-DD; "next month", "same dates" → resolve using history or the upcoming month. Do not leave relative time in the rewritten query.
- Within the SAME query: if the user mentions a city in one part (e.g. "flights to NYC") and something vague in another (e.g. "hotels near airport"), resolve the vague part using the city (e.g. "hotels near NYC airport").
- Keep all parts of the query; keep budget/quality wording. Do not favor one domain; keep the full request.

Current query: ${JSON.stringify(ctx.message)}
${historyContext}

Return ONLY the rewritten query as plain text (no JSON, no explanation). Include explicit YYYY-MM-DD for any date references.
`;
  const raw = await callSmallLLM(prompt);
  return raw.trim();
}

/** Extract entities, locations, and concepts for structured anchors (rewrite/filter extraction). */
async function extractEntitiesAndLocations(
  ctx: QueryContext,
  rewrittenQuery: string,
): Promise<ExtractedEntities> {
  const prompt = `
From the user's query, extract entities (brands, product names, event names), locations (cities, regions, landmarks), and key concepts. Use for search and filter anchoring.

Query: ${JSON.stringify(rewrittenQuery)}

Return JSON only: {"entities": ["string"], "locations": ["string"], "concepts": ["string"]}. Use empty arrays if none. No markdown, no code fences. Use double quotes.
`;
  const raw = await callSmallLLM(prompt);
  const p = safeParseJson(raw, 'extractEntitiesAndLocations');
  const entities = Array.isArray(p?.entities) ? p.entities.filter((x): x is string => typeof x === 'string').slice(0, 20) : undefined;
  const locations = Array.isArray(p?.locations) ? p.locations.filter((x): x is string => typeof x === 'string').slice(0, 20) : undefined;
  const concepts = Array.isArray(p?.concepts) ? p.concepts.filter((x): x is string => typeof x === 'string').slice(0, 20) : undefined;
  if (!entities?.length && !locations?.length && !concepts?.length) return {};
  return { entities, locations, concepts };
}

/** Detect when a term has multiple interpretations (e.g. "Apple" = company vs fruit). Answer can disambiguate. */
async function detectAmbiguity(ctx: QueryContext, rewrittenQuery: string): Promise<AmbiguityInfo | undefined> {
  const prompt = `
Does the query contain a term that could have multiple interpretations (e.g. "Apple" = company vs fruit, "Python" = language vs snake, "Java" = island vs language)? If yes, list the term and possible interpretations. If the rest of the query or history makes the intent clear, set "resolved" to the most likely interpretation.

Query: ${JSON.stringify(rewrittenQuery)}

Return JSON only: {"term": "string", "interpretations": ["string"], "resolved": "string or omit"}. If no ambiguity, return {"term": "", "interpretations": []} or empty. No markdown, no code fences.
`;
  const raw = await callSmallLLM(prompt);
  const p = safeParseJson(raw, 'detectAmbiguity');
  const term = typeof p?.term === 'string' ? p.term.trim() : '';
  const interpretations = Array.isArray(p?.interpretations) ? p.interpretations.filter((x): x is string => typeof x === 'string') : [];
  if (!term || interpretations.length < 2) return undefined;
  const resolved = typeof p?.resolved === 'string' ? p.resolved.trim() : undefined;
  return { term, interpretations, resolved };
}

/** Perplexity-style: turn one request into 1–3 effective search queries (synonyms, key terms) for retrieval fan-out. Exported for use by vertical agents. */
export async function searchReformulationPerPart(partText: string, vertical: Vertical): Promise<string[]> {
  const prompt = `
Turn this user request into 1-3 effective search queries for a ${vertical} search engine. Add synonyms, key terms, or alternate phrasings that would improve recall. Keep each query concise (a few words to a short phrase). Preserve the user's intent.

Request: ${JSON.stringify(partText)}

Return JSON only: {"queries": ["query1", "query2", ...]}. No markdown, no code fences. Use double quotes. Include the original phrasing as the first query if it's already search-friendly.
`;
  const raw = await callSmallLLM(prompt);
  const p = safeParseJson(raw, 'searchReformulationPerPart');
  const arr = Array.isArray(p?.queries) ? p.queries : [];
  const valid = arr.filter((x): x is string => typeof x === 'string' && x.trim().length > 0).slice(0, 5);
  if (valid.length === 0) return [partText.slice(0, 200)];
  return valid;
}

/** Within-vertical fan-out: decompose one part into multiple focused sub-queries for retrieval (e.g. "50L backpack" + "beginner" + "Philmont"). */
async function decomposeWithinVertical(partText: string, vertical: Vertical): Promise<string[]> {
  const prompt = `
Break this ${vertical} request into 2-5 focused sub-queries that each target a different aspect (e.g. product type, size, use case, location). Each sub-query should be a short, search-friendly phrase. We will run retrieval for each sub-query and combine results.

Request: ${JSON.stringify(partText)}

Return JSON only: {"subQueries": ["sub1", "sub2", ...]}. No markdown, no code fences. Use double quotes. If the request is already a single clear query, return one item.
`;
  const raw = await callSmallLLM(prompt);
  const p = safeParseJson(raw, 'decomposeWithinVertical');
  const arr = Array.isArray(p?.subQueries) ? p.subQueries : [];
  const valid = arr.filter((x): x is string => typeof x === 'string' && x.trim().length > 0).slice(0, 5);
  if (valid.length === 0) return [partText.slice(0, 200)];
  return valid;
}

// Step B: Query rewriting with history (resolves vague references like "there", "this weekend")
async function rewriteQueryWithHistory(ctx: QueryContext, vertical: Vertical): Promise<string> {
  const recentHistory = ctx.history.slice(-5); // Last 5 queries for context
  const historyContext = recentHistory.length > 0
    ? `\n\nPrevious queries:\n${recentHistory.map((q, i) => `${i + 1}. ${q}`).join('\n')}`
    : '';

  const prompt = `
Rewrite the user's query as a clear, explicit request for the "${vertical}" domain. Resolve vague references using history.

Rules:
- "there", "that place", "same area" → use location from previous queries
- "this weekend", "next week", "same dates" → resolve to specific dates
- "under $X", "cheap", "budget" → keep budget constraints
- "good", "best", "nice" → keep quality indicators
- If history mentions a location/city, use it when current query is vague
- If history mentions dates, use them when current query says "same" or "this weekend"

Current query: ${JSON.stringify(ctx.message)}
${historyContext}

Return ONLY the rewritten query as plain text (no JSON, no explanation).
`;
  const raw = await callSmallLLM(prompt);
  return raw.trim();
}

/** Extract user preference context (free-form). Uses conversation history to resolve "my taste", "my budget", etc. */
async function extractPreferenceContext(
  ctx: QueryContext,
  rewrittenQuery: string,
  vertical: Vertical,
): Promise<string | undefined> {
  const recentHistory = (ctx.history ?? []).slice(-10); // Last 10 messages for "my taste" / "my budget" resolution
  const historyBlock =
    recentHistory.length > 0
      ? `\nConversation history (most recent last):\n${recentHistory.map((h, i) => `${i + 1}. ${h}`).join('\n')}\n`
      : '';

  const prompt = `
From the user's current query and the conversation history, extract a short "preference context" in plain language: what they care about beyond basic filters (e.g. location, dates).

Important:
- If the user says "my taste", "my style", "what I like", "like I said", "as I mentioned", "my budget", "in my price range", "same as before", etc., USE THE CONVERSATION HISTORY to resolve these. Extract specific preferences from prior messages (e.g. budget amount, style, colors, brands) and include them in the preference context.
- Examples from history: "User said budget $150/night" → include "budget around $150/night"; "User said they like minimalist design" → include "minimalist style"; "User asked for family-friendly earlier" → include "family-friendly".
- If there is no history or the history doesn't contain relevant preferences, extract only from the current query.
- Do NOT invent preferences. Only use what is stated in the current query or clearly implied in history.
- Do NOT extract structured filters that go in schema (destination, check-in/out, origin/destination for flights). Only preferences, style, use case, amenities, budget range if stated, or related wishes.

Current query: ${JSON.stringify(ctx.message)}
Rewritten query: ${JSON.stringify(rewrittenQuery)}
Vertical: ${vertical}
${historyBlock}

Return a single short sentence or phrase list, e.g. "User wants: X, Y, Z." or "User previously said: budget $200, minimalist style." If the query has no clear preferences and history has none, return exactly: NONE
`;
  const raw = await callSmallLLM(prompt);
  const trimmed = raw.trim();
  if (!trimmed || trimmed.toUpperCase() === 'NONE') return undefined;
  return trimmed.length > 500 ? trimmed.slice(0, 500) : trimmed;
}

/** Extract ordered preference phrases (highest priority first) for relaxation when results are thin. */
async function extractPreferencePriority(
  ctx: QueryContext,
  rewrittenQuery: string,
): Promise<string[]> {
  const prompt = `
From the user's query and rewritten form, list their stated preferences in ORDER of importance (most important first).
Typical order: price/budget > location/area > amenities/quality (e.g. "under $150" before "good wifi" before "near airport").
Include only concrete preferences (budget, location, wifi, quiet, etc.), not the main intent (e.g. not "flights to NYC").
Current query: ${JSON.stringify(ctx.message)}
Rewritten: ${JSON.stringify(rewrittenQuery)}

Return JSON only: {"priorityOrder": ["preference1", "preference2", ...]}. If no clear preferences, return {"priorityOrder": []}. No markdown.
`;
  const raw = await callSmallLLM(prompt);
  const parsed = safeParseJson(raw, 'extractPreferencePriority');
  const arr = parsed?.priorityOrder;
  if (!Array.isArray(arr)) return [];
  return arr.filter((x): x is string => typeof x === 'string').slice(0, 10);
}

/** Point 1: Detect when "airport" is mentioned but not pinned to a specific code (JFK/LGA/EWR etc.). */
function detectSoftAirport(rewrittenQuery: string): 'city_only' | 'unspecified' | undefined {
  const lower = rewrittenQuery.toLowerCase();
  if (!lower.includes('airport')) return undefined;
  const airportCodes = ['jfk', 'lga', 'ewr', 'newark', 'laguardia', 'la guardia'];
  const hasSpecific = airportCodes.some((code) => lower.includes(code));
  if (hasSpecific) return undefined;
  return 'unspecified';
}

const STRUCTURED_VERTICALS: Vertical[] = ['product', 'hotel', 'flight', 'movie'];

/** Decompose a multi-part query into per-vertical sub-query / preference slice (query decomposition). When the user asks for two different things (e.g. flights to NYC and hotels in Philadelphia), each vertical gets only the part that applies to it. */
async function decomposeQueryForVerticals(
  ctx: QueryContext,
  rewrittenQuery: string,
  verticals: Vertical[],
): Promise<Partial<Record<Vertical, string>>> {
  const structured = verticals.filter((v) => STRUCTURED_VERTICALS.includes(v));
  if (structured.length < 2) return {};

  const verticalList = structured.join(', ');
  const prompt = `
The user asked a single question that touches multiple domains. Decompose it so each domain gets only the part of the request that applies to that domain.

Current query: ${JSON.stringify(ctx.message)}
Rewritten query: ${JSON.stringify(rewrittenQuery)}
Domains to decompose for: ${verticalList}

Examples:
- "flights to NYC and also suggest me few hotels in Philadelphia" → flight: "flights to NYC", hotel: "hotels in Philadelphia"
- "flights to NYC and hotels near the airport" (same trip) → flight: "flights to NYC", hotel: "hotels near NYC airport" (same context is fine if it's one trip)
- "weekend in NYC with kids, things to do and a family-friendly hotel" → hotel: "family-friendly hotel in NYC for weekend with kids", other: "things to do with kids in NYC"

Return JSON only: {"vertical_name": "short sub-query or preference for that vertical", ...}. Use keys: ${structured.map((v) => `"${v}"`).join(', ')}. Each value should be one short sentence or phrase. If the query is really one continuous request (same location, same trip), you may return the same or very similar text for each. Do NOT include markdown or code fences.
`;
  const raw = await callSmallLLM(prompt);
  const parsed = safeParseJson(raw, 'decomposeQueryForVerticals');
  const result: Partial<Record<Vertical, string>> = {};
  for (const v of structured) {
    const val = parsed?.[v];
    if (typeof val === 'string' && val.trim()) result[v as Vertical] = val.trim().slice(0, 500);
  }
  return result;
}

/** Returns retrieval-only query variants for the vertical (deep mode fan-out). Not semantic truth; plan.rewrittenPrompt is from rewriteFullQuery only. */
export async function getRewrittenQueriesForMode(
  ctx: QueryContext,
  vertical: Vertical,
): Promise<string[]> {
  const base = await rewriteQueryWithHistory(ctx, vertical);

  if (ctx.mode !== 'deep' || ctx.message.length < 25) {
    return [base];
  }

  const prompt = `
You are helping generate alternate queries for better search recall.

Original rewritten query: ${JSON.stringify(base)}

Generate ONE alternate rewritten query that:
- Emphasizes different facets (e.g., budget vs location, dates vs amenities)
- Keeps the same overall intent
- Is concise and explicit

Return ONLY the alternate query as plain text (no JSON, no explanation).
`;
  const raw = await callSmallLLM(prompt);
  const alt = raw.trim();

  if (!alt || alt.toLowerCase() === base.toLowerCase()) {
    return [base];
  }
  return [base, alt];
}

// Step C: Extract product filters (now receives rewritten query + context for history-aware extraction)
async function extractProductFilters(rewrittenQuery: string, ctx: QueryContext): Promise<ProductFilters> {
  const recentHistory = ctx.history.slice(-3);
  const prompt = `
Extract product search filters from the rewritten query.
Return JSON:
{
  "query": string,
  "category": string|null,
  "budgetMin": number|null,
  "budgetMax": number|null,
  "brands": string[]|null,
  "attributes": object|null
}

Rewritten query: ${JSON.stringify(rewrittenQuery)}
Recent history (for context): ${JSON.stringify(recentHistory)}
`;
  const raw = await callSmallLLM(prompt);
  const p = safeParseJson(raw, 'extractProductFilters');
  let budgetMin = typeof p.budgetMin === 'number' && p.budgetMin >= 0 ? p.budgetMin : undefined;
  let budgetMax = typeof p.budgetMax === 'number' && p.budgetMax > 0 ? p.budgetMax : undefined;
  if (budgetMin != null && budgetMax != null && budgetMax < budgetMin) {
    [budgetMin, budgetMax] = [budgetMax, budgetMin];
  }
  return {
    query: typeof p.query === 'string' ? p.query : rewrittenQuery,
    category: typeof p.category === 'string' ? p.category : undefined,
    budgetMin,
    budgetMax,
    brands: Array.isArray(p.brands) ? p.brands : undefined,
    attributes: typeof p.attributes === 'object' && p.attributes !== null ? p.attributes : undefined,
  };
}

// Step C: Extract hotel filters with history-aware resolution
async function extractHotelFilters(rewrittenQuery: string, ctx: QueryContext): Promise<HotelFilters> {
  const recentHistory = (ctx.history ?? []).slice(-5);
  const prompt = `
Extract hotel search filters from the rewritten query.
Use history to resolve vague references (e.g., "there" → previous city, "this weekend" → specific dates).
If the user says "my budget", "in my price range", or "same budget", infer budgetMin/budgetMax from history when they mentioned a price in prior messages.

Return JSON:
{
  "destination": string,        // city name (required)
  "checkIn": string|null,       // YYYY-MM-DD (null if not specified)
  "checkOut": string|null,      // YYYY-MM-DD (null if not specified)
  "guests": number|null,        // number of guests (null if not specified)
  "budgetMin": number|null,     // minimum price per night
  "budgetMax": number|null,     // maximum price per night
  "area": string|null,          // neighborhood/area name
  "amenities": string[]|null    // e.g., ["wifi", "pool", "parking"]
}

Rewritten query: ${JSON.stringify(rewrittenQuery)}
Recent history (for context): ${JSON.stringify(recentHistory)}

Important:
- Return ONLY valid JSON. Do NOT include markdown or code fences. Use double quotes for keys and string values.
- If destination is vague ("there", "same place"), infer from history
- If dates are vague ("this weekend", "next week"), calculate specific dates
- Set fields to null if truly unknown (don't guess)
`;
  const raw = await callSmallLLM(prompt);
  const p = safeParseJson(raw, 'extractHotelFilters');
  const now = new Date();
  const defaultCheckIn = formatDate(now);
  const defaultCheckOut = formatDate(addDays(now, 1));

  const rawCheckIn = typeof p.checkIn === 'string' ? p.checkIn : null;
  const rawCheckOut = typeof p.checkOut === 'string' ? p.checkOut : null;

  let checkIn = rawCheckIn ?? defaultCheckIn;
  let checkOut = rawCheckOut ?? defaultCheckOut;

  if (checkOut < checkIn) {
    checkOut = formatDate(addDays(new Date(checkIn), 1));
  }

  const guests =
    typeof p.guests === 'number' && p.guests > 0 && p.guests < 20
      ? p.guests
      : 2;

  let budgetMin = typeof p.budgetMin === 'number' && p.budgetMin >= 0 ? p.budgetMin : undefined;
  let budgetMax = typeof p.budgetMax === 'number' && p.budgetMax > 0 ? p.budgetMax : undefined;
  if (budgetMin != null && budgetMax != null && budgetMax < budgetMin) {
    [budgetMin, budgetMax] = [budgetMax, budgetMin];
  }

  return {
    destination: typeof p.destination === 'string' && p.destination.trim()
      ? p.destination.trim()
      : 'unknown',
    checkIn,
    checkOut,
    guests,
    budgetMin,
    budgetMax,
    area: typeof p.area === 'string' ? p.area : undefined,
    amenities: Array.isArray(p.amenities) ? p.amenities : undefined,
  };
}

// Step C: Extract flight filters with history-aware resolution
async function extractFlightFilters(rewrittenQuery: string, ctx: QueryContext): Promise<FlightFilters> {
  const recentHistory = ctx.history.slice(-3);
  const prompt = `
Extract flight search filters from the rewritten query.
Use history to resolve vague references (e.g., "there" → previous destination).

Return JSON:
{
  "origin": string,          // IATA code or city name
  "destination": string,     // IATA code or city name
  "departDate": string|null, // YYYY-MM-DD (null if not specified)
  "returnDate": string|null, // YYYY-MM-DD (null if one-way or not specified)
  "adults": number|null,     // number of adults
  "cabin": "economy"|"premium"|"business"|"first"|null
}

Important: Return ONLY valid JSON. Do NOT include markdown or code fences. Use double quotes for keys and string values.

Rewritten query: ${JSON.stringify(rewrittenQuery)}
Recent history (for context): ${JSON.stringify(recentHistory)}
`;
  const raw = await callSmallLLM(prompt);
  const p = safeParseJson(raw, 'extractFlightFilters');
  const defaultDate = new Date().toISOString().slice(0, 10);
  const adults =
    typeof p.adults === 'number' && p.adults > 0 && p.adults <= 9
      ? p.adults
      : 1;
  return {
    origin: typeof p.origin === 'string' ? p.origin : 'unknown',
    destination: typeof p.destination === 'string' ? p.destination : 'unknown',
    departDate: typeof p.departDate === 'string' ? p.departDate : defaultDate,
    returnDate: typeof p.returnDate === 'string' ? p.returnDate : undefined,
    adults,
    cabin:
      typeof p.cabin === 'string' && ['economy', 'premium', 'business', 'first'].includes(p.cabin)
        ? (p.cabin as 'economy' | 'premium' | 'business' | 'first')
        : undefined,
  };
}

// Step C: Extract movie filters with history-aware resolution
async function extractMovieFilters(rewrittenQuery: string, ctx: QueryContext): Promise<MovieTicketFilters> {
  const recentHistory = ctx.history.slice(-3);
  const prompt = `
Extract movie ticket booking filters from the rewritten query.
Use history to resolve vague references (e.g., "there" → previous city, "this weekend" → specific date).

Return JSON:
{
  "city": string,            // city name (required)
  "movieTitle": string|null, // movie name if specified
  "date": string|null,       // YYYY-MM-DD (null if not specified)
  "timeWindow": string|null, // "morning"|"afternoon"|"evening"|"night"|null
  "tickets": number|null,    // number of seats
  "format": string|null      // "IMAX"|"3D"|"2D"|null
}

Important: Return ONLY valid JSON. Do NOT include markdown or code fences. Use double quotes for keys and string values.

Rewritten query: ${JSON.stringify(rewrittenQuery)}
Recent history (for context): ${JSON.stringify(recentHistory)}
`;
  const raw = await callSmallLLM(prompt);
  const p = safeParseJson(raw, 'extractMovieFilters');
  const defaultDate = new Date().toISOString().slice(0, 10);
  const tickets =
    typeof p.tickets === 'number' && p.tickets > 0 && p.tickets <= 20
      ? p.tickets
      : 2;
  return {
    city: typeof p.city === 'string' ? p.city : 'unknown',
    movieTitle: typeof p.movieTitle === 'string' ? p.movieTitle : undefined,
    date: typeof p.date === 'string' ? p.date : defaultDate,
    timeWindow: typeof p.timeWindow === 'string' ? p.timeWindow : undefined,
    tickets,
    format: typeof p.format === 'string' ? p.format : undefined,
  };
}

function formatDate(d: Date): string {
  return d.toISOString().slice(0, 10);
}

function addDays(d: Date, days: number): Date {
  const out = new Date(d);
  out.setDate(out.getDate() + days);
  return out;
}
