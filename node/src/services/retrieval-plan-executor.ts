/**
 * Stage 5 of the 7-stage flow: Execute the retrieval plan.
 * Runs each step in order; injects previous step result when context_from_step is set.
 * Returns chunks + bySource for merge and synthesis.
 */
import type { QueryContext } from '@/types/core';
import type { RetrievalPlan, RetrievalStep, RetrievalToolName } from './retrieval-plan';
import type { RetrievedChunk } from './retrieval-router';
import type { OrchestratorDeps } from './orchestrator';
import { perplexityOverview } from './providers/web/perplexity-web';
import { fetchWeather } from './providers/weather/open-meteo-weather';
import { logger } from './logger';
import type { Vertical } from '@/types/core';

export type ExecutePlanDeps = OrchestratorDeps;

export interface ExecuteRetrievalPlanResult {
  chunks: RetrievedChunk[];
  bySource: {
    hotel?: import('./providers/hotels/hotel-provider').Hotel[];
    flight?: import('./providers/flights/flight-provider').Flight[];
    product?: import('./providers/catalog/catalog-provider').Product[];
    movie?: import('./providers/movies/movie-provider').MovieShowtime[];
  };
  searchQueries: string[];
  primaryVertical: Vertical;
}

const SOURCE_BY_TOOL: Record<RetrievalToolName, RetrievedChunk['source']> = {
  weather_search: 'web',
  hotel_search: 'hotel',
  product_search: 'product',
  flight_search: 'flight',
  movie_search: 'movie',
  web_search: 'web',
};

function snippetToChunk(
  s: { id: string; title: string; url: string; text: string; score: number },
  source: RetrievedChunk['source'],
): RetrievedChunk {
  return {
    id: s.id,
    url: s.url,
    title: s.title,
    text: s.text,
    score: s.score,
    source,
  };
}

/** Inject context from a previous step into args (e.g. preferenceContext for product_search). */
function injectContextIntoArgs(
  args: Record<string, unknown>,
  contextText: string,
  tool: RetrievalToolName,
): Record<string, unknown> {
  const out = { ...args };
  if (tool === 'product_search' || tool === 'hotel_search' || tool === 'flight_search' || tool === 'movie_search') {
    out.preferenceContext = (out.preferenceContext as string) ? `${out.preferenceContext}\n${contextText}` : contextText;
  }
  if (tool === 'product_search' && typeof out.query === 'string') {
    out.query = `${out.query}\n[Context: ${contextText.slice(0, 300)}]`;
  }
  return out;
}

/** Run a single step and return chunks + bySource slice. */
async function runOneStep(
  step: RetrievalStep,
  stepResults: (unknown)[],
  _ctx: QueryContext,
  deps: ExecutePlanDeps,
): Promise<{ chunks: RetrievedChunk[]; bySource: ExecuteRetrievalPlanResult['bySource'] }> {
  let args = { ...step.args };
  if (step.context_from_step != null && step.context_from_step >= 1 && step.context_from_step <= stepResults.length) {
    const prev = stepResults[step.context_from_step - 1];
    const contextText = typeof prev === 'string' ? prev : JSON.stringify(prev);
    args = injectContextIntoArgs(args, contextText, step.tool);
  }

  const chunks: RetrievedChunk[] = [];
  const bySource: ExecuteRetrievalPlanResult['bySource'] = {};

  switch (step.tool) {
    case 'weather_search': {
      const location = String(args.location ?? '');
      const date = String(args.date ?? new Date().toISOString().slice(0, 10));
      const weather = await fetchWeather(location, date);
      const weatherText = JSON.stringify(weather);
      chunks.push({
        id: `weather-${step.tool}-${date}`,
        url: '',
        title: '',
        text: `Weather (${location}, ${date}): ${weatherText}`,
        score: 1,
        source: 'web',
      });
      stepResults.push(weather);
      break;
    }
    case 'hotel_search': {
      const res = await deps.hotelRetriever.searchHotels({
        rewrittenQuery: String(args.rewrittenQuery ?? ''),
        destination: String(args.destination ?? ''),
        checkIn: String(args.checkIn ?? new Date().toISOString().slice(0, 10)),
        checkOut: String(args.checkOut ?? new Date(Date.now() + 86400000).toISOString().slice(0, 10)),
        guests: Number(args.guests ?? 2),
        ...(args.budgetMin != null && { budgetMin: Number(args.budgetMin) }),
        ...(args.budgetMax != null && { budgetMax: Number(args.budgetMax) }),
        ...(args.area != null && { area: String(args.area) }),
        ...(args.amenities != null && { amenities: args.amenities as string[] }),
        ...(args.preferenceContext != null && { preferenceContext: args.preferenceContext as string }),
      });
      stepResults.push({ hotels: res.hotels, snippets: res.snippets });
      res.snippets.forEach((s) => chunks.push(snippetToChunk(s, 'hotel')));
      if (res.hotels?.length) bySource.hotel = res.hotels;
      break;
    }
    case 'product_search': {
      const res = await deps.productRetriever.searchProducts({
        query: String(args.query ?? args.rewrittenQuery ?? ''),
        rewrittenQuery: String(args.rewrittenQuery ?? args.query ?? ''),
        ...(args.category != null && { category: String(args.category) }),
        ...(args.budgetMin != null && { budgetMin: Number(args.budgetMin) }),
        ...(args.budgetMax != null && { budgetMax: Number(args.budgetMax) }),
        ...(args.brands != null && { brands: args.brands as string[] }),
        ...(args.preferenceContext != null && { preferenceContext: args.preferenceContext as string }),
      });
      stepResults.push({ products: res.products, snippets: res.snippets });
      res.snippets.forEach((s) => chunks.push(snippetToChunk(s, 'product')));
      if (res.products?.length) bySource.product = res.products;
      break;
    }
    case 'flight_search': {
      const res = await deps.flightRetriever.searchFlights({
        rewrittenQuery: String(args.rewrittenQuery ?? ''),
        origin: String(args.origin ?? ''),
        destination: String(args.destination ?? ''),
        departDate: String(args.departDate ?? new Date().toISOString().slice(0, 10)),
        returnDate: args.returnDate != null ? String(args.returnDate) : undefined,
        adults: Number(args.adults ?? 1),
        ...(args.cabin != null && { cabin: args.cabin as 'economy' | 'premium' | 'business' | 'first' }),
        ...(args.preferenceContext != null && { preferenceContext: args.preferenceContext as string }),
      });
      stepResults.push({ flights: res.flights, snippets: res.snippets });
      res.snippets.forEach((s) => chunks.push(snippetToChunk(s, 'flight')));
      if (res.flights?.length) bySource.flight = res.flights;
      break;
    }
    case 'movie_search': {
      const res = await deps.movieRetriever.searchShowtimes({
        rewrittenQuery: String(args.rewrittenQuery ?? ''),
        city: String(args.city ?? ''),
        date: String(args.date ?? new Date().toISOString().slice(0, 10)),
        movieTitle: args.movieTitle != null ? String(args.movieTitle) : undefined,
        timeWindow: args.timeWindow != null ? String(args.timeWindow) : undefined,
        tickets: Number(args.tickets ?? 2),
        ...(args.format != null && { format: String(args.format) }),
        ...(args.preferenceContext != null && { preferenceContext: args.preferenceContext as string }),
      });
      stepResults.push({ showtimes: res.showtimes, snippets: res.snippets });
      res.snippets.forEach((s) => chunks.push(snippetToChunk(s, 'movie')));
      if (res.showtimes?.length) bySource.movie = res.showtimes;
      break;
    }
    case 'web_search': {
      const query = String(args.query ?? '');
      const overview = await perplexityOverview(query);
      overview.citations?.forEach((c, i) => {
        chunks.push({
          id: c.id ?? `web-${i}`,
          url: c.url ?? '',
          title: c.title,
          text: c.snippet ?? '',
          score: 0.8,
          source: 'web',
          date: c.date,
        });
      });
      stepResults.push({ web: overview });
      break;
    }
    default:
      stepResults.push({});
  }

  return { chunks, bySource };
}

/**
 * Execute the retrieval plan: run each step in order, inject context when context_from_step is set,
 * aggregate chunks and bySource.
 * Defensive: if plan has no steps, fallback to a single web_search.
 */
export async function executeRetrievalPlan(
  plan: RetrievalPlan,
  ctx: QueryContext,
  deps: ExecutePlanDeps,
): Promise<ExecuteRetrievalPlanResult> {
  const effectivePlan: RetrievalPlan =
    plan.steps?.length > 0
      ? plan
      : { steps: [{ tool: 'web_search', args: { query: ctx.message?.trim() || 'search' } }] };

  const allChunks: RetrievedChunk[] = [];
  const aggregatedBySource: ExecuteRetrievalPlanResult['bySource'] = {};
  const searchQueries: string[] = [];
  const stepResults: unknown[] = [];

  for (const step of effectivePlan.steps) {
    const { chunks, bySource } = await runOneStep(step, stepResults, ctx, deps);
    allChunks.push(...chunks);
    if (bySource.hotel?.length) aggregatedBySource.hotel = [...(aggregatedBySource.hotel ?? []), ...bySource.hotel];
    if (bySource.flight?.length) aggregatedBySource.flight = [...(aggregatedBySource.flight ?? []), ...bySource.flight];
    if (bySource.product?.length) aggregatedBySource.product = [...(aggregatedBySource.product ?? []), ...bySource.product];
    if (bySource.movie?.length) aggregatedBySource.movie = [...(aggregatedBySource.movie ?? []), ...bySource.movie];
    const q = step.args.query ?? step.args.rewrittenQuery ?? ctx.message;
    if (typeof q === 'string') searchQueries.push(q);
  }

  const primaryVertical: Vertical = aggregatedBySource.hotel?.length
    ? 'hotel'
    : aggregatedBySource.flight?.length
      ? 'flight'
      : aggregatedBySource.product?.length
        ? 'product'
        : aggregatedBySource.movie?.length
          ? 'movie'
          : 'other';

  logger.info('flow:executor_done', {
    step: 'executor_done',
    totalChunks: allChunks.length,
    primaryVertical,
    hotel: aggregatedBySource.hotel?.length ?? 0,
    flight: aggregatedBySource.flight?.length ?? 0,
    product: aggregatedBySource.product?.length ?? 0,
    movie: aggregatedBySource.movie?.length ?? 0,
    searchQueriesCount: searchQueries.length,
  });
  return {
    chunks: allChunks,
    bySource: aggregatedBySource,
    searchQueries: searchQueries.length ? searchQueries : [ctx.message],
    primaryVertical,
  };
}
