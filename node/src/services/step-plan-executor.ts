/**
 * Layer 2: Execute a StepPlan — run each step (evaluate runIf), call capability tools, synthesize answer.
 */
import type { StepPlan, Step } from '@/types/planning';
import { callHotelSearch } from '@/mcp/capability-client';
import { callFlightSearch } from '@/mcp/capability-client';
import { callProductSearch } from '@/mcp/capability-client';
import { callMovieSearch } from '@/mcp/capability-client';
import { callWeatherSearch } from '@/mcp/capability-client';
import { callSmallLLM } from './llm-small';
import { callMainLLM } from './llm-main';

/** Minimal citation shape; orchestrator converts to its Citation type. */
export interface StepCitation {
  id: string;
  url: string;
  title?: string;
  snippet?: string;
  date?: string;
  last_updated?: string;
}

const CAPABILITY_NAMES = [
  'hotel_search',
  'flight_search',
  'product_search',
  'movie_search',
  'weather_search',
] as const;

export interface StepPlanExecutionResult {
  summary: string;
  citations: StepCitation[];
  stepOutputs: Map<string, unknown>;
  searchQueries: string[];
  /** Primary vertical for UI if we can infer (e.g. hotel from hotel_search step). */
  inferredVertical: 'product' | 'hotel' | 'flight' | 'movie' | 'other';
  /** Collected cards for UI (hotels, products, etc.) when steps return them. */
  hotels?: import('@/services/providers/hotels/hotel-provider').Hotel[];
  products?: import('@/services/providers/catalog/catalog-provider').Product[];
  flights?: import('@/services/providers/flights/flight-provider').Flight[];
  showtimes?: import('@/services/providers/movies/movie-provider').MovieShowtime[];
}

/** Evaluate runIf condition given the referenced step's output. Returns true to run the step. */
async function evaluateRunIf(
  runIf: string,
  conditionOnStepId: string | undefined,
  stepOutputs: Map<string, unknown>,
): Promise<boolean> {
  const refOutput = conditionOnStepId ? stepOutputs.get(conditionOnStepId) : undefined;
  if (refOutput === undefined) return true; // no prior output → run step
  const prompt = `Given this JSON output from a previous step, does the condition hold?

Condition: "${runIf}"

Previous step output (JSON): ${JSON.stringify(refOutput)}

Answer with JSON only: {"holds": true or false}. No explanation.`;
  try {
    const raw = await callSmallLLM(prompt);
    const parsed = JSON.parse(raw) as { holds?: boolean };
    return parsed?.holds === true;
  } catch {
    return true; // on parse/LLM error, run the step
  }
}

/** Dispatch one step to the right capability and return the result. */
async function runStep(step: Step): Promise<unknown> {
  const cap = step.capability as (typeof CAPABILITY_NAMES)[number];
  const input = step.input as Record<string, unknown>;

  switch (cap) {
    case 'weather_search': {
      const loc = typeof input.location === 'string' ? input.location : '';
      const date = typeof input.date === 'string' ? input.date : new Date().toISOString().slice(0, 10);
      const res = await callWeatherSearch({ location: loc, date });
      return res.weather;
    }
    case 'hotel_search': {
      const res = await callHotelSearch({
        rewrittenQuery: String(input.rewrittenQuery ?? ''),
        destination: String(input.destination ?? ''),
        checkIn: String(input.checkIn ?? ''),
        checkOut: String(input.checkOut ?? ''),
        guests: Number(input.guests ?? 2),
        ...(input.budgetMin != null && { budgetMin: Number(input.budgetMin) }),
        ...(input.budgetMax != null && { budgetMax: Number(input.budgetMax) }),
        ...(input.area != null && { area: String(input.area) }),
        ...(input.amenities != null && { amenities: (input.amenities as string[]) }),
        ...(input.preferenceContext != null && { preferenceContext: input.preferenceContext as string | string[] }),
      });
      return { hotels: res.hotels, snippets: res.snippets };
    }
    case 'flight_search': {
      const res = await callFlightSearch({
        rewrittenQuery: String(input.rewrittenQuery ?? ''),
        origin: String(input.origin ?? ''),
        destination: String(input.destination ?? ''),
        departDate: String(input.departDate ?? ''),
        returnDate: input.returnDate != null ? String(input.returnDate) : undefined,
        adults: Number(input.adults ?? 1),
        ...(input.cabin != null && { cabin: input.cabin as 'economy' | 'premium' | 'business' | 'first' }),
        ...(input.preferenceContext != null && { preferenceContext: input.preferenceContext as string | string[] }),
      });
      return { flights: res.flights, snippets: res.snippets };
    }
    case 'product_search': {
      const res = await callProductSearch({
        query: String(input.query ?? input.rewrittenQuery ?? ''),
        rewrittenQuery: String(input.rewrittenQuery ?? input.query ?? ''),
        ...(input.category != null && { category: String(input.category) }),
        ...(input.budgetMin != null && { budgetMin: Number(input.budgetMin) }),
        ...(input.budgetMax != null && { budgetMax: Number(input.budgetMax) }),
        ...(input.brands != null && { brands: input.brands as string[] }),
        ...(input.attributes != null && { attributes: input.attributes as Record<string, string | number | boolean> }),
        ...(input.preferenceContext != null && { preferenceContext: input.preferenceContext as string | string[] }),
      });
      return { products: res.products, snippets: res.snippets };
    }
    case 'movie_search': {
      const res = await callMovieSearch({
        rewrittenQuery: String(input.rewrittenQuery ?? ''),
        city: String(input.city ?? ''),
        date: String(input.date ?? ''),
        movieTitle: input.movieTitle != null ? String(input.movieTitle) : undefined,
        timeWindow: input.timeWindow != null ? String(input.timeWindow) : undefined,
        tickets: Number(input.tickets ?? 2),
        ...(input.format != null && { format: String(input.format) }),
        ...(input.preferenceContext != null && { preferenceContext: input.preferenceContext as string | string[] }),
      });
      return { showtimes: res.showtimes, snippets: res.snippets };
    }
    default:
      return { error: `Unknown capability: ${step.capability}` };
  }
}

/** Execute the full StepPlan and return summary + step outputs + any cards. */
export async function executeStepPlan(plan: StepPlan): Promise<StepPlanExecutionResult> {
  const stepOutputs = new Map<string, unknown>();
  const searchQueries: string[] = [plan.rewrittenPrompt];
  let inferredVertical: StepPlanExecutionResult['inferredVertical'] = 'other';
  const collected: {
    hotels?: import('@/services/providers/hotels/hotel-provider').Hotel[];
    products?: import('@/services/providers/catalog/catalog-provider').Product[];
    flights?: import('@/services/providers/flights/flight-provider').Flight[];
    showtimes?: import('@/services/providers/movies/movie-provider').MovieShowtime[];
  } = {};

  for (const step of plan.steps) {
    if (step.runIf != null) {
      const shouldRun = await evaluateRunIf(step.runIf, step.conditionOnStepId, stepOutputs);
      if (!shouldRun) continue;
    }

    const output = await runStep(step);
    stepOutputs.set(step.id, output);

    const out = output as Record<string, unknown>;
    if (out?.hotels && Array.isArray(out.hotels)) {
      collected.hotels = [...(collected.hotels ?? []), ...(out.hotels as import('@/services/providers/hotels/hotel-provider').Hotel[])];
      if (inferredVertical === 'other') inferredVertical = 'hotel';
    }
    if (out?.products && Array.isArray(out.products)) {
      collected.products = [...(collected.products ?? []), ...(out.products as import('@/services/providers/catalog/catalog-provider').Product[])];
      if (inferredVertical === 'other') inferredVertical = 'product';
    }
    if (out?.flights && Array.isArray(out.flights)) {
      collected.flights = [...(collected.flights ?? []), ...(out.flights as import('@/services/providers/flights/flight-provider').Flight[])];
      if (inferredVertical === 'other') inferredVertical = 'flight';
    }
    if (out?.showtimes && Array.isArray(out.showtimes)) {
      collected.showtimes = [...(collected.showtimes ?? []), ...(out.showtimes as import('@/services/providers/movies/movie-provider').MovieShowtime[])];
      if (inferredVertical === 'other') inferredVertical = 'movie';
    }
  }

  const outputsSummary = Array.from(stepOutputs.entries())
    .map(([id, v]) => `${id}: ${JSON.stringify(v)}`)
    .join('\n');

  const system = `You are a helpful assistant. The user asked: "${plan.rewrittenPrompt}"

Goal for your answer: ${plan.goal}

Below are the results from each step that was executed (tools: weather, hotels, flights, products, movies). Synthesize a clear, useful answer that addresses the user's request. Use the step data to give specific information (e.g. weather, hotel names, prices). Do not invent data. If a step was skipped due to a condition, mention that when relevant.`;

  const userContent = `Step outputs:\n${outputsSummary}`;
  const summary = await callMainLLM(system, userContent);

  return {
    summary: summary.trim(),
    citations: [],
    stepOutputs,
    searchQueries,
    inferredVertical,
    ...collected,
  };
}
