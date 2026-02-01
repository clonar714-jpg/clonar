import { MovieTicketFilters } from '@/types/verticals';
import { MovieShowtime } from './movie-provider';
import type { RetrievedSnippet } from '../retrieval-types';

export interface MovieRetriever {
  searchShowtimes(
    filters: MovieTicketFilters & { rewrittenQuery: string; preferenceContext?: string | string[] },
  ): Promise<{
    showtimes: MovieShowtime[];
    snippets: RetrievedSnippet[];
  }>;
  getMaxItems?(): number;
}
