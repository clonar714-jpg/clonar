/**
 * MCP-backed flight retriever: calls flight_search by CAPABILITY.
 * Provider selection, auth, request formatting, and response normalization
 * live inside the MCP tool server; the app receives normalized results only.
 */
import { FlightRetriever } from '@/services/providers/flights/flight-retriever';
import type { FlightFilters } from '@/types/verticals';
import { callFlightSearch } from '@/mcp/capability-client';

const DEFAULT_MAX_ITEMS = 20;

export class McpFlightRetriever implements FlightRetriever {
  constructor() {}

  getMaxItems?(): number {
    return DEFAULT_MAX_ITEMS;
  }

  async searchFlights(
    filters: FlightFilters & { rewrittenQuery: string; preferenceContext?: string | string[] },
  ): Promise<{ flights: import('@/services/providers/flights/flight-provider').Flight[]; snippets: import('@/services/providers/retrieval-types').RetrievedSnippet[] }> {
    const input = {
      rewrittenQuery: filters.rewrittenQuery,
      origin: filters.origin,
      destination: filters.destination,
      departDate: filters.departDate,
      ...(filters.returnDate != null && { returnDate: filters.returnDate }),
      adults: filters.adults,
      ...(filters.cabin != null && { cabin: filters.cabin }),
      ...(filters.preferenceContext != null && { preferenceContext: filters.preferenceContext }),
    };
    return callFlightSearch(input);
  }
}
