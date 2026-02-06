/**
 * MCP-backed hotel retriever: calls hotel_search by CAPABILITY.
 * Provider selection, auth, request formatting, and response normalization
 * live inside the MCP tool server; the app receives normalized results only.
 */
import { HotelRetriever } from '@/services/providers/hotels/hotel-retriever';
import type { HotelFilters } from '@/types/verticals';
import { callHotelSearch } from '@/mcp/capability-client';

const DEFAULT_MAX_ITEMS = 20;

export class McpHotelRetriever implements HotelRetriever {
  constructor() {}

  getMaxItems?(): number {
    return DEFAULT_MAX_ITEMS;
  }

  async searchHotels(
    filters: HotelFilters & { rewrittenQuery: string; preferenceContext?: string | string[] },
  ): Promise<{ hotels: import('@/services/providers/hotels/hotel-provider').Hotel[]; snippets: import('@/services/providers/retrieval-types').RetrievedSnippet[] }> {
    const input = {
      rewrittenQuery: filters.rewrittenQuery,
      destination: filters.destination,
      checkIn: filters.checkIn,
      checkOut: filters.checkOut,
      guests: filters.guests,
      ...(filters.budgetMin != null && { budgetMin: filters.budgetMin }),
      ...(filters.budgetMax != null && { budgetMax: filters.budgetMax }),
      ...(filters.area != null && { area: filters.area }),
      ...(filters.amenities != null && { amenities: filters.amenities }),
      ...(filters.preferenceContext != null && { preferenceContext: filters.preferenceContext }),
    };
    return callHotelSearch(input);
  }
}
