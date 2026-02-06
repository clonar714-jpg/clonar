// src/services/filter-extraction.ts
// Extract structured filters from NL (explicit + implicit from session) for APIs that need
// temporal, categorical, content-type, permission filters. Per article: don't over-restrict;
// merge session defaults with query-extracted overrides.
import type { QueryContext } from '@/types/core';
import type {
  HotelFilters,
  FlightFilters,
  ProductFilters,
  MovieTicketFilters,
} from '@/types/verticals';
import { callSmallLlmJson } from './llm-small';
import { logger } from './logger';

/** Partial filters per vertical (extractor fills what it can; we merge with defaults). */
export interface ExtractedFilters {
  hotel?: Partial<HotelFilters>;
  flight?: Partial<FlightFilters>;
  product?: Partial<ProductFilters>;
  movie?: Partial<MovieTicketFilters>;
}

const FILTER_EXTRACTION_TIMEOUT_MS = 6_000;

function formatDate(d: Date): string {
  return d.toISOString().slice(0, 10);
}
function addDays(d: Date, days: number): Date {
  const out = new Date(d);
  out.setDate(out.getDate() + days);
  return out;
}

/** Default required fields for hotel (APIs need these). */
export function getDefaultHotelFilterValues(): Pick<
  HotelFilters,
  'destination' | 'checkIn' | 'checkOut' | 'guests'
> {
  const now = new Date();
  return {
    destination: 'unknown',
    checkIn: formatDate(now),
    checkOut: formatDate(addDays(now, 1)),
    guests: 2,
  };
}

export function getDefaultFlightFilterValues(): Pick<
  FlightFilters,
  'origin' | 'destination' | 'departDate' | 'adults'
> {
  const now = new Date();
  return {
    origin: '',
    destination: 'unknown',
    departDate: formatDate(now),
    adults: 1,
  };
}

export function getDefaultProductFilterValues(): Pick<ProductFilters, 'query'> {
  return { query: '' };
}

export function getDefaultMovieFilterValues(): Pick<
  MovieTicketFilters,
  'city' | 'date' | 'tickets'
> {
  const now = new Date();
  return {
    city: 'unknown',
    date: formatDate(now),
    tickets: 2,
  };
}

const EXTRACT_SYSTEM = `You extract structured search filters from a user's rewritten query and optional context.
Output ONLY valid JSON with optional keys: hotel, flight, product, movie.
- hotel: { destination?: string (city/place), checkIn?: string (YYYY-MM-DD), checkOut?: string (YYYY-MM-DD), guests?: number, amenities?: string[], area?: string, budgetMin?: number, budgetMax?: number }
- flight: { origin?: string (airport/city), destination?: string, departDate?: string (YYYY-MM-DD), returnDate?: string, adults?: number, cabin?: "economy"|"premium"|"business"|"first" }
- product: { query?: string, category?: string, budgetMin?: number, budgetMax?: number, brands?: string[] }
- movie: { city?: string, movieTitle?: string, date?: string (YYYY-MM-DD), timeWindow?: string, tickets?: number, format?: string }
Only include a vertical if the query clearly implies it. Use relative dates when the user says "this weekend", "next week", etc. (output YYYY-MM-DD).
Do not invent values; leave fields out if not stated or implied. Output {} when nothing to extract.`;

function buildExtractUserPrompt(rewrittenPrompt: string, ctx: QueryContext): string {
  const parts: string[] = [
    `Rewritten query: "${rewrittenPrompt}"`,
  ];
  if (ctx.conversationThread?.length) {
    parts.push(
      'Conversation so far (use for implicit context only):',
      ctx.conversationThread
        .map((t) => `Q: ${t.query}\nA: (summary)`)
        .join('\n')
    );
  }
  const lastHotel = ctx.lastHotelFilters;
  const lastFlight = ctx.lastFlightFilters;
  const lastProduct = ctx.lastProductFilters;
  const lastMovie = ctx.lastMovieFilters;
  if (lastHotel || lastFlight || lastProduct || lastMovie) {
    parts.push('Last-used filters from session (use as fallback only; query overrides):');
    if (lastHotel) parts.push(`Hotel: ${JSON.stringify(lastHotel)}`);
    if (lastFlight) parts.push(`Flight: ${JSON.stringify(lastFlight)}`);
    if (lastProduct) parts.push(`Product: ${JSON.stringify(lastProduct)}`);
    if (lastMovie) parts.push(`Movie: ${JSON.stringify(lastMovie)}`);
  }
  parts.push('\nOutput JSON only (no markdown):');
  return parts.join('\n');
}

function safeParseExtracted(raw: string): ExtractedFilters {
  try {
    const parsed = JSON.parse(raw);
    if (parsed && typeof parsed === 'object') {
      const out: ExtractedFilters = {};
      if (parsed.hotel && typeof parsed.hotel === 'object') out.hotel = parsed.hotel;
      if (parsed.flight && typeof parsed.flight === 'object') out.flight = parsed.flight;
      if (parsed.product && typeof parsed.product === 'object') out.product = parsed.product;
      if (parsed.movie && typeof parsed.movie === 'object') out.movie = parsed.movie;
      return out;
    }
  } catch (_) {
    // ignore
  }
  return {};
}

/**
 * Extract filters from NL (rewritten prompt + conversation + session last-used).
 * Merges: default required fields <- session last*Filters <- extracted from query.
 * Do not over-restrict: extraction is best-effort; retrieval can still widen.
 */
export async function extractFilters(
  ctx: QueryContext,
  rewrittenPrompt: string
): Promise<ExtractedFilters> {
  const userPrompt = buildExtractUserPrompt(rewrittenPrompt, ctx);
  try {
    const raw = await Promise.race([
      callSmallLlmJson({ system: EXTRACT_SYSTEM, user: userPrompt }),
      new Promise<string>((_, reject) =>
        setTimeout(() => reject(new Error('filter_extraction_timeout')), FILTER_EXTRACTION_TIMEOUT_MS)
      ),
    ]);
    const extracted = safeParseExtracted(raw);

    // Merge session defaults (implicit) with extracted (explicit): session as base, query overrides.
    const merged: ExtractedFilters = {};
    if (extracted.hotel || ctx.lastHotelFilters) {
      merged.hotel = {
        ...getDefaultHotelFilterValues(),
        ...ctx.lastHotelFilters,
        ...extracted.hotel,
      };
    }
    if (extracted.flight || ctx.lastFlightFilters) {
      merged.flight = {
        ...getDefaultFlightFilterValues(),
        ...ctx.lastFlightFilters,
        ...extracted.flight,
      };
    }
    if (extracted.product || ctx.lastProductFilters) {
      merged.product = {
        ...getDefaultProductFilterValues(),
        ...ctx.lastProductFilters,
        ...extracted.product,
      };
      if (merged.product && !merged.product.query) merged.product.query = rewrittenPrompt.slice(0, 200);
    }
    if (extracted.movie || ctx.lastMovieFilters) {
      merged.movie = {
        ...getDefaultMovieFilterValues(),
        ...ctx.lastMovieFilters,
        ...extracted.movie,
      };
    }
    return merged;
  } catch (err) {
    logger.warn('filter_extraction:failed', {
      err: err instanceof Error ? err.message : String(err),
    });
    // Fallback: only session defaults (no LLM extraction).
    const fallback: ExtractedFilters = {};
    if (ctx.lastHotelFilters) {
      fallback.hotel = { ...getDefaultHotelFilterValues(), ...ctx.lastHotelFilters };
    }
    if (ctx.lastFlightFilters) {
      fallback.flight = { ...getDefaultFlightFilterValues(), ...ctx.lastFlightFilters };
    }
    if (ctx.lastProductFilters) {
      fallback.product = { ...getDefaultProductFilterValues(), ...ctx.lastProductFilters, query: rewrittenPrompt.slice(0, 200) };
    }
    if (ctx.lastMovieFilters) {
      fallback.movie = { ...getDefaultMovieFilterValues(), ...ctx.lastMovieFilters };
    }
    return fallback;
  }
}
