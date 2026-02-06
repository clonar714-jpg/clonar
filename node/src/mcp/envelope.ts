/**
 * Standard MCP tool response contract. All capability tools return this envelope.
 * App uses ok / error.retryable for retry and fallback; no raw provider errors leak.
 */
import type { Product } from '@/services/providers/catalog/catalog-provider';
import type { Hotel } from '@/services/providers/hotels/hotel-provider';
import type { Flight } from '@/services/providers/flights/flight-provider';
import type { MovieShowtime } from '@/services/providers/movies/movie-provider';
import type { RetrievedSnippet } from '@/services/providers/retrieval-types';
import type { WeatherResult } from '@/mcp/tool-contract';

export interface McpToolError {
  code: string;
  message: string;
  retryable: boolean;
}

/** Data payload: one of products | hotels | flights | showtimes | weather. */
export type McpToolData =
  | { products: Product[] }
  | { hotels: Hotel[] }
  | { flights: Flight[] }
  | { showtimes: MovieShowtime[] }
  | { weather: WeatherResult };

export interface McpToolEnvelope {
  ok: boolean;
  data?: McpToolData;
  snippets?: RetrievedSnippet[];
  error?: McpToolError;
}

export function envelopeOk(data: McpToolData, snippets: RetrievedSnippet[] = []): McpToolEnvelope {
  return { ok: true, data, snippets };
}

export function envelopeErr(
  code: string,
  message: string,
  retryable: boolean,
): McpToolEnvelope {
  return {
    ok: false,
    error: { code, message, retryable },
  };
}

/** Normalize a thrown value into a retryable vs non-retryable error. */
export function toRetryable(err: unknown): boolean {
  if (err instanceof Error) {
    const n = err.name?.toLowerCase() ?? '';
    const m = err.message?.toLowerCase() ?? '';
    if (n === 'typeerror' || n === 'aggregateerror') return true;
    if (m.includes('timeout') || m.includes('econnrefused') || m.includes('network')) return true;
    if (m.includes('econnreset') || m.includes('etimedout')) return true;
  }
  return false;
}
