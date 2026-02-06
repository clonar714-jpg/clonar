/**
 * MCP-backed movie retriever: calls movie_search by CAPABILITY.
 * Provider selection, auth, request formatting, and response normalization
 * live inside the MCP tool server; the app receives normalized results only.
 */
import { MovieRetriever } from '@/services/providers/movies/movie-retriever';
import type { MovieTicketFilters } from '@/types/verticals';
import { callMovieSearch } from '@/mcp/capability-client';

const DEFAULT_MAX_ITEMS = 20;

export class McpMovieRetriever implements MovieRetriever {
  constructor() {}

  getMaxItems?(): number {
    return DEFAULT_MAX_ITEMS;
  }

  async searchShowtimes(
    filters: MovieTicketFilters & { rewrittenQuery: string; preferenceContext?: string | string[] },
  ): Promise<{
    showtimes: import('@/services/providers/movies/movie-provider').MovieShowtime[];
    snippets: import('@/services/providers/retrieval-types').RetrievedSnippet[];
  }> {
    const input = {
      rewrittenQuery: filters.rewrittenQuery,
      city: filters.city,
      date: filters.date,
      ...(filters.movieTitle != null && { movieTitle: filters.movieTitle }),
      ...(filters.timeWindow != null && { timeWindow: filters.timeWindow }),
      tickets: filters.tickets,
      ...(filters.format != null && { format: filters.format }),
      ...(filters.preferenceContext != null && { preferenceContext: filters.preferenceContext }),
    };
    return callMovieSearch(input);
  }
}
