
import type { QueryContext } from '@/types/core';
import type {
  HotelFilters,
  FlightFilters,
  ProductFilters,
  MovieTicketFilters,
} from '@/types/verticals';
import { callSmallLlmJson } from './llm-small';
import { logger } from './logger';


export interface ExtractedFilters {
  hotel?: Partial<HotelFilters>;
  flight?: Partial<FlightFilters>;
  product?: Partial<ProductFilters>;
  movie?: Partial<MovieTicketFilters>;
 
  preferenceDescription?: string;
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


function getHotelMergeDefaults(): Pick<HotelFilters, 'destination'> {
  return { destination: 'unknown' };
}

const VALID_CABINS = ['economy', 'premium', 'business', 'first'] as const;
type Cabin = (typeof VALID_CABINS)[number];

function narrowCabin(s: unknown): Cabin | undefined {
  return typeof s === 'string' && VALID_CABINS.includes(s as Cabin) ? (s as Cabin) : undefined;
}


function toPartialFlightFilters(
  raw: Record<string, unknown> & { cabin?: string }
): Partial<FlightFilters> {
  const cabin = narrowCabin(raw.cabin);
  const { cabin: _, ...rest } = raw;
  return cabin !== undefined ? { ...rest, cabin } : rest as Partial<FlightFilters>;
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


function getFlightMergeDefaults(): Pick<FlightFilters, 'origin' | 'destination'> {
  return { origin: '', destination: 'unknown' };
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


function getMovieMergeDefaults(): Pick<MovieTicketFilters, 'city'> {
  return { city: 'unknown' };
}

const EXTRACT_SYSTEM = `You extract structured search filters AND subjective preferences from a user's rewritten query and optional context.
Output ONLY valid JSON with optional keys: hotel, flight, product, movie, preferenceDescription.

Structured filters (hard constraints for APIs):
- hotel: { destination?: string (city/place), checkIn?: string (YYYY-MM-DD), checkOut?: string (YYYY-MM-DD), guests?: number, amenities?: string[], area?: string, budgetMin?: number, budgetMax?: number }
- flight: { origin?: string (airport/city), destination?: string, departDate?: string (YYYY-MM-DD), returnDate?: string, adults?: number, cabin?: "economy"|"premium"|"business"|"first" }
- product: { query?: string, category?: string, budgetMin?: number, budgetMax?: number, brands?: string[] }
- movie: { city?: string, movieTitle?: string, date?: string (YYYY-MM-DD), timeWindow?: string, tickets?: number, format?: string }

Subjective preferences (fuzzy criteria for ranking — NOT hard filters):
- preferenceDescription: A short, comma-separated list of the user's soft preferences that can mean different things to different people. Examples: "good workspace", "close to restaurants", "quiet", "romantic", "family-friendly", "boutique feel", "walkable area". Extract these from phrases like "with good workspaces", "near restaurants", "cozy", "great for working". Leave empty string or omit if the query has no such preferences.

Rules:
- Only include a vertical if the query clearly implies it. Do not add hotel/flight/product/movie when the query is generic or about another topic.
- Use relative dates when the user says "this weekend", "next week", "tomorrow" (output YYYY-MM-DD).
- Do not invent values; leave fields out if not stated or implied.
- Always extract preferenceDescription when the query mentions subjective or fuzzy criteria (workspace, near X, vibe, style, atmosphere, good for Y, etc.).

Examples:
- "hotels in Boston next weekend" → {"hotel":{"destination":"Boston","checkIn":"YYYY-MM-DD","checkOut":"YYYY-MM-DD"}}
- "boutique hotels near Boston's convention center with good workspaces and close to restaurants" → {"hotel":{"destination":"Boston","area":"convention center"},"preferenceDescription":"boutique style, good workspace, close to restaurants"}
- "running shoes under 100" → {"product":{"query":"running shoes","budgetMax":100}}
- "best laptops under 900$" or "laptops under $900" → {"product":{"query":"laptops","budgetMax":900}}
- "what is machine learning?" → {}`;

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

const DATE_ONLY_REGEX = /^\d{4}-\d{2}-\d{2}$/;

function isValidDateOnly(s: unknown): s is string {
  return typeof s === 'string' && DATE_ONLY_REGEX.test(s);
}


function sanitizeDateFields<T extends Record<string, unknown>>(
  obj: T,
  dateKeys: string[]
): T {
  const out = { ...obj };
  for (const k of dateKeys) {
    if (k in out && !isValidDateOnly(out[k])) delete out[k];
  }
  return out;
}

function safeParseExtracted(raw: string): ExtractedFilters {
  try {
    const parsed = JSON.parse(raw);
    if (parsed && typeof parsed === 'object') {
      const out: ExtractedFilters = {};
      if (parsed.hotel && typeof parsed.hotel === 'object') {
        out.hotel = sanitizeDateFields(parsed.hotel as Record<string, unknown>, ['checkIn', 'checkOut']) as Partial<HotelFilters>;
      }
      if (parsed.flight && typeof parsed.flight === 'object') {
        out.flight = sanitizeDateFields(parsed.flight as Record<string, unknown>, ['departDate', 'returnDate']) as Partial<FlightFilters>;
      }
      if (parsed.product && typeof parsed.product === 'object') out.product = parsed.product;
      if (parsed.movie && typeof parsed.movie === 'object') {
        out.movie = sanitizeDateFields(parsed.movie as Record<string, unknown>, ['date']) as Partial<MovieTicketFilters>;
      }
      if (typeof parsed.preferenceDescription === 'string' && parsed.preferenceDescription.trim()) {
        out.preferenceDescription = parsed.preferenceDescription.trim().slice(0, 500);
      }
      return out;
    }
  } catch (_) {
    // ignore
  }
  return {};
}


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

    
    const merged: ExtractedFilters = {};
    if (extracted.hotel || ctx.lastHotelFilters) {
      merged.hotel = {
        ...getHotelMergeDefaults(),
        ...ctx.lastHotelFilters,
        ...extracted.hotel,
      };
    }
    if (extracted.flight || ctx.lastFlightFilters) {
      merged.flight = toPartialFlightFilters({
        ...getFlightMergeDefaults(),
        ...ctx.lastFlightFilters,
        ...extracted.flight,
      } as Record<string, unknown> & { cabin?: string });
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
        ...getMovieMergeDefaults(),
        ...ctx.lastMovieFilters,
        ...extracted.movie,
      };
    }
    if (extracted.preferenceDescription) merged.preferenceDescription = extracted.preferenceDescription;
    return merged;
  } catch (err) {
    logger.warn('filter_extraction:failed', {
      err: err instanceof Error ? err.message : String(err),
    });
    
    const fallback: ExtractedFilters = {};
    if (ctx.lastHotelFilters) {
      fallback.hotel = { ...getHotelMergeDefaults(), ...ctx.lastHotelFilters };
    }
    if (ctx.lastFlightFilters) {
      fallback.flight = toPartialFlightFilters({
        ...getFlightMergeDefaults(),
        ...ctx.lastFlightFilters,
      } as Record<string, unknown> & { cabin?: string });
    }
    if (ctx.lastProductFilters) {
      fallback.product = { ...getDefaultProductFilterValues(), ...ctx.lastProductFilters, query: rewrittenPrompt.slice(0, 200) };
    }
    if (ctx.lastMovieFilters) {
      fallback.movie = { ...getMovieMergeDefaults(), ...ctx.lastMovieFilters };
    }
    logger.info('flow:filter_extraction', {
      step: 'filter_extraction',
      fallback: true,
      hotel: !!fallback.hotel,
      flight: !!fallback.flight,
      product: !!fallback.product,
      movie: !!fallback.movie,
      preferenceDescription: null,
    });
    return fallback;
  }
}
