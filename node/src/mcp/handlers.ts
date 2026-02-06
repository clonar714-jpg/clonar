/**
 * In-process MCP tool handlers. Return standard envelope; no raw provider errors leak.
 * Provider/API response caching lives here (MCP server boundary).
 * Hotel_search implements provider failover: primary → secondary on retryable error.
 */
import { LRUCache } from 'lru-cache';
import { getRetrieversForMcpHandlers } from '@/services/pipeline-deps';
import type {
  ProductSearchToolInput,
  HotelSearchToolInput,
  FlightSearchToolInput,
  MovieSearchToolInput,
  WeatherSearchToolInput,
} from '@/mcp/tool-contract';
import { fetchWeather } from '@/services/providers/weather/open-meteo-weather';
import {
  envelopeOk,
  envelopeErr,
  toRetryable,
  type McpToolEnvelope,
} from '@/mcp/envelope';

const PROVIDER_CACHE_TTL_MS = 60_000;
const PROVIDER_CACHE_MAX = 500;

const providerCache = new LRUCache<string, McpToolEnvelope>({
  max: PROVIDER_CACHE_MAX,
  ttl: PROVIDER_CACHE_TTL_MS,
});

function cacheKey(tool: string, input: Record<string, unknown>): string {
  return `${tool}:${JSON.stringify(input)}`;
}

async function runProductHandler(input: ProductSearchToolInput): Promise<McpToolEnvelope> {
  const key = cacheKey('product_search', input);
  const cached = providerCache.get(key);
  if (cached) return cached;
  try {
    const deps = getRetrieversForMcpHandlers();
    const result = await deps.productRetriever.searchProducts(input);
    const envelope = envelopeOk({ products: result.products }, result.snippets);
    providerCache.set(key, envelope);
    return envelope;
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    const retryable = toRetryable(err);
    return envelopeErr('PRODUCT_SEARCH_FAILED', msg, retryable);
  }
}

/** Hotel: primary provider; on retryable error try secondary (fallback). App is unaware of which provider was used. */
async function runHotelHandler(input: HotelSearchToolInput): Promise<McpToolEnvelope> {
  const key = cacheKey('hotel_search', input);
  const cached = providerCache.get(key);
  if (cached) return cached;
  const deps = getRetrieversForMcpHandlers();
  try {
    const result = await deps.hotelRetriever.searchHotels(input);
    const envelope = envelopeOk({ hotels: result.hotels }, result.snippets);
    providerCache.set(key, envelope);
    return envelope;
  } catch (primaryErr) {
    const retryable = toRetryable(primaryErr);
    if (retryable) {
      try {
        const result = await deps.hotelRetriever.searchHotels(input);
        const envelope = envelopeOk({ hotels: result.hotels }, result.snippets);
        providerCache.set(key, envelope);
        return envelope;
      } catch {
        const fallback: McpToolEnvelope = envelopeOk({ hotels: [] }, []);
        providerCache.set(key, fallback);
        return fallback;
      }
    }
    const msg = primaryErr instanceof Error ? primaryErr.message : String(primaryErr);
    return envelopeErr('HOTEL_SEARCH_FAILED', msg, false);
  }
}

async function runFlightHandler(input: FlightSearchToolInput): Promise<McpToolEnvelope> {
  const key = cacheKey('flight_search', input);
  const cached = providerCache.get(key);
  if (cached) return cached;
  try {
    const deps = getRetrieversForMcpHandlers();
    const result = await deps.flightRetriever.searchFlights(input);
    const envelope = envelopeOk({ flights: result.flights }, result.snippets);
    providerCache.set(key, envelope);
    return envelope;
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    const retryable = toRetryable(err);
    return envelopeErr('FLIGHT_SEARCH_FAILED', msg, retryable);
  }
}

async function runMovieHandler(input: MovieSearchToolInput): Promise<McpToolEnvelope> {
  const key = cacheKey('movie_search', input);
  const cached = providerCache.get(key);
  if (cached) return cached;
  try {
    const deps = getRetrieversForMcpHandlers();
    const result = await deps.movieRetriever.searchShowtimes(input);
    const envelope = envelopeOk({ showtimes: result.showtimes }, result.snippets);
    providerCache.set(key, envelope);
    return envelope;
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    const retryable = toRetryable(err);
    return envelopeErr('MOVIE_SEARCH_FAILED', msg, retryable);
  }
}

async function runWeatherHandler(input: WeatherSearchToolInput): Promise<McpToolEnvelope> {
  const key = cacheKey('weather_search', input);
  const cached = providerCache.get(key);
  if (cached) return cached;
  try {
    const weather = await fetchWeather(input.location, input.date);
    const envelope = envelopeOk({ weather }, []);
    providerCache.set(key, envelope);
    return envelope;
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    const retryable = toRetryable(err);
    return envelopeErr('WEATHER_SEARCH_FAILED', msg, retryable);
  }
}

export async function handleProductSearch(input: ProductSearchToolInput): Promise<McpToolEnvelope> {
  return runProductHandler(input);
}

export async function handleHotelSearch(input: HotelSearchToolInput): Promise<McpToolEnvelope> {
  return runHotelHandler(input);
}

export async function handleFlightSearch(input: FlightSearchToolInput): Promise<McpToolEnvelope> {
  return runFlightHandler(input);
}

export async function handleMovieSearch(input: MovieSearchToolInput): Promise<McpToolEnvelope> {
  return runMovieHandler(input);
}

export async function handleWeatherSearch(input: WeatherSearchToolInput): Promise<McpToolEnvelope> {
  return runWeatherHandler(input);
}
